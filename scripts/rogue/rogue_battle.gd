extends "res://scripts/game.gd"
## Single-player encounters share combat and commands, but own objectives and lifecycle.
const OutpostAI = preload("res://scripts/rogue/rogue_outpost_ai.gd")
var encounter: RogueBattleDefinition
var battle_kind: String = "outpost"
var emergency: bool = false
var intro_active: bool = true
var battle_won: bool = false
var enemy_total: int = 0
var enemy_reinforcements: int = 0
var outpost_ai: OutpostAI
var wave_index: int = 0
var _ending_queued: bool = false
var _result_accepted: bool = false
var _roster_snapshot: Array = []

func command_unit_limit(owner: int) -> int:
	return Session.rogue.state.population_cap() if owner == 0 else maxi(encounter.enemy_cap, living_enemies())

func _ready() -> void:
	get_tree().auto_accept_quit = false
	assert(not Session.online, "Roguelike battles are offline")
	battle_kind = Session.rogue.state.data.battle_kind
	emergency = bool(Session.rogue.state.data.emergency) and battle_kind == "outpost"
	encounter = load("res://data/rogue/battles/%s.tres" % battle_kind)
	map_size = encounter.size
	players = [PlayerState.new(0, 0), PlayerState.new(1, 1)]
	players[0].display_name = "远征军"
	players[1].display_name = "林地守军" if battle_kind == "outpost" else "围剿部队"
	for player: PlayerState in players:
		player.gold = 0
	command_bus = MatchCommands.new(self)
	_roster_snapshot = Session.rogue.state.deployed_units().duplicate(true)
	hud.bind_game(self)
	map_instance = encounter.map_scene.instantiate()
	$MapContainer.add_child(map_instance)
	# Paused combat containers preserve their authored hierarchies during the briefing.
	_set_combat_processing(false)
	if battle_kind == "outpost":
		_spawn_outpost()
		outpost_ai = OutpostAI.new(self, encounter)
	else:
		headquarters = spawn_building("headquarters", 0, Vector3.ZERO)
		headquarters.died.connect(_on_base_destroyed)
	_spawn_roster()
	$ConstructionNavigation.refresh()
	$StaticMotionGrid.configure(map_instance, $Buildings, Rect2(-map_size * 0.5, map_size))
	$FogOfWar.configure(self, map_size)
	$FogOfWar/Overlay.hide()
	_fog_ready = true
	settings.pause_requested.connect(handle_pause_action)
	camera_rig.set_process(false)
	$Intro.animation_finished.connect(_on_intro_finished)
	game_started = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	_match_ready = true
	hud.refresh()
	$Intro.play(battle_kind)

func unit_definition_for(kind: String, owner: int) -> UnitDefinition:
	if owner == 0:
		return Session.rogue.state.unit_definition(kind)
	var definition: UnitDefinition = BalanceCatalog.unit(kind).duplicate(true)
	if emergency:
		definition.hp *= encounter.emergency_hp_multiplier
		definition.damage *= encounter.emergency_damage_multiplier
	return definition

func building_definition_for(kind: String, owner: int) -> BuildingDefinition:
	var definition: BuildingDefinition = BalanceCatalog.building(kind).duplicate(true)
	definition.produces = PackedStringArray()
	if battle_kind == "outpost" and owner == 1 and kind == "barracks":
		definition.produces = encounter.barracks_recruit_cycle.duplicate()
	if kind == "headquarters":
		definition.hp = encounter.base_hp
		definition.melee_armor = encounter.base_armor
		definition.ranged_armor = encounter.base_armor
		definition.damage = encounter.base_damage
		definition.range = encounter.base_range
		definition.cooldown = encounter.base_cooldown
	else:
		definition.hp = encounter.tower_hp if kind == "defense_tower" else encounter.barracks_hp
		definition.melee_armor = encounter.tower_armor
		definition.ranged_armor = encounter.tower_armor
		definition.damage = encounter.tower_damage if kind == "defense_tower" else 0.0
		definition.range = encounter.tower_range if kind == "defense_tower" else 0.0
		if emergency:
			definition.hp *= encounter.emergency_hp_multiplier
			definition.damage *= encounter.emergency_damage_multiplier
	return definition

