extends "res://scripts/game.gd"
## A separate scenario lifecycle reuses the native RTS simulation and render pools.
const DECK := preload("res://data/moba/test1_deck.tres")
const HERO := preload("res://scenes/moba/hero.tscn")
const HERO_STATS := preload("res://data/sandbox/heroes/capsule.tres")
const MAP := preload("res://scenes/moba/test1_map.tscn")
const HEALTH_MATERIAL := preload("res://assets/ui/moba/health_bar.tres")
const ARMY_CAP := 240
const WAVE: PackedStringArray = ["spearman", "spearman", "archer", "archer", "archer", "swordsman"]
const FORTS := {
	"headquarters": preload("res://data/moba/buildings/headquarters.tres"),
	"heavy_fortress": preload("res://data/moba/buildings/heavy_fortress.tres"),
	"castle": preload("res://data/moba/buildings/castle.tres"),
	"cannon_tower": preload("res://data/moba/buildings/cannon_tower.tres"),
}
## Zero chooses a fresh shuffle; an explicit value reproduces balance experiments.
@export var shuffle_seed: int = 0
var running: bool = false
var hands: Array[MobaCardHand] = []
var heroes: Array[MobaHero] = [null, null]
var bases: Array[BattleBuilding] = []
var fronts: Array = [[], []]
var army_counts := PackedInt32Array([0, 0])
var wave_due := PackedFloat64Array([8, 8])
var wave_counts := PackedInt32Array([0, 0])
var respawn_at := PackedFloat64Array([0, 0])
var card_plays := PackedInt32Array([0, 0])
var earned_gold := PackedInt32Array([0, 0])
var _settings_running: bool = false
var _wave_retry := PackedFloat64Array([0, 0])
var _hero_retry := PackedFloat64Array([0, 0])
@onready var hero_controller = $HeroController