func _spawn_roster() -> void:
	var origin := Vector3(-43, 0, 0) if battle_kind == "outpost" else Vector3.ZERO
	for entry: Dictionary in _roster_snapshot:
		var layout: Array = entry.layouts[battle_kind]
		var unit: BattleUnit = spawn_unit(entry.kind, 0, origin + Vector3(float(layout[0]), 0, float(layout[1])))
		unit.set_meta("roster_uid", int(entry.uid))
		unit.model_pivot.rotation.y = float(layout[2])
		unit.reset_physics_interpolation()

func _spawn_outpost() -> void:
	for marker: Marker3D in map_instance.get_node("Buildings").get_children():
		spawn_building(marker.get_meta("kind"), 1, marker.position)
	for marker: Marker3D in map_instance.get_node("Defenders").get_children():
		var unit: BattleUnit = spawn_unit(marker.get_meta("kind"), 1, marker.position)
		unit.set_meta("rogue_role", "scout" if marker.get_meta("search", false) else "guard")
	if emergency:
		for reinforcement: Dictionary in encounter.emergency_reinforcements:
			var unit: BattleUnit = spawn_unit(reinforcement.kind, 1, reinforcement.position)
			unit.set_meta("rogue_role", "guard")
	# Guards deliberately retain native IDLE: HOLD forbids chasing a shooter
	# outside melee reach. The encounter AI adds local support and guarded posts.

func spawn_unit(kind: String, faction: int, at: Vector3, id: int = 0) -> Node3D:
	var unit: Node3D = super.spawn_unit(kind, faction, at, id)
	if faction == 1:
		enemy_total += 1
	return unit

func _set_combat_processing(enabled: bool) -> void:
	var mode: ProcessMode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	$Units.process_mode = mode
	$Buildings.process_mode = mode
	$ProjectilePool.process_mode = mode
	$EffectPool.process_mode = mode

func skip_intro() -> void:
	if not intro_active or not _match_ready:
		return
	$Intro.stop()
	_on_intro_finished(battle_kind)

func _on_intro_finished(_name: StringName) -> void:
	if not intro_active:
		return
	intro_active = false
	game_started = true
	camera_rig.focus_at(Vector3(-25, 0, 0) if battle_kind == "outpost" else Vector3.ZERO, true)
	camera_rig.zoom_target = 35.0 if battle_kind == "outpost" else 43.0
	camera.size = camera_rig.zoom_target
	camera_rig.set_process(true)
	$FogOfWar.apply_visibility(local_owner_id)
	$FogOfWar/Overlay.show()
	_set_combat_processing(true)
	select_army()
	hud.refresh()

func _physics_process(delta: float) -> void:
	if not _match_ready or intro_active or finished:
		return
	$FogOfWar.tick(delta)
	command_bus.tick()
	simulation_tick += 1
	elapsed += delta
	if battle_kind == "siege":
		while wave_index < encounter.waves.size() and elapsed >= float(encounter.waves[wave_index].time):
			_spawn_siege_wave(encounter.waves[wave_index])
			wave_index += 1
		if elapsed >= encounter.duration and not _ending_queued:
			_ending_queued = true
			# Resolve after all native unit and projectile ticks; base destruction wins ties.
			_resolve_deadline.call_deferred()
	else:
		outpost_ai.tick(delta)
		check_victory()

func _process(delta: float) -> void:
	if not intro_active:
		if _fog_ready:
			$FogOfWar.apply_visibility(local_owner_id)
	_ui_accumulator += delta
	if _ui_accumulator >= 0.12:
		_ui_accumulator = 0.0
		_prune_selection()
		hud.refresh()
	if dragging:
		overlay.box_end = get_viewport().get_mouse_position()
		overlay.box_visible = overlay.box_start.distance_to(overlay.box_end) > 6.0