func _ready() -> void:
	get_tree().auto_accept_quit = false
	assert(not Session.online, "test1 is a local match")
	map_size = Vector2(200, 56)
	players = [PlayerState.new(0, 0), PlayerState.new(1, 1)]
	players[0].display_name = HeroProfile.read_profile().name
	players[1].display_name = "林地守军"
	if shuffle_seed == 0: shuffle_seed = randi_range(1, 2147483647)
	for owner: int in 2:
		players[owner].gold = DECK.starting_gold
		hands.append(MobaCardHand.new(DECK, shuffle_seed + owner * 997))
	command_bus = MatchCommands.new(self)
	map_instance = MAP.instantiate()
	$MapContainer.add_child(map_instance)
	for owner: int in 2:
		var markers: Node3D = map_instance.get_node("Spawns/Left" if owner == 0 else "Spawns/Right")
		var base := spawn_building("headquarters", owner, markers.get_node("HQ").position)
		base.rally_point = base.position + Vector3(15 if owner == 0 else -15, 0, 0)
		bases.append(base)
		fronts[owner] = [[], [], [], [base]]
		fronts[owner][2].append(spawn_building("heavy_fortress", owner, markers.get_node("Fortress").position))
		fronts[owner][1].append(spawn_building("castle", owner, markers.get_node("Castle").position))
		for lane: String in ["NorthTower", "SouthTower"]: fronts[owner][0].append(spawn_building("cannon_tower", owner, markers.get_node(lane).position))
	$ConstructionNavigation.refresh()
	$StaticMotionGrid.configure(map_instance, $Buildings, Rect2(-map_size * .5, map_size))
	hud.bind_game(self)
	hero_controller.bind(self)
	settings.opened.connect(_settings_opened)
	settings.closed.connect(_settings_closed)
	settings.pause_requested.connect(_toggle_view)
	camera_rig.focus_at(Vector3(-62, 0, 0), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	while $ConstructionNavigation.is_rebuilding(): await get_tree().physics_frame
	await get_tree().physics_frame
	_match_ready = true
	for owner: int in 2: _spawn_hero(owner)
	game_started = true
	set_running(true)
	hud.toast("双击卡牌或拖向战场派兵 · 右键指挥英雄 · E / R 技能", 8)

func building_definition_for(kind: String, _owner: int) -> BuildingDefinition:
	return FORTS[kind]

func register_entity(entity: Node3D) -> void:
	super.register_entity(entity)
	entity.health_bar.material_override = HEALTH_MATERIAL
	if entity is BattleUnit and not entity is HeroUnit: army_counts[entity.owner_id] += 1

func command_unit_limit(_owner: int) -> int: return ARMY_CAP + 1
func can_see_entity(_owner: int, entity: Node3D) -> bool: return is_instance_valid(entity) and entity.alive
func can_see_position(_owner: int, _at: Vector3) -> bool: return true

func local_hero() -> MobaHero:
	return heroes[0] if is_instance_valid(heroes[0]) and heroes[0].alive else null

func _spawn_hero(owner: int) -> bool:
	var places := find_spawn_slots(PackedStringArray(["hero"]), owner)
	if places.is_empty(): return false
	var hero: MobaHero = HERO.instantiate()
	attach_unit(hero, owner, places[0])
	var profile := HeroProfile.read_profile() if owner == 0 else HeroProfile.defaults()
	profile.faction = owner
	profile.team_clothes = true
	if owner == 1: profile.name = "守林者"; profile.headwear = 1
	hero.display_name = profile.name
	(hero._model as HeroVisual).apply_appearance(profile)
	hero.model_pivot.rotation.y = -PI / 2 if owner == 0 else PI / 2
	heroes[owner] = hero
	respawn_at[owner] = 0
	if owner == 0:
		hero_controller.adopt(hero)
		select_entities([hero])
		hud.sync_hero(profile)
	return true

func find_spawn_slots(kinds: PackedStringArray, owner: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var reserved_radii: Array[float] = []
	var forward := 1.0 if owner == 0 else -1.0
	var live_units: Array = unit_container.get_children().filter(func(unit: BattleUnit): return unit.alive)
	for kind: String in kinds:
		var stats: UnitDefinition = HERO_STATS if kind == "hero" else BalanceCatalog.unit(kind)
		var found := false
		for row: int in 5:
			if found: break
			for z: float in [0.0, -2.0, 2.0, -4.0, 4.0, -6.0, 6.0]:
				var at: Vector3 = bases[owner].position + Vector3(forward * (7.0 + row * 1.7), 0, z)
				if not $ConstructionNavigation.contains_walkable_point(at): continue
				var free := true
				for index: int in result.size():
					if at.distance_to(result[index]) < stats.radius + reserved_radii[index] + .22: free = false; break
				if not free: continue
				for unit: BattleUnit in live_units:
					if at.distance_to(unit.position) < stats.radius + unit.radius + .22: free = false; break
				if free:
					result.append(at)
					reserved_radii.append(stats.radius)
					found = true
					break
		if not found: return []
	return result

func spawn_army(kinds: PackedStringArray, owner: int) -> bool:
	if army_counts[owner] + kinds.size() > ARMY_CAP: return false
	var places := find_spawn_slots(kinds, owner)
	if places.size() != kinds.size(): return false
	for index: int in kinds.size():
		var unit: BattleUnit = spawn_unit(kinds[index], owner, places[index])
		unit.set_meta("moba_lane", (unit.entity_id % 2) * 2 - 1)
		$Director.enlist(unit)
	spawn_effect(places[0], "spawn", Color("80d6ba") if owner == 0 else Color("ec968c"))
	return true

func card_error(owner: int, index: int, uid: int) -> String:
	if not running or not _match_ready or finished: return "对局暂停中"
	if owner < 0 or owner >= hands.size() or index < 0 or index >= DECK.hand_size: return "卡牌无效"
	var entry: Dictionary = hands[owner].slots[index]
	if entry.card == null or entry.uid != uid: return "卡牌已更新"
	var card: MobaCardDefinition = entry.card
	if card.type != MobaCardDefinition.Type.ARMY: return "此类型暂未开放"
	if players[owner].gold < card.cost: return "金币不足"
	if army_counts[owner] + card.units.size() > ARMY_CAP: return "前线部队已满"
	return ""

func play_card(owner: int, index: int, uid: int) -> bool:
	var error := card_error(owner, index, uid)
	if not error.is_empty():
		if owner == 0: hud.toast(error)
		return false
	var card: MobaCardDefinition = hands[owner].slots[index].card
	# Reserve all positions before mutating money or card identity.
	if not spawn_army(card.units, owner):
		if owner == 0: hud.toast("大本营出口拥挤，请稍后再试")
		return false
	players[owner].gold -= card.cost
	hands[owner].consume(index)
	card_plays[owner] += 1
	if owner == 0:
		$Audio.play_ui(&"order")
		hud.toast("%s已从大本营出发" % card.title, 2)
	hud.refresh()
	return true

func on_entity_died(entity: Node3D) -> void:
	if entity.get_meta("moba_death_settled", false): return
	entity.set_meta("moba_death_settled", true)
	if entity is HeroUnit:
		respawn_at[entity.owner_id] = elapsed + 15.0
		if entity.owner_id == 0: hero_controller.release_hero()
	elif entity is BattleUnit:
		army_counts[entity.owner_id] -= 1
		var bounty := maxi(5, roundi(entity._stats.cost * .2))
		for player: PlayerState in players:
			if player.alliance_id != entity.alliance_id:
				player.gold += bounty
				earned_gold[player.owner_id] += bounty
	super.on_entity_died(entity)
	if entity is BattleBuilding and entity.building_type == "headquarters":
		end_battle(entity.owner_id != 0)

func _physics_process(delta: float) -> void:
	if not _match_ready or not running or finished: return
	elapsed += delta
	simulation_tick += 1
	command_bus.tick()
	$StatusEffects.advance(delta)
	for hand: MobaCardHand in hands: hand.advance(delta)
	for owner: int in 2:
		if elapsed + .000001 >= maxf(wave_due[owner], _wave_retry[owner]):
			if spawn_army(WAVE, owner):
				wave_counts[owner] += 1
				wave_due[owner] = elapsed + 8.0
			else: _wave_retry[owner] = elapsed + .25
		if respawn_at[owner] > 0 and elapsed + .000001 >= maxf(respawn_at[owner], _hero_retry[owner]):
			if not _spawn_hero(owner): _hero_retry[owner] = elapsed + .25
	$Director.advance(delta)

func _process(delta: float) -> void:
	if not _match_ready: return
	_ui_accumulator += delta
	if _ui_accumulator >= .1:
		_ui_accumulator = 0
		hud.refresh()

func set_running(value: bool) -> void:
	running = value and not finished
	$Audio.set_world_paused(not running)
	for path: String in ["Units", "Buildings", "ProjectilePool", "EffectPool"]:
		get_node(path).process_mode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED
	if not running and local_hero() != null: local_hero().trigger_held = false
	if _match_ready: hud.refresh()

func select_entities(entities: Array, _additive: bool = false, _toggle: bool = false) -> void:
	super.select_entities(entities.filter(func(unit): return unit == local_hero()))

func submit_local(command: Dictionary) -> Dictionary:
	var hero := local_hero()
	if hero == null or not running or str(command.get("kind", "")) not in ["move", "attack", "stop", "hold"]:
		return {"ok": false, "error": "只能指挥自己的英雄"}
	for id: int in command.get("units", []):
		if id != hero.entity_id: return {"ok": false, "error": "军队由兵线指挥器控制"}
	return super.submit_local(command)

func _toggle_view() -> void:
	if _match_ready and not finished: hero_controller.toggle_view()

func _input(event: InputEvent) -> void:
	if not _match_ready or settings.is_open(): return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_ESCAPE:
			if get_viewport().gui_is_dragging(): return
			hud.toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F11: settings.toggle_fullscreen(); return
		if not running: return
		if key == KEY_F5: hero_controller.toggle_view()
		elif key == KEY_E: cast_skill(0)
		elif key == KEY_R: cast_skill(1)
		elif key >= KEY_1 and key <= KEY_5:
			var slot := key - KEY_1
			play_card(0, slot, hands[0].slots[slot].uid)
		elif key == KEY_SPACE and not hero_controller.first_person: focus_hero()
		else:
			if hero_controller.handle_input(event): get_viewport().set_input_as_handled()
			return
		get_viewport().set_input_as_handled()
	elif running and hero_controller.handle_input(event): get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not running or settings.is_open() or hero_controller.first_person: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE: camera_rig.dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_rig.zoom_by(-3)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_rig.zoom_by(3)
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var hero := local_hero()
			if hero == null: return
			select_entities([hero])
			var target := entity_at(event.position)
			if is_instance_valid(target) and target.alliance_id != 0: command_attack(target, event.shift_pressed)
			else: command_move(camera_rig.world_at(event.position), false, event.shift_pressed)
	elif event is InputEventMouseMotion and camera_rig.dragging: camera_rig.drag_by(event.relative)

func cast_skill(index: int) -> bool:
	var hero := local_hero()
	if hero == null or not running: return false
	var cast := hero.cast_recovery() if index == 0 else hero.cast_morale()
	if cast: hud.refresh()
	return cast

func focus_hero() -> void:
	if local_hero() != null: camera_rig.focus_at(local_hero().position)

func _settings_opened() -> void:
	_settings_running = running
	set_running(false)
	hero_controller.capture_mouse(false)

func _settings_closed() -> void:
	set_running(_settings_running)
	if running and hero_controller.first_person: hero_controller.capture_mouse(true)

func handle_pause_action() -> void: hud.toggle_pause()

func end_battle(victory: bool, _winner: int = -2) -> void:
	if finished: return
	finished = true
	set_running(false)
	hero_controller.set_first_person(false)
	$ProjectilePool.reset_all()
	$EffectPool.reset_all()
	for unit: BattleUnit in unit_container.get_children(): unit.navigation_agent.avoidance_enabled = false
	hud.show_result(victory, elapsed, kills)
	$Audio.play_ui(&"victory" if victory else &"defeat")

func restart() -> void:
	if _closing: return
	_closing = true
	await prepare_shutdown()
	get_tree().reload_current_scene()

func return_to_menu() -> void:
	if _closing: return
	_closing = true
	await prepare_shutdown()
	Session.back_to_lobby()

func prepare_shutdown() -> void:
	hero_controller.set_first_person(false)
	hero_controller.capture_mouse(false)
	$StatusEffects.reset()
	await super.prepare_shutdown()