func _spawn_siege_wave(wave: Dictionary) -> void:
	var capacity: int = maxi(0, encounter.enemy_cap - living_enemies())
	var spawned: int = 0
	var entries: Array = wave.units
	for index: int in mini(entries.size(), capacity):
		var marker: Marker3D = map_instance.get_node("Entrances").get_child((index + wave_index) % 4)
		var side: Vector3 = Vector3(-marker.position.z, 0, marker.position.x).normalized()
		var at: Vector3 = marker.position + side * (floori(float(index) / 4.0) - 1.0) * 2.6
		var unit: BattleUnit = spawn_unit(str(entries[index]), 1, at)
		unit.issue_move(Vector3.ZERO, true)
		spawned += 1
	hud.toast("第 %d 波围剿 · %d 名敌军正从林间接近" % [wave_index + 1, spawned], 3.5)

func living_enemies() -> int:
	var amount: int = 0
	for unit: BattleUnit in $Units.get_children():
		if unit.alive and unit.owner_id == 1:
			amount += 1
	return amount

func living_enemy_barracks() -> int:
	return owned_entities(1, "buildings").filter(func(building: BattleBuilding): return building.building_type == "barracks").size()

func remaining_buildings() -> int:
	var amount: int = 0
	for building: BattleBuilding in $Buildings.get_children():
		if building.alive and building.owner_id == 1:
			amount += 1
	return amount

func check_victory() -> void:
	if finished or intro_active or not _match_ready:
		return
	if battle_kind == "siege":
		if not headquarters.alive:
			end_battle(false)
		return
	if player_count() == 0:
		end_battle(false)
	elif living_enemies() == 0 and remaining_buildings() == 0:
		end_battle(true)

func _on_base_destroyed(_entity: Node3D) -> void:
	end_battle(false)

func _resolve_deadline() -> void:
	if not finished:
		end_battle(headquarters.alive)

func end_battle(victory: bool, _winner: int = -2) -> void:
	if finished:
		return
	finished = true
	battle_won = victory
	_set_combat_processing(false)
	$ProjectilePool.reset_all()
	$EnemyTimer.stop()
	$IncomeTimer.stop()
	for unit: BattleUnit in $Units.get_children():
		if unit.alive:
			unit.hold()
			unit.attack_windup.stop()
			unit.navigation_agent.avoidance_enabled = false
	$Audio.play_ui(&"victory" if victory else &"defeat")
	hud.show_result(victory, elapsed, kills)

func accept_result() -> void:
	if not finished or _result_accepted:
		return
	_result_accepted = true
	get_tree().paused = false
	await prepare_shutdown()
	Session.rogue.resolve_battle(battle_won)

func handle_pause_action() -> void:
	if intro_active or finished:
		return
	if settings.is_open():
		settings.close_menu()
	toggle_pause()

func return_to_menu() -> void:
	if _closing:
		return
	_closing = true
	get_tree().paused = false
	await prepare_shutdown()
	Session.back_to_lobby()

func _input(event: InputEvent) -> void:
	if settings.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = settings.resolve_key(event)
		if key == KEY_ESCAPE or key == KEY_F5:
			if intro_active:
				skip_intro()
			elif attack_mode:
				set_attack_mode(false)
			else:
				handle_pause_action()
			get_viewport().set_input_as_handled()
		elif key == KEY_F11:
			settings.toggle_fullscreen()
	if intro_active or finished or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		camera_rig.dragging = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and camera_rig.dragging:
		camera_rig.drag_by(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		dragging = false
		overlay.box_visible = false
		_finish_selection(event.position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if intro_active or finished or get_tree().paused or settings.is_open():
		return
	# Reuse production RTS pointing. Restrict keys to combat commands only.
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		super._unhandled_input(event)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = settings.resolve_key(event)
		if key >= KEY_1 and key <= KEY_9:
			use_control_group(key - KEY_0, event.ctrl_pressed, event.shift_pressed)
		match key:
			KEY_A: set_attack_mode(true)
			KEY_S: stop_selected()
			KEY_H: hold_selected(event.shift_pressed)
			KEY_G, KEY_F2: select_army()
			KEY_SPACE: focus_selection()
			KEY_HOME: select_headquarters()
			KEY_TAB: hud.cycle_selection_group(event.shift_pressed)

func submit_local(command: Dictionary) -> Dictionary:
	if str(command.get("kind", "")) not in ["move", "attack", "support", "stop", "hold"]:
		return {"ok": false, "error": "本次作战仅可指挥已部署部队"}
	return super.submit_local(command)
