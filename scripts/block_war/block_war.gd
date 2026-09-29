extends Node3D
## Building-node conquest. Population is simulated here; marches only transport it.

signal presentation_event(kind: String, payload: Dictionary)

const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺", "能量塔"]
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const COMBAT_RULES := preload("res://scripts/block_war/war_combat_rules.gd")
const SKILL_COOLDOWNS := SKILL_RULES.COOLDOWNS
const SKILL_DURATIONS := SKILL_RULES.DURATIONS
const SKILL_ENERGY_COSTS := SKILL_RULES.COSTS
const ENERGY_MAX := SKILL_RULES.ENERGY_MAX
const ENERGY_REGEN := SKILL_RULES.ENERGY_REGEN
const RECRUIT_RATE := SKILL_RULES.RECRUIT_RATE
const IMPACT_RADIUS := SKILL_RULES.FIRE_RADIUS
const IMPACT_DAMAGE := SKILL_RULES.FIRE_DAMAGE
const CONVERSION_COST := 20
const PLAYER := 0
const ENEMY := 1
const AI_STRATEGY := preload("res://scripts/block_war/war_ai.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const MAP_CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const MORALE := preload("res://scripts/block_war/war_morale.gd")
const DEBUG_DATA := preload("res://scripts/block_war/war_debug_data.gd")
var morale := MORALE.new()
const RABBIT_SKILLS := preload("res://scripts/block_war/war_rabbit_skills.gd")
const BEAR_SKILLS := preload("res://scripts/block_war/war_bear_skills.gd")
const FROG_SKILLS := preload("res://scripts/block_war/war_frog_skills.gd")
const FOX_SKILLS := preload("res://scripts/block_war/war_fox_skills.gd")
const PIG_SKILLS := preload("res://scripts/block_war/war_pig_skills.gd")
const FIRE_STATE := preload("res://scripts/block_war/war_fire_state.gd")
const SURRENDER := preload("res://scripts/block_war/war_surrender.gd")
var bear := BEAR_SKILLS.new()
var pig := PIG_SKILLS.new()

class SkillState extends RefCounted:
	var commander: StringName = &"squirrel"
	var energy: float = SKILL_RULES.ENERGY_INITIAL
	var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
	# Remote accounts publish only these states, never energy or countdowns.
	var public_statuses: Array[int] = [1, 1, 1, 1]
	var durations: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var recruit_target_id := -1

var faction_skills: Array[SkillState] = []
var local_faction := 0:
	set(value):
		local_faction = value
		for building: WarBuilding in buildings:
			building.viewer_faction = value
var local_team: int:
	get: return local_faction % 2
var local_player_id := -1
var online_host := false
var match_config: Dictionary = {}
var network_match: RefCounted
var simulation_paused := false
var match_paused := false
var pause_faction := -1
var surrendered_factions: Array[int] = []
var initial_human_factions: Array[int] = []
var winner_team := -2
var _ai_by_faction: Dictionary[int, RefCounted] = {}
var _bot_factions: Array[int] = []
# The input layer and HUD expose only the human commander's account.
var cooldowns: Array[float]:
	get: return faction_skills[local_faction].cooldowns
var active_durations: Array[float]:
	get: return faction_skills[local_faction].durations
var energy: float:
	get: return faction_skills[local_faction].energy
	set(value): faction_skills[local_faction].energy = value

var buildings: Array[Node3D] = []
var by_id: Dictionary = {}
var selected: Node3D
var drag_source: Node3D
var hovered: Node3D
var percentage: int = 50
var elapsed: float = 0.0
var armed_skill: int = -1
var _skill_keycode := 0
var ground_skill_target := Vector3.INF
var finished: bool = false
var _local_menu: bool = false
var ai_enabled: bool = true
var ai_clock: float = 6.0
var _ai_strategy := AI_STRATEGY.new()
var _other_ai: Array[RefCounted] = []
var faction_count := 2
var shields: Dictionary = {}
var tower_clocks: Dictionary = {}
var effects: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var fire_states: Array[RefCounted] = []
var _next_fire_id := 1
var order_route := PackedVector3Array()
var _hud_clock: float = 0.0
var _drag_start := Vector2.ZERO
var _match_ready: bool = false
var _previous_taa: bool = false
var _previous_auto_quit: bool = true
var _closing: bool = false
var recall_preview: Array[Dictionary] = []
var rush_preview: Array[WarMarches.MarchUnit] = []
var frog_preview: Array[WarMarches.MarchUnit] = []
var fox_preview: Array[WarMarches.MarchUnit] = []
var _recall_preview_center := Vector3.INF
var _rabbit_preview_time := -1.0

@onready var map: Node3D = $Map
@onready var marches: Node3D = $Marches
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var hud: CanvasLayer = $HUD
@onready var audio: Node = $Audio
@onready var overlay: Control = $Orders/Overlay
@onready var world_effects: Node3D = $Effects

func _enter_tree() -> void:
	var definition: Resource = MAP_CATALOG.find_map(get_node("/root/Session").block_war_map_id)
	assert(definition != null, "The selected battlefield must exist in the catalog.")
	if definition.map_id != "rift":
		# Replace one complete authored scene, before any map child becomes ready.
		var original := get_node("Map")
		remove_child(original)
		original.free()
		var replacement: Node3D = load(definition.scene_path).instantiate()
		replacement.name = "Map"
		add_child(replacement)
		move_child(replacement, 0)
	faction_count = definition.team_size * 2
	morale.configure(faction_count)
	for faction: int in faction_count:
		var state := SkillState.new()
		state.commander = get_node("/root/Session").block_war_commander if faction % 2 == 0 else get_node("/root/Session").block_war_opponent_commander
		faction_skills.append(state)
	for faction: int in range(2, faction_count):
		_other_ai.append(AI_STRATEGY.new(faction))
	_ai_by_faction[0] = AI_STRATEGY.new(0)
	_ai_by_faction[1] = _ai_strategy
	for strategy: RefCounted in _other_ai:
		_ai_by_faction[strategy.faction] = strategy
	for faction: int in range(1, faction_count):
		_bot_factions.append(faction)
	var online := get_node_or_null("/root/Session/Online")
	if online != null and not online.match_config.is_empty():
		configure_match(online.match_config, online.player_id)

func configure_match(config: Dictionary, player_id: int) -> void:
	# Seat, controller, team and commander are independent. Reconnection updates
	# controllers separately so no population, cooldown or AI plan gets reset.
	assert(config.slots.size() == faction_count)
	match_config = config.duplicate(true)
	local_player_id = player_id
	online_host = int(config.host_player_id) == player_id
	var found := false
	for slot: Dictionary in config.slots:
		var faction := int(slot.faction_id)
		assert(faction >= 0 and faction < faction_count and int(slot.team_id) == faction % 2)
		faction_skills[faction].commander = StringName(slot.commander)
		if slot.kind == "human" and faction not in initial_human_factions:
			initial_human_factions.append(faction)
		if int(slot.player_id) == player_id and slot.kind == "human":
			local_faction = faction
			found = true
	assert(found, "A match participant must occupy one authored faction seat.")
	configure_controllers(config.slots)

func configure_controllers(slots: Array) -> void:
	_bot_factions.clear()
	for slot: Dictionary in slots:
		if slot.controller == "bot" and int(slot.faction_id) not in surrendered_factions:
			_bot_factions.append(int(slot.faction_id))
	if not match_config.is_empty():
		match_config.slots = slots.duplicate(true)

func is_rule_paused() -> bool:
	return simulation_paused or match_paused or (match_config.is_empty() and _local_menu)

func is_authority() -> bool:
	return match_config.is_empty() or online_host

func has_surrendered(faction: int) -> bool:
	return faction in surrendered_factions

func can_request_match_control(faction: int) -> bool:
	return not match_config.is_empty() and not simulation_paused and not finished and not _closing and faction in initial_human_factions and not has_surrendered(faction)

func set_match_paused(value: bool, requester_faction: int) -> Dictionary:
	if not is_authority() or not can_request_match_control(requester_faction):
		return {"accepted": false, "reason": "当前身份不能暂停对局"}
	if match_paused == value:
		return {"accepted": true, "reason": "", "changed": false}
	match_paused = value
	pause_faction = requester_faction if value else -1
	sync_match_control_presentation()
	return {"accepted": true, "reason": "", "changed": true}

func surrender_faction(faction: int) -> Dictionary:
	if not is_authority() or not can_request_match_control(faction):
		return {"accepted": false, "reason": "当前身份不能投降"}
	surrendered_factions.append(faction)
	surrendered_factions.sort()
	_bot_factions.erase(faction)
	var recipients: Array[int] = []
	for slot: Dictionary in match_config.slots:
		var other := int(slot.faction_id)
		# A temporary AI takeover preserves a human seat; expired identities do not.
		if slot.kind == "human" and not slot.get("forfeit_requested", false) and other in initial_human_factions and FACTIONS.allied(faction, other) and not has_surrendered(other):
			recipients.append(other)
	if recipients.is_empty():
		_finish_match(1 - faction % 2)
		return {"accepted": true, "reason": "", "defeated": true}
	var transfer: Dictionary = SURRENDER.transfer(self, faction, recipients)
	sync_match_control_presentation()
	return {"accepted": true, "reason": "", "defeated": false, "transfer": transfer}

func sync_match_control_presentation() -> void:
	# Transport signals can arrive while the native audio teardown is awaiting release.
	if _closing: return
	_cancel_drag()
	_cancel_skill_drag()
	camera_rig.dragging = false
	var paused := is_rule_paused() or finished
	audio.set_world_paused(paused)
	world_effects.set_running(not paused)
	map.set_visual_paused(paused)
	for building: WarBuilding in buildings: building.set_visual_paused(paused)
	update_hud()

func opponent_faction() -> int:
	return 1 - local_team

func faction_name(faction: int) -> String:
	if faction < 0:
		return "中立"
	if not match_config.is_empty():
		for slot: Dictionary in match_config.slots:
			if int(slot.faction_id) == faction:
				return "%s（你）" % slot.name if faction == local_faction else str(slot.name)
	return FACTIONS.NAMES[faction]

func _enemy_role() -> String:
	if match_config.is_empty():
		return "%d 名电脑对手" % (faction_count / 2)
	var humans := 0
	var bots := 0
	for slot: Dictionary in match_config.slots:
		if int(slot.team_id) == local_team:
			continue
		if slot.controller == "bot":
			bots += 1
		else:
			humans += 1
	return "%d 名玩家 · %d 名电脑" % [humans, bots]

func _ready() -> void:
	# MSAA keeps the small world-space badges and moving spear rows crisp.
	# TAA retains old Label3D glyphs when the garrison count changes.
	_previous_taa = get_viewport().use_taa
	get_viewport().use_taa = false
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	for building: Node3D in $Map/Buildings.get_children():
		building.viewer_faction = local_faction
		buildings.append(building)
		by_id[building.building_id] = building
		tower_clocks[building.building_id] = 0.0
		building.construction_completed.connect(_on_building_completed.bind(building))
	morale.changed.connect(_on_morale_changed)
	for faction: int in faction_count:
		_on_morale_changed(faction)
	marches.unit_arrived.connect(_on_unit_arrived)
	marches.combat_death.connect(_on_march_combat_death)
	marches.departure_queue_changed.connect(_on_departure_queue_changed)
	marches.unit_departed.connect(_on_unit_departed)
	world_effects.get_node("Rabbit").tunnel_opened.connect(func(at: Vector3): audio.play_world(&"war_rabbit_burrow", at))
	marches.unit_defeated.connect(_on_unit_defeated)
	hud.debug_refresh_requested.connect(refresh_debug_panel)
	hud.debug_visibility_changed.connect(_on_debug_visibility_changed)
	hud.percentage_changed.connect(set_percentage)
	hud.skill_requested.connect(request_skill)
	hud.pause_requested.connect(set_paused.bind(true))
	hud.match_pause_requested.connect(func(value: bool): submit_player_command({"type": "pause", "paused": value}))
	hud.surrender_requested.connect(func(): submit_player_command({"type": "surrender"}))
	hud.resume_requested.connect(set_paused.bind(false))
	hud.restart_requested.connect(restart)
	hud.exit_requested.connect(exit_to_lobby)
	hud.upgrade_requested.connect(upgrade_selected)
	hud.convert_requested.connect(convert_selected)
	hud.ui_sound_requested.connect(audio.play_ui)
	get_window().focus_exited.connect(_on_focus_exited)
	marches.map_definition = map.definition
	world_effects.configure_surface(map.definition)
	camera_rig.maximum_zoom = maxf(95.0, map.definition.half_size.y * 2.1)
	camera_rig.configure_bounds(map.definition.camera_bounds)
	var home: Node3D
	for building: Node3D in buildings:
		if building.faction == local_faction:
			home = building
			break
	if map.definition.size_class > 0 or not match_config.is_empty():
		camera_rig.focus_at(home.global_position, true)
		camera.far = 320.0
	select_building(home)
	_match_ready = true
	update_hud()
	hud.notify("拖动自己的住宅到中立据点，派出你的第一支民兵。")
	if not match_config.is_empty():
		network_match = load("res://scripts/network/war_network_match.gd").new()
		network_match.setup(self, get_node("/root/Session/Online"))

func _exit_tree() -> void:
	get_viewport().use_taa = _previous_taa
	get_tree().auto_accept_quit = _previous_auto_quit

func _process(delta: float) -> void:
	if network_match != null:
		network_match.process(delta)
	elif not is_rule_paused() and not finished:
		simulate(delta)
	_hud_clock -= delta
	if _hud_clock <= 0.0:
		_hud_clock = 0.1
		update_hud()
	if drag_source != null:
		_update_drag(get_viewport().get_mouse_position())
	elif armed_skill >= 0:
		_update_skill_drag(get_viewport().get_mouse_position())
	overlay.queue_redraw()

func simulate(delta: float) -> void:
	if not is_authority() or is_rule_paused() or finished or delta <= 0.0:
		return
	# Integrate up to each completion before applying the next level's rules.
	# Long frames and multiple simultaneous builds keep the same production as
	# small steps, including a recruitment skill crossing the completion time.
	marches.begin_render_batch()
	var remaining := delta
	while remaining > 0.0 and not finished:
		sync_environment_bonuses()
		var step := remaining
		if elapsed < SKILL_RULES.ENERGY_ACCELERATION_TIME:
			step = minf(step, SKILL_RULES.ENERGY_ACCELERATION_TIME - elapsed)
		if ai_enabled:
			step = minf(step, maxf(ai_clock, 0.000001))
		if marches.has_marchers() or not projectiles.is_empty() or world_effects.has_fire():
			step = minf(step, 0.05)
		step = minf(step, marches.departure_step_limit())
		step = minf(step, morale.step_limit())
		step = minf(step, world_effects.fire_step_limit())
		step = minf(step, bear.step_limit())
		step = minf(step, pig.step_limit())
		for shield_remaining: float in shields.values():
			step = minf(step, shield_remaining)
		for building: WarBuilding in buildings:
			if building.is_constructing:
				step = minf(step, building.construction_remaining)
			if building.disruption_remaining > 0.0:
				step = minf(step, building.disruption_remaining)
		_simulate_step(step)
		remaining = maxf(0.0, remaining - step)
	marches.end_render_batch()

func _simulate_step(delta: float) -> void:
	sync_environment_bonuses()
	morale.begin_step()
	var natural_energy := SKILL_RULES.natural_energy_between(elapsed, delta)
	elapsed += delta
	var recruiting := _tick_recruitment(delta)
	for faction: int in faction_count:
		var state := faction_skills[faction]
		state.energy = minf(ENERGY_MAX, state.energy + natural_energy + SKILL_RULES.energy_tower_bonus(energy_tower_count(faction)) * delta)
		for index: int in 4:
			state.cooldowns[index] = maxf(0.0, state.cooldowns[index] - delta)
			state.durations[index] = maxf(0.0, state.durations[index] - delta)
	for building: Node3D in buildings:
		# Reinforcement can exceed the soft cap. Only automatic growth stops there.
		if building.faction >= 0 and building.kind == 0 and building.population < building.capacity and not recruiting.has(building.building_id) and building.disruption_remaining <= 0.0:
			building.population = minf(building.capacity, building.population + building.production_rate * delta)
		if building.faction >= 0 and building.kind == 1:
			tower_clocks[building.building_id] = maxf(0.0, float(tower_clocks[building.building_id]) - delta)
			if tower_clocks[building.building_id] <= 0.0 and building.disruption_remaining <= 0.0:
				_fire_tower(building)
		building.refresh_visual()
	marches.tick(delta, world_effects.fire_segments(delta))
	_tick_projectiles(delta)
	bear.tick_projectiles(self, delta)
	audio.tick_marches(delta, marches)
	_advance_fire_states(delta)
	world_effects.tick(delta)
	_tick_fire_buildings()
	pig.advance(self, delta)
	# Damage in this interval still belongs to the shield's last active span.
	# The next substep starts after its expiry, with protection already removed.
	for id: int in shields.keys():
		shields[id] = maxf(0.0, float(shields[id]) - delta)
		if shields[id] <= 0.0:
			shields.erase(id)
	world_effects.update_skills(delta, faction_skills, shields, by_id, marches)
	morale.end_step(delta)
	for index: int in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0.0:
			effects.remove_at(index)
	for building: WarBuilding in buildings:
		# End-of-step restoration: movement and already-fired projectiles still
		# belong to the interval during which the building was disabled.
		building.advance_burrow(delta)
		var restored := building.advance_disruption(delta)
		if restored and building.faction >= 0 and building.kind == 1 and tower_clocks[building.building_id] <= 0.0:
			_fire_tower(building)
		var converting := building.conversion_target >= 0
		if building.advance_construction(delta):
			if converting and building.kind != 0:
				_cancel_building_recruitment(building.building_id)
			audio.play_world(&"war_upgrade", building.global_position)
			if building.faction == local_faction:
				hud.notify("改建完成 · %s" % KIND_NAMES[building.kind] if converting else "%s已升至 %d 级" % [KIND_NAMES[building.kind], building.level])
			update_hud()
	sync_environment_bonuses()
	bear.advance(self, delta)
	world_effects.get_node("Frog").sync(marches, delta)
	_check_victory()
	# Orders are decisions at the end of this step. New construction must not
	# receive the production time that passed before the AI paid for it.
	if ai_enabled and not finished:
		ai_clock -= delta
		if ai_clock <= 0.000001:
			ai_clock = AI_STRATEGY.TURN_INTERVAL
			_ai_turn()

func _tick_recruitment(delta: float) -> Dictionary[int, bool]:
	var recruiting: Dictionary[int, bool] = {}
	for faction: int in faction_count:
		var state := faction_skills[faction]
		if state.recruit_target_id < 0:
			continue
		var target: WarBuilding = by_id[state.recruit_target_id]
		if not FACTIONS.allied(target.faction, faction) or target.kind != 0:
			_cancel_recruitment(faction)
			continue
		if target.disruption_remaining > 0.0:
			recruiting[target.building_id] = true
			if delta >= state.durations[0]:
				state.recruit_target_id = -1
			continue
		# One recruitment per residence. Only natural production observes the cap.
		var active_time := minf(delta, state.durations[0])
		var rate := target.production_rate
		var ordinary_time := minf(active_time, maxf(0.0, target.capacity - target.population) / (RECRUIT_RATE + rate))
		target.population += RECRUIT_RATE * active_time + rate * ordinary_time
		if target.population < target.capacity:
			target.population = minf(target.capacity, target.population + rate * (delta - active_time))
		recruiting[target.building_id] = true
		if delta >= state.durations[0]:
			state.recruit_target_id = -1
	return recruiting

func _cancel_recruitment(faction: int = -2) -> void:
	faction = local_faction if faction == -2 else faction
	faction_skills[faction].recruit_target_id = -1
	faction_skills[faction].durations[0] = 0.0

func _cancel_building_recruitment(building_id: int) -> void:
	for faction: int in faction_count:
		if faction_skills[faction].recruit_target_id == building_id:
			_cancel_recruitment(faction)

func set_percentage(value: int) -> void:
	if value in [25, 50, 75, 100] and value != percentage and not _local_menu and not finished:
		percentage = value
		if drag_source == null:
			audio.play_ui(&"war_ratio")
		update_hud()
		overlay.queue_redraw()

func select_building(building: Node3D) -> void:
	if selected != null:
		selected.set_selected(false)
	selected = building
	if selected != null:
		selected.set_selected(true)
	hud.track_building(selected, camera, buildings)
	update_hud()

func dispatch_count(source: WarBuilding, amount_percent: int) -> int:
	var count := floori(source.available_population * amount_percent / 100.0)
	if source.burrow_remaining > 0.0: count = mini(count, SKILL_RULES.BURROW_LIMIT)
	return mini(count, pig.limit_for(source.building_id))

func dispatch_route(source: WarBuilding, target: WarBuilding) -> PackedVector3Array:
	if pig.flags_for(source.building_id).y > 0.0:
		return flight_route(source, target)
	return map.get_building_route(source, target)

func flight_route(source: WarBuilding, target: WarBuilding) -> PackedVector3Array:
	var entrance: Vector3 = map.definition.surface_point(source.march_perimeter_towards(target.global_position))
	var exit: Vector3 = map.definition.surface_point(target.march_perimeter_towards(source.global_position))
	return marches.make_flight_route(entrance, exit, map.flight_obstacle_top)

func issue_order(source: Node3D, target: Node3D, amount_percent: int, faction: int = -2) -> int:
	faction = local_faction if faction == -2 else faction
	if not is_authority() or has_surrendered(faction) or finished or is_rule_paused() or source == null or target == null or source == target:
		return 0
	if source.faction != faction or amount_percent not in [25, 50, 75, 100]:
		return 0
	var count := dispatch_count(source, amount_percent)
	if count < 1:
		if faction == local_faction:
			hud.notify("当前比例不足 1 名可用民兵 · 待出发部队已预留")
			audio.play_ui(&"war_denied")
		return 0
	var route := dispatch_route(source, target)
	if route.size() < 2:
		if faction == local_faction:
			hud.notify("没有可通行的路线")
			audio.play_ui(&"war_denied")
		return 0
	if source.burrow_remaining > 0.0:
		var plan := RABBIT_SKILLS.burrow_plan(self, source, target, amount_percent)
		if plan.is_empty():
			return 0
		_clear_building_burrow(source)
		marches.queue_tunnel_departure(source.building_id, target.building_id, faction, count, route, SKILL_RULES.BURROW_BATCH_INTERVAL, plan.dig_duration, source.kind == 3)
		world_effects.get_node("Rabbit").start_tunnel(faction, plan.entrance, plan.exit, plan.route[1] - plan.route[0], count, plan.dig_duration)
		presentation_event.emit("tunnel", {"faction": faction, "entrance": _vector_values(plan.entrance), "exit": _vector_values(plan.exit), "direction": _vector_values(plan.route[1] - plan.route[0]), "count": count, "dig_duration": plan.dig_duration})
	else:
		var pig_flags: Vector3 = pig.flags_for(source.building_id)
		marches.queue_departure(source.building_id, target.building_id, faction, count, route, source.kind == 3, pig_flags.x > 0.0, pig_flags.y > 0.0, pig_flags.z > 0.0)
	pig.clear_building(self, source.building_id)
	presentation_event.emit("dispatch", {"faction": faction, "source": source.building_id, "target": target.building_id, "count": count})
	if faction == local_faction:
		audio.play_ui(&"war_order")
		var verb := "增援" if FACTIONS.allied(target.faction, local_faction) else "进攻"
		var transfer := " · 抵达后归队友指挥" if target.faction != local_faction and FACTIONS.allied(target.faction, local_faction) else ""
		hud.notify("%d 名民兵依次出发 · %s%s%s" % [count, verb, KIND_NAMES[target.kind], transfer])
		add_effect(target.global_position, Color(1.0, 0.77, 0.3), "order", 0.65)
	update_hud()
	return count

func forge_count(faction: int) -> int:
	if faction < 0:
		return 0
	var count: int = 0
	for building: Node3D in buildings:
		if building.faction == faction and building.kind == 2 and building.disruption_remaining <= 0.0:
			count += 1
	return count

func energy_tower_count(faction: int) -> int:
	if faction < 0:
		return 0
	var count := 0
	for building: WarBuilding in buildings:
		if building.faction == faction and building.kind == 3 and building.disruption_remaining <= 0.0:
			count += 1
	return count

func energy_regen_for(faction: int) -> float:
	return SKILL_RULES.natural_energy_regen(elapsed) + SKILL_RULES.energy_tower_bonus(energy_tower_count(faction))

func attack_bonus(faction: int) -> float:
	return COMBAT_RULES.forge_attack_bonus(forge_count(faction))

func defense_bonus(building: Node3D) -> float:
	var tower: float = COMBAT_RULES.tower_defense_bonus(building.level) if building.kind == 1 else 0.0
	return tower + COMBAT_RULES.forge_defense_bonus(forge_count(building.faction))

func skill_defense_bonus(building: Node3D) -> float:
	var bonus: float = SKILL_RULES.SHIELD_DEFENSE if shields.has(building.building_id) else 0.0
	if bear.wards.has(building.building_id) and bear.wards[building.building_id].remaining > 0.0:
		bonus += SKILL_RULES.BEAR_WARD_DEFENSE
	return bonus

func combat_multiplier(faction: int, target: Node3D, unit_attack_bonus: float = 0.0) -> float:
	# Buildings and morale share one additive group; skills form a separate group.
	var environment := (morale.attack(faction) + attack_bonus(faction)) / (morale.defense(target.faction) + defense_bonus(target))
	return environment * (1.0 + unit_attack_bonus) / (1.0 + skill_defense_bonus(target))

func sync_environment_bonuses() -> void:
	for faction: int in faction_count:
		marches.environment_speed[faction] = morale.speed(faction)

func _on_morale_changed(faction: int) -> void:
	marches.environment_speed[faction] = morale.speed(faction)

func _on_building_completed(kind: int, completed_level: int, converted: bool, building: WarBuilding) -> void:
	sync_environment_bonuses()
	if not converted and building.faction >= 0:
		morale.adjust(building.faction, MORALE.upgrade_reward(kind, completed_level))
	presentation_event.emit("construction_complete", {"building": building.building_id, "faction": building.faction, "kind": kind, "level": completed_level, "converted": converted})

static func _vector_values(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _on_unit_defeated(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool) -> void:
	world_effects.casualty(at, heading, faction, impulse, burning)
	presentation_event.emit("casualty", {"at": _vector_values(at), "heading": _vector_values(heading), "faction": faction, "impulse": _vector_values(impulse), "burning": burning})

func _restore_combat_energy(faction: int, losses: float) -> void:
	# Population and morale remain fractional; a neutral garrison has no account.
	if faction < 0 or losses <= 0.0:
		return
	var state := faction_skills[faction]
	state.energy = minf(ENERGY_MAX, state.energy + losses * SKILL_RULES.combat_energy_per_loss(morale.stars(faction)))

func _record_attacker_losses(faction: int, defender: int, losses: float) -> void:
	if losses <= 0.0:
		return
	# Sample the loss owner's current tier before this exchange changes morale.
	_restore_combat_energy(faction, losses)
	morale.adjust(faction, -MORALE.ATTACKER_LOSS_PENALTY * losses)
	if FACTIONS.hostile(faction, defender):
		morale.adjust(defender, MORALE.KILL_REWARD * losses)

func _on_march_combat_death(faction: int, target_id: int, killer_faction: int) -> void:
	var destination: WarBuilding = by_id[target_id]
	# Reinforcements are not attacking; neither friendly fire nor an unrelated
	# intercepted transfer earns a defensive-kill reward.
	if not FACTIONS.allied(faction, destination.faction):
		morale.adjust(faction, -MORALE.ATTACKER_LOSS_PENALTY)
		if FACTIONS.hostile(faction, killer_faction) and FACTIONS.allied(killer_faction, destination.faction):
			morale.adjust(killer_faction, MORALE.KILL_REWARD)

func _on_departure_queue_changed(source_id: int, faction: int, change: int) -> void:
	var source: WarBuilding = by_id[source_id]
	assert(source.faction == faction)
	source.queued_population += change
	assert(source.queued_population >= 0)

func _on_unit_departed(source_id: int, faction: int) -> void:
	var source: WarBuilding = by_id[source_id]
	assert(source.faction == faction and source.population >= 1.0)
	source.population -= 1.0
	source.refresh_visual()

func _on_unit_arrived(target_id: int, faction: int, strength: float, unit_attack_bonus: float = 0.0, energy_origin: bool = false) -> void:
	var target: Node3D = by_id[target_id]
	if FACTIONS.allied(target.faction, faction):
		# Entering a teammate's building transfers command with the garrison.
		# Ownership stays with the recipient; later orders use that building's faction.
		target.population += strength
		audio.play_world(&"war_reinforce", target.global_position)
	else:
		var defending_population: float = target.population
		var original_damage: float = strength * combat_multiplier(faction, target, unit_attack_bonus)
		var damage: float = bear.apply_damage(self, target, original_damage, true)
		if defending_population + 0.00001 >= damage:
			_record_attacker_losses(faction, target.faction, strength)
		else:
			var survivors: float = clampf(strength * (damage - defending_population) / maxf(original_damage, 0.000001), 0.0, strength)
			var previous_faction: int = target.faction
			var captured_level: int = target.level
			_record_attacker_losses(faction, previous_faction, strength - survivors)
			morale.adjust(faction, MORALE.capture_reward(target.kind, captured_level, previous_faction < 0))
			if previous_faction >= 0:
				morale.adjust(previous_faction, -MORALE.loss_penalty(target.kind, captured_level))
			if target.queued_population > 0:
				marches.trim_departures(target_id, previous_faction, 0)
			target.cancel_construction()
			bear.clear_building(self, target_id)
			target.clear_disruption()
			_clear_building_burrow(target)
			pig.clear_building(self, target_id)
			target.faction = faction
			_cancel_building_recruitment(target_id)
			target.population = survivors
			target.level = maxi(1, target.level - 1)
			shields.erase(target_id)
			sync_environment_bonuses()
			var energy_bonus := 0.0
			if energy_origin and FACTIONS.hostile(faction, previous_faction):
				var state := faction_skills[faction]
				energy_bonus = minf(SKILL_RULES.ENERGY_CAPTURE_REWARD, ENERGY_MAX - state.energy)
				state.energy += energy_bonus
			target.pulse_capture()
			presentation_event.emit("capture", {"building": target_id, "faction": faction, "previous_faction": previous_faction, "energy_bonus": energy_bonus})
			add_effect(target.global_position, faction_color(faction), "capture", 1.1)
			if faction == local_faction:
				audio.play_ui(&"war_capture")
			elif previous_faction == local_faction:
				audio.play_ui(&"war_lost")
			if faction == local_faction:
				var benefit: String = ["每秒 +%s 民兵" % target.production_rate, "炮塔开始拦截敌军", "提高全军攻击与防御", "提高技力恢复速度"][target.kind]
				if energy_bonus > 0.0:
					benefit += " · 技力 +%.1f" % energy_bonus
				hud.notify("已占领%s · %s" % [KIND_NAMES[target.kind], benefit])
			tower_clocks[target_id] = 0.6
		if effects.size() < 80:
			add_effect(target.global_position, faction_color(faction), "hit", 0.2)
		audio.play_world(&"war_melee", target.global_position)
	target.refresh_visual()

func _fire_tower(building: Node3D) -> void:
	if building.disruption_remaining > 0.0:
		return
	var targets: Array[WarMarches.MarchUnit] = marches.acquire_targets(building.global_position, building.faction, tower_range(building), building.level, false, true)
	if targets.is_empty():
		return
	tower_clocks[building.building_id] = tower_interval(building)
	building.fire_at(targets[0].position)
	var muzzle: Vector3 = building.muzzle_position()
	world_effects.hit(muzzle, (targets[0].position - muzzle).normalized(), true)
	for target: WarMarches.MarchUnit in targets:
		var destination := target.position + Vector3(0, 0.65, 0)
		presentation_event.emit("tower_shot", {"building": building.building_id, "faction": building.faction, "unit": target.unit_id, "at": _vector_values(muzzle), "to": _vector_values(destination), "duration": clampf(muzzle.distance_to(destination) / 32.0, 0.07, 0.48)})
		projectiles.append({"target": target, "at": muzzle, "position": muzzle, "previous": muzzle,
			"to": destination, "tracking": true, "age": 0.0, "duration": clampf(muzzle.distance_to(destination) / 32.0, 0.07, 0.48)})
	world_effects.render_projectiles(projectiles)
	audio.play_world(&"cannon_shot", building.global_position)

func _tick_projectiles(delta: float) -> void:
	for index: int in range(projectiles.size() - 1, -1, -1):
		var shot: Dictionary = projectiles[index]
		var target: WarMarches.MarchUnit = shot.target
		shot.age += delta
		shot.previous = shot.position
		shot.tracking = shot.tracking and marches.tower_can_target(target)
		if shot.tracking:
			shot.to = target.position + Vector3(0, 0.65, 0)
		var progress := minf(1.0, shot.age / shot.duration)
		shot.position = shot.at.lerp(shot.to, progress) + Vector3(0, sin(progress * PI) * 0.65, 0)
		if progress >= 1.0:
			var direction: Vector3 = (shot.to - shot.at).normalized()
			if not shot.tracking or not marches.hit_target(target, direction, true):
				target.reserved = false
				target.intercepted_by = -1
				world_effects.hit(shot.to, direction)
			audio.play_world(&"war_projectile_hit", shot.to)
			projectiles.remove_at(index)
	world_effects.render_projectiles(projectiles)

func start_fire(at: Vector3, radius: float, faction: int) -> RefCounted:
	var fire := FIRE_STATE.new()
	fire.effect_id = _next_fire_id
	_next_fire_id += 1
	fire.global_position = at
	fire.radius = radius
	fire.faction = faction
	fire_states.append(fire)
	world_effects.sync_fire_states(fire_states)
	return fire

func _advance_fire_states(delta: float) -> void:
	for index: int in range(fire_states.size() - 1, -1, -1):
		fire_states[index].age += delta
		if fire_states[index].age >= FIRE_STATE.LIFETIME:
			fire_states.remove_at(index)

func _tick_fire_buildings() -> void:
	for fire: RefCounted in fire_states:
		if fire.age >= FIRE_STATE.BURN_TIME:
			continue
		for building: WarBuilding in buildings:
			if FACTIONS.allied(building.faction, fire.faction) or fire.hit_buildings.has(building.building_id):
				continue
			var offset := Vector2(building.global_position.x - fire.global_position.x, building.global_position.z - fire.global_position.z)
			if offset.length() <= fire.front(fire.age):
				fire.hit_buildings[building.building_id] = true
				# Fire retains its independent base damage and morale attack scaling.
				bear.apply_damage(self, building, IMPACT_DAMAGE * morale.attack(fire.faction) / (morale.defense(building.faction) + defense_bonus(building)) / (1.0 + skill_defense_bonus(building)))
				building.refresh_visual()

func tower_range(building: Node3D) -> float:
	return building.attack_range

func tower_interval(building: Node3D) -> float:
	return maxf(0.55, 1.5 - 0.3 * (building.level - 1))

func request_skill(index: int, from_keyboard: bool = false) -> void:
	if _local_menu or not _skill_available(index):
		return
	audio.play_ui(&"war_drag")
	_cancel_skill_drag()
	_cancel_drag()
	armed_skill = index
	_skill_keycode = [KEY_Q, KEY_W, KEY_E, KEY_R][index] if from_keyboard else 0
	_update_skill_drag(get_viewport().get_mouse_position())
	update_hud()
	overlay.queue_redraw()

func _update_skill_drag(screen: Vector2, refresh_preview: bool = false) -> void:
	ground_skill_target = skill_ground_at(screen)
	var over_battlefield: bool = get_viewport().get_visible_rect().has_point(screen) and not hud.is_pointer_blocked(screen)
	hovered = pick_building(screen) if over_battlefield and not skill_is_ground(armed_skill) else null
	var valid := ground_skill_target.is_finite() if skill_is_ground(armed_skill) else _valid_skill_target(armed_skill, hovered)
	if faction_skills[local_faction].commander == SKILL_RULES.FROG and skill_is_ground(armed_skill):
		frog_preview.clear()
		if ground_skill_target.is_finite():
			frog_preview = marches.frog_targets(armed_skill, local_faction, ground_skill_target)
		if armed_skill in [1, 2]:
			valid = not frog_preview.is_empty()
	if faction_skills[local_faction].commander == SKILL_RULES.RABBIT:
		if armed_skill == 0:
			rush_preview = marches.rush_targets(local_faction, ground_skill_target, SKILL_RULES.RABBIT_RUSH_RADIUS)
			valid = not rush_preview.is_empty()
		elif armed_skill == 2:
			_refresh_rabbit_preview(refresh_preview)
			valid = not recall_preview.is_empty()
	if faction_skills[local_faction].commander == SKILL_RULES.FOX and armed_skill == 2:
		fox_preview = FOX_SKILLS.conversion_targets(self, ground_skill_target, local_faction)
		valid = not fox_preview.is_empty()
	hud.set_skill_drag_target(valid, screen)
	overlay.queue_redraw()

func release_skill_drag(screen: Vector2) -> void:
	var index := armed_skill
	_update_skill_drag(screen, true)
	var target := hovered
	var success := false
	if skill_is_ground(index) and ground_skill_target.is_finite():
		success = submit_player_command({"type": "skill_ground", "skill": index, "x": ground_skill_target.x, "z": ground_skill_target.z}).accepted
	elif not skill_is_ground(index) and _valid_skill_target(index, target):
		success = submit_player_command({"type": "skill_building", "skill": index, "target": target.building_id}).accepted
	_cancel_skill_drag()
	if success and target != null:
		select_building(target)
	elif not success:
		audio.play_ui(&"war_cancel")
	update_hud()
	overlay.queue_redraw()

func _cancel_skill_drag() -> void:
	armed_skill = -1
	_skill_keycode = 0
	ground_skill_target = Vector3.INF
	hovered = null
	recall_preview = []
	rush_preview = []
	frog_preview = []
	fox_preview = []
	_recall_preview_center = Vector3.INF
	_rabbit_preview_time = -1.0

func skill_is_ground(index: int, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	return index >= 0 and index < 4 and faction >= 0 and faction < faction_count and SKILL_RULES.is_ground(index, faction_skills[faction].commander)

func skill_radius(index: int, faction: int = -2) -> float:
	faction = local_faction if faction == -2 else faction
	if faction_skills[faction].commander == SKILL_RULES.PIG:
		return SKILL_RULES.PIG_DROP_RADIUS
	if faction_skills[faction].commander == SKILL_RULES.FOX:
		return SKILL_RULES.FOX_CONVERT_RADIUS
	if faction_skills[faction].commander == SKILL_RULES.FROG:
		return SKILL_RULES.FROG_RADII[index]
	if faction_skills[faction].commander == SKILL_RULES.BEAR:
		return SKILL_RULES.BEAR_SLOW_RADIUS
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		return SKILL_RULES.RABBIT_RUSH_RADIUS if index == 0 else SKILL_RULES.RECALL_RADIUS
	return SKILL_RULES.HASTE_RADIUS if index == 1 else IMPACT_RADIUS

func _refresh_rabbit_preview(force: bool = false) -> void:
	var changed := ground_skill_target != _recall_preview_center
	if not force and not changed and elapsed - _rabbit_preview_time < 0.1:
		return
	_rabbit_preview_time = elapsed
	_recall_preview_center = ground_skill_target
	recall_preview = RABBIT_SKILLS.recall_plan(self, ground_skill_target)

func _clear_building_burrow(building: WarBuilding) -> void:
	if building.burrow_remaining > 0.0 and building.faction >= 0:
		faction_skills[building.faction].durations[3] = 0.0
	building.clear_burrow()

func public_skill_statuses_for(faction: int) -> Array[int]:
	var state := faction_skills[faction]
	if not is_authority() and faction != local_faction:
		return state.public_statuses.duplicate()
	var statuses: Array[int] = []
	var costs := SKILL_RULES.costs_for(state.commander)
	for index: int in 4:
		statuses.append(0 if state.cooldowns[index] > 0.0 else (2 if state.energy >= costs[index] else 1))
	return statuses

func can_cast_skill(index: int, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	return index >= 0 and index < 4 and faction >= 0 and faction < faction_count and not has_surrendered(faction) and not is_rule_paused() and not finished and faction_skills[faction].cooldowns[index] <= 0.0 and faction_skills[faction].energy >= SKILL_RULES.costs_for(faction_skills[faction].commander)[index]

func _skill_available(index: int, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	if faction != local_faction:
		return can_cast_skill(index, faction)
	if index < 0 or index >= 4 or is_rule_paused() or finished or has_surrendered(faction):
		return false
	if cooldowns[index] > 0.0:
		hud.notify("技能冷却中 · 还需 %d 秒" % ceili(cooldowns[index]))
		audio.play_ui(&"war_denied")
		return false
	var cost := SKILL_RULES.costs_for(faction_skills[faction].commander)[index]
	if energy < cost:
		hud.notify("技力不足 · 需要 %d，还差 %d" % [int(cost), ceili(cost - energy)])
		audio.play_ui(&"war_denied")
		return false
	return true

func _valid_skill_target(index: int, target: Node3D, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	if target == null:
		return false
	if faction_skills[faction].commander == SKILL_RULES.PIG:
		return pig.valid_target(index, target, faction)
	if faction_skills[faction].commander == SKILL_RULES.FOX:
		return FOX_SKILLS.valid_target(self, index, target, faction)
	if faction_skills[faction].commander == SKILL_RULES.FROG:
		return FROG_SKILLS.valid_target(self, index, target, faction)
	if faction_skills[faction].commander == SKILL_RULES.BEAR:
		return bear.valid_target(self, index, target, faction)
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		match index:
			1: return FACTIONS.hostile(target.faction, faction) and target.disruption_remaining <= 0.0
			3: return target.faction == faction and target.burrow_remaining <= 0.0
		return false
	if index == 0:
		if not FACTIONS.allied(target.faction, faction) or target.kind != 0:
			return false
		for state: SkillState in faction_skills:
			if state.recruit_target_id == target.building_id:
				return false
		return true
	if index == 2:
		return FACTIONS.allied(target.faction, faction) and not shields.has(target.building_id)
	return false

func cast_skill(index: int, target: Node3D, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	if not is_authority() or not _skill_available(index, faction):
		return false
	if not _valid_skill_target(index, target, faction):
		if faction == local_faction:
			if faction_skills[faction].commander == SKILL_RULES.PIG:
				hud.notify("选择尚未获得此待命效果的自己的建筑" if index < 3 else "拖至战场地面后松手")
			elif faction_skills[faction].commander == SKILL_RULES.FOX:
				hud.notify(["选择有驻军的敌方或中立建筑", "选择仍有士气的敌方建筑；自己的士气须未满", "拖至有敌军的地面区域后松手", "选择有同阵营避难建筑的敌方建筑"][index])
			elif faction_skills[faction].commander == SKILL_RULES.FROG:
				hud.notify("选择有驻军、可降级或正在施工的敌方或中立建筑" if index == 3 else "拖至战场地面后松手")
			elif faction_skills[faction].commander == SKILL_RULES.BEAR:
				hud.notify(["选择正在升级或转换的己方建筑", "拖至战场地面后松手", "选择附近 18 米内有己方支援建筑的据点", "选择尚未获得震庭威慑的己方建筑"][index])
			elif faction_skills[faction].commander == SKILL_RULES.RABBIT:
				hud.notify(["拖至战场地面后松手", "选择尚未停工的敌方建筑", "选择有行军部队的地面区域", "选择尚未获得兔洞待命的自己的建筑"][index])
			else:
				hud.notify("选择尚未受此军令影响的己方或盟友住宅" if index == 0 else ("选择尚未受防护罩保护的己方或盟友建筑" if index == 2 else "拖至战场地面后松手"))
			audio.play_ui(&"war_denied")
		return false
	if faction_skills[faction].commander == SKILL_RULES.PIG:
		_commit_skill(index, faction)
		pig.arm(self, index, target, faction)
		_present_skill(index, faction, target.global_position, target.building_id)
		audio.play_world(pig.CAST_SOUNDS[index], target.global_position)
		if faction == local_faction:
			hud.notify("%s · 待命 15 秒，下次出兵生效" % SKILL_RULES.PIG_NAMES[index])
		update_hud()
		return true
	if faction_skills[faction].commander in [SKILL_RULES.BEAR, SKILL_RULES.FROG, SKILL_RULES.FOX]:
		if faction_skills[faction].commander == SKILL_RULES.FOX:
			FOX_SKILLS.cast(self, index, target, faction)
		elif faction_skills[faction].commander == SKILL_RULES.FROG:
			FROG_SKILLS.strike(self, target, faction)
		else:
			bear.cast(self, index, target, faction)
		_commit_skill(index, faction)
		_present_skill(index, faction, target.global_position, target.building_id)
		target.refresh_visual()
		update_hud()
		return true
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		if not RABBIT_SKILLS.cast(self, index, target, faction):
			return false
		_commit_skill(index, faction)
		_present_skill(index, faction, target.global_position, target.building_id)
		audio.play_world(&"war_rabbit_seal" if index == 1 else &"war_rabbit_burrow", target.global_position)
		if faction == local_faction:
			hud.notify("封条急件 · 停工 6 秒" if index == 1 else "兔洞待命 15 秒 · 下次派兵最多 50 人，距离不限")
		target.refresh_visual()
		update_hud()
		return true
	match index:
		0:
			faction_skills[faction].recruit_target_id = target.building_id
			add_effect(target.global_position, Color(1.0, 0.8, 0.25), "skill", 1.1)
		2:
			shields[target.building_id] = SKILL_DURATIONS[2]
	_commit_skill(index, faction)
	_present_skill(index, faction, target.global_position, target.building_id)
	var skill_sounds: Array[StringName] = [&"war_skill_command", &"war_skill_drum", &"war_skill_shield"]
	audio.play_world(skill_sounds[index], target.global_position)
	if faction == local_faction:
		hud.notify("%s · %s" % [SKILL_RULES.NAMES[index], SKILL_RULES.effect_text(index)])
	if target != null:
		target.refresh_visual()
	world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
	update_hud()
	return true

func cast_ground_skill(index: int, at: Vector3, faction: int = -2) -> bool:
	faction = local_faction if faction == -2 else faction
	if not is_authority() or not skill_is_ground(index, faction) or not _skill_available(index, faction):
		return false
	if not _valid_ground_skill_target(at):
		if faction == local_faction:
			hud.notify("请选择战场内的地面 · 右键取消")
			audio.play_ui(&"war_denied")
		return false
	var center: Vector3 = map.definition.surface_point(at)
	if faction_skills[faction].commander == SKILL_RULES.PIG:
		pig.start_drop(self, center, faction)
		_commit_skill(index, faction)
		_present_skill(index, faction, center)
		audio.play_world(pig.CAST_SOUNDS[index], center)
		update_hud()
		return true
	if faction_skills[faction].commander == SKILL_RULES.FOX:
		if FOX_SKILLS.convert(self, center, faction) == 0:
			if faction == local_faction:
				hud.notify("范围内没有可招降的敌方行军部队")
			return false
		world_effects.get_node("Fox").release(index, faction, center)
		_commit_skill(index, faction)
		_present_skill(index, faction, center)
		audio.play_world(&"war_fox_convert", center)
		update_hud()
		return true
	if faction_skills[faction].commander == SKILL_RULES.FROG:
		if marches.apply_frog_field(index, faction, center) == 0:
			if faction == local_faction:
				hud.notify("范围内没有可滞空的士兵" if index == 1 else "范围内没有可隐身的己方士兵")
			return false
		world_effects.get_node("Frog").release(index, faction, center)
		world_effects.get_node("Frog").sync(marches, 0.0)
		_commit_skill(index, faction)
		_present_skill(index, faction, center)
		var frog_sounds: Array[StringName] = [&"war_frog_mist", &"war_frog_float", &"war_frog_cloak"]
		audio.play_world(frog_sounds[index], center)
		update_hud()
		return true
	if faction_skills[faction].commander == SKILL_RULES.BEAR:
		marches.create_slow_zone(faction, center, SKILL_RULES.BEAR_SLOW_RADIUS, SKILL_RULES.BEAR_DURATIONS[1])
		world_effects.get_node("Bear").stomp(faction, center)
		world_effects.get_node("Bear").sync(bear, marches, by_id, 0.0)
		_commit_skill(index, faction)
		_present_skill(index, faction, center)
		audio.play_world(&"war_bear_stomp", center)
		update_hud()
		return true
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		if index == 0:
			var rushing: int = marches.apply_rush(faction, center, SKILL_RULES.RABBIT_RUSH_RADIUS, SKILL_RULES.RABBIT_DURATIONS[0])
			if rushing == 0:
				if faction == local_faction:
					hud.notify("小圈内没有自己的行军部队 · 请选择已出发的士兵")
				return false
			world_effects.get_node("Rabbit").start_rush(faction, center, SKILL_RULES.RABBIT_RUSH_RADIUS)
			if faction == local_faction:
				hud.notify("迅猛冲刺 · %d 人移速 +%d%%、攻击 +%d%%，持续 %d 秒" % [rushing, roundi((SKILL_RULES.RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), roundi(SKILL_RULES.RABBIT_RUSH_ATTACK_BONUS * 100.0), SKILL_RULES.RABBIT_DURATIONS[0]])
		else:
			var recalled := RABBIT_SKILLS.recall(self, center, faction)
			if recalled == 0:
				if faction == local_faction:
					hud.notify("范围内没有需要折返的行军部队")
				return false
			if faction == local_faction:
				hud.notify("归巢口哨 · %d 名双方部队返回各自出发建筑" % recalled)
		_commit_skill(index, faction)
		_present_skill(index, faction, center)
		audio.play_world(&"war_rabbit_dash" if index == 0 else &"war_rabbit_recall", center)
		world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
		update_hud()
		return true
	if index == 1:
		marches.create_haste_zone(faction, center, SKILL_RULES.HASTE_RADIUS, SKILL_DURATIONS[1], SKILL_RULES.HASTE_MULTIPLIER)
	else:
		var fire: RefCounted = start_fire(center, IMPACT_RADIUS, faction)
		marches.ignite_at(center, fire.front(0.0), faction)
		_tick_fire_buildings()
	_commit_skill(index, faction)
	_present_skill(index, faction, center)
	audio.play_world(&"war_skill_drum" if index == 1 else &"war_skill_breach", center)
	if faction == local_faction:
		hud.notify("疾行区域已展开 · 圈内自己的部队提速，离开恢复" if index == 1 else "火焰已点燃 · 接触火焰的双方士兵都会死亡")
	world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
	update_hud()
	return true

func _commit_skill(index: int, faction: int = -2) -> void:
	faction = local_faction if faction == -2 else faction
	var state := faction_skills[faction]
	state.energy -= SKILL_RULES.costs_for(state.commander)[index]
	state.cooldowns[index] = SKILL_RULES.cooldowns_for(state.commander)[index]
	state.durations[index] = SKILL_RULES.durations_for(state.commander)[index]
	if faction == local_faction:
		_cancel_skill_drag()
		_cancel_drag()

func _present_skill(index: int, faction: int, at: Vector3, target_id: int = -1) -> void:
	presentation_event.emit("skill", {"faction": faction, "skill": index, "commander": str(faction_skills[faction].commander), "at": _vector_values(at), "target": target_id})

func _valid_ground_skill_target(at: Vector3) -> bool:
	return at.is_finite() and absf(at.x) <= map.definition.half_size.x and absf(at.z) <= map.definition.half_size.y

func skill_ground_at(screen: Vector2) -> Vector3:
	if not get_viewport().get_visible_rect().has_point(screen) or hud.is_pointer_blocked(screen):
		return Vector3.INF
	var hit: Vector3 = map.definition.ray_ground(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if not _valid_ground_skill_target(hit):
		return Vector3.INF
	return hit

func upgrade_selected() -> void:
	if selected == null:
		return
	submit_player_command({"type": "upgrade", "building": selected.building_id})

func convert_selected(kind: int) -> void:
	if selected == null:
		return
	submit_player_command({"type": "convert", "building": selected.building_id, "kind": kind})

func begin_building_construction(building: WarBuilding, kind: int, faction: int) -> bool:
	if not is_authority() or has_surrendered(faction) or finished or is_rule_paused() or building == null or building.faction != faction or building.is_constructing:
		return false
	if kind == -1:
		if building.level >= building.max_level:
			return false
	elif not building.can_convert_to(kind):
		return false
	var cost: int = building.upgrade_cost if kind == -1 else CONVERSION_COST
	if building.available_population < cost:
		if faction == local_faction:
			hud.notify("%s需要 %d 名未编入出发队列的驻军" % ["升级" if kind == -1 else "改建", cost])
			audio.play_ui(&"war_denied")
		return false
	building.population -= cost
	building.begin_construction(kind, cost)
	building.refresh_visual()
	audio.play_world(&"war_rebuild", building.global_position)
	presentation_event.emit("construction", {"building": building.building_id, "faction": faction, "kind": kind})
	if faction == local_faction:
		hud.notify("%s开始升级 · 10 秒后完成" % KIND_NAMES[building.kind] if kind == -1 else "开始改建%s · 10 秒后完成" % KIND_NAMES[kind])
	update_hud()
	return true

func submit_player_command(command: Dictionary) -> Dictionary:
	var control: bool = command.get("type") in ["pause", "surrender"]
	if (_local_menu and not control) or finished or _closing or has_surrendered(local_faction):
		return {"accepted": false, "reason": "input_blocked"}
	if network_match != null:
		return network_match.submit(command)
	return execute_network_command(local_faction, command)

static func _integer_fields(command: Dictionary, fields: Array) -> bool:
	# JSON transports represent integral numbers as doubles. Accept only finite,
	# exact 32-bit integers so booleans, strings, fractions and overflow cannot
	# silently turn into somebody else's building/skill identifier.
	for field: String in fields:
		var value: Variant = command.get(field)
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			return false
		if not is_finite(float(value)) or absf(float(value)) > 2147483647.0 or float(value) != floorf(float(value)):
			return false
	return true

func execute_network_command(faction: int, command: Dictionary) -> Dictionary:
	if not is_authority():
		return {"accepted": false, "reason": "not_authority"}
	if finished or _closing:
		return {"accepted": false, "reason": "match_not_running"}
	if faction < 0 or faction >= faction_count:
		return {"accepted": false, "reason": "invalid_faction"}
	if command.get("type") == "pause":
		if not command.get("paused") is bool: return {"accepted": false, "reason": "invalid_command"}
		return set_match_paused(command.paused, faction)
	if command.get("type") == "surrender": return surrender_faction(faction)
	if is_rule_paused() or has_surrendered(faction):
		return {"accepted": false, "reason": "match_not_running"}
	var accepted := false
	var count := 0
	match command.get("type", ""):
		"dispatch":
			if not _integer_fields(command, ["source", "target", "percent"]):
				return {"accepted": false, "reason": "invalid_command"}
			count = issue_order(by_id.get(int(command.source)), by_id.get(int(command.target)), int(command.percent), faction)
			accepted = count > 0
		"upgrade", "convert":
			var converting: bool = command.type == "convert"
			if not _integer_fields(command, ["building", "kind"] if converting else ["building"]):
				return {"accepted": false, "reason": "invalid_command"}
			if converting and int(command.kind) not in [0, 1, 2, 3]:
				return {"accepted": false, "reason": "invalid_command"}
			accepted = begin_building_construction(by_id.get(int(command.building)), int(command.kind) if converting else -1, faction)
		"skill_building":
			if not _integer_fields(command, ["skill", "target"]):
				return {"accepted": false, "reason": "invalid_command"}
			accepted = cast_skill(int(command.skill), by_id.get(int(command.target)), faction)
		"skill_ground":
			if not _integer_fields(command, ["skill"]) or typeof(command.get("x")) not in [TYPE_INT, TYPE_FLOAT] or typeof(command.get("z")) not in [TYPE_INT, TYPE_FLOAT]:
				return {"accepted": false, "reason": "invalid_command"}
			accepted = cast_ground_skill(int(command.skill), map.definition.surface_point(Vector3(float(command.x), 0.0, float(command.z))), faction)
		_:
			return {"accepted": false, "reason": "invalid_command"}
	return {"accepted": accepted, "reason": "" if accepted else "rule_rejected", "count": count}

func _ai_turn() -> void:
	if not is_authority() or is_rule_paused():
		return
	if match_config.is_empty():
		_ai_strategy.take_turn(self)
		for strategy: RefCounted in _other_ai:
			strategy.take_turn(self)
		return
	for faction: int in _bot_factions:
		if not has_surrendered(faction): _ai_by_faction[faction].take_turn(self)

func team_total_for(faction: int) -> int:
	var count: float = marches.team_total_for(faction)
	for building: WarBuilding in buildings:
		if FACTIONS.allied(building.faction, faction):
			count += building.available_population
	return floori(count)

func incoming_damage_for(building: WarBuilding, incoming: Dictionary[Vector2i, int]) -> float:
	var damage := 0.0
	for faction: int in faction_count:
		if FACTIONS.hostile(building.faction, faction):
			damage += incoming.get(Vector2i(building.building_id, faction), 0) * combat_multiplier(faction, building)
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.target_id == building.building_id and FACTIONS.hostile(building.faction, unit.order.faction):
			damage += unit.order.strength * (combat_multiplier(unit.order.faction, building, marches.projected_attack_bonus(unit)) - combat_multiplier(unit.order.faction, building))
	return damage

func total_for(faction: int) -> int:
	var count: float = marches.total_for(faction)
	for building: Node3D in buildings:
		if building.faction == faction:
			count += building.available_population
	return floori(count)

func _toolbox_can_restore_population(building: WarBuilding) -> bool:
	if not building.is_constructing or has_surrendered(building.faction): return false
	var state := faction_skills[building.faction]
	if state.commander != SKILL_RULES.BEAR or building.construction_cost <= 0: return false
	if building.population + floori(float(building.construction_cost) / 2.0) < 1.0: return false
	# Waiting for energy/cooldown is a real recovery path only while the paid
	# receipt still exists. Natural completion consumes it before a new command.
	var deadline := building.construction_remaining
	if state.cooldowns[0] >= deadline: return false
	if state.energy >= SKILL_RULES.BEAR_COSTS[0]: return true
	# Known tower restorations/conversions can change regeneration before this
	# receipt expires. Integrate only those authored building clocks, preserving
	# the diminishing bonus for the number of simultaneously active towers.
	var changes: Dictionary[float, int] = {0.0: 0, deadline: 0}
	for supply: WarBuilding in buildings:
		if supply.faction != building.faction: continue
		var start := supply.disruption_remaining
		var end := deadline
		if supply.kind == 3:
			if supply.is_constructing and supply.conversion_target >= 0:
				end = minf(end, supply.construction_remaining)
		elif supply.is_constructing and supply.conversion_target == 3:
			start = maxf(start, supply.construction_remaining)
		else:
			continue
		if start >= end: continue
		changes[start] = changes.get(start, 0) + 1
		changes[end] = changes.get(end, 0) - 1
	var times := changes.keys()
	times.sort()
	var count := 0
	var previous := 0.0
	var energy_at_completion := state.energy + SKILL_RULES.natural_energy_between(elapsed, deadline)
	for time: float in times:
		energy_at_completion += SKILL_RULES.energy_tower_bonus(count) * (time - previous)
		count += changes[time]
		previous = time
	return energy_at_completion > SKILL_RULES.BEAR_COSTS[0]

func _check_victory() -> void:
	if finished:
		return
	var remaining: Array[bool] = [false, false]
	var can_make_progress := false
	for building: Node3D in buildings:
		if building.faction < 0:
			continue
		remaining[building.faction % 2] = true
		# Fractions in separate garrisons cannot be combined without a full soldier
		# leaving one doorway. An existing or unfinished residence can still grow it.
		if building.kind == 0 or building.conversion_target == 0 or floori(building.population) >= 1:
			can_make_progress = true
		elif not can_make_progress and _toolbox_can_restore_population(building):
			can_make_progress = true
	# Living productive buildings already prove that ordinary battles continue.
	# Only inspect marching armies when elimination/stalemate is possible.
	if remaining[PLAYER] and remaining[ENEMY] and can_make_progress:
		return
	for unit: WarMarches.MarchUnit in marches._units:
		remaining[unit.order.faction % 2] = true
		can_make_progress = true
		if remaining[PLAYER] and remaining[ENEMY]: return
	# Resolve elimination before asking whether the remaining armies are stuck.
	if not remaining[PLAYER] and not remaining[ENEMY]:
		_finish_match(-1)
	elif not remaining[ENEMY]:
		_finish_match(PLAYER)
	elif not remaining[PLAYER]:
		_finish_match(ENEMY)
	elif not can_make_progress:
		_finish_match(-1)

func _finish_match(winner: int) -> void:
	finished = true
	winner_team = winner
	_local_menu = true
	_cancel_drag()
	camera_rig.dragging = false
	_cancel_skill_drag()
	if winner < 0:
		hud.show_draw()
	else:
		hud.show_result(winner == local_team)
	audio.set_world_paused(true)
	world_effects.set_running(false)
	map.set_visual_paused(true)
	for building: Node3D in buildings:
		building.set_visual_paused(true)
	if winner >= 0:
		audio.play_ui(&"war_victory" if winner == local_team else &"war_defeat")
	presentation_event.emit("result", {"winner": winner})
	update_hud()

func refresh_debug_panel() -> void:
	if hud.debug_visible():
		hud.get_node("%DebugPanel").update_data(DEBUG_DATA.capture(self))

func _on_debug_visibility_changed(visible: bool) -> void:
	if visible:
		_cancel_drag()
		_cancel_skill_drag()
		camera_rig.dragging = false
		update_hud()

func update_hud() -> void:
	if not is_node_ready():
		return
	var faction_buildings: Array[int] = []
	var morale_stars: Array[float] = []
	var faction_names: Array[String] = []
	var faction_commanders: Array[StringName] = []
	var faction_skill_statuses: Array = []
	var faction_skill_active: Array[bool] = []
	# Only our alliance's population is public. The shared color bar measures
	# visible territory, so neither its width nor a total reveals enemy garrisons.
	faction_buildings.resize(faction_count)
	faction_buildings.fill(0)
	var player_population := 0.0
	for unit: WarMarches.MarchUnit in marches._units:
		if FACTIONS.allied(unit.order.faction, local_faction):
			player_population += 1.0
	for building: WarBuilding in buildings:
		if building.faction >= 0:
			faction_buildings[building.faction] += 1
			if FACTIONS.allied(building.faction, local_faction):
				player_population += building.available_population
	for faction: int in faction_count:
		morale_stars.append(morale.stars(faction))
		faction_names.append(faction_name(faction))
		faction_commanders.append(faction_skills[faction].commander)
		faction_skill_statuses.append(public_skill_statuses_for(faction))
		faction_skill_active.append(not finished and not is_rule_paused() and not has_surrendered(faction))
	var detail: String = "住宅产兵 · 炮塔拦截 · 铁匠铺强化军团 · 能量塔恢复技力"
	if selected != null:
		match selected.kind:
			0: detail = "每秒 +%s 民兵 · %d 人停产 · 援军不限" % [selected.production_rate, selected.capacity]
			1: detail = "射程 %d · 每 %.1f 秒拦截 %d 人 · 防御 +%d%%" % [tower_range(selected), tower_interval(selected), selected.level, roundi(COMBAT_RULES.tower_defense_bonus(selected.level) * 100.0)]
			2: detail = "提高所属军团攻击与防御 · 不可升级 · 不自动产兵"
			3: detail = "提高技力恢复 · 出征占领敌方建筑 +10 技力 · 不可升级 · 不自动产兵"
		if shields.has(selected.building_id):
			detail += " · 防护罩 %ds" % ceili(shields[selected.building_id])
		if selected.disruption_remaining > 0.0:
			detail += " · 停工 %ds" % ceili(selected.disruption_remaining)
		if selected.burrow_remaining > 0.0:
			detail += " · 兔洞待命 %ds · 下次最多 50 人" % ceili(selected.burrow_remaining)
		var pig_flags: Vector3 = pig.flags_for(selected.building_id)
		for index: int in 3:
			if pig_flags[index] > 0.0:
				detail += " · %s待命 %ds" % [SKILL_RULES.PIG_NAMES[index], ceili(pig_flags[index])]
		if selected.is_population_visible() and selected.queued_population > 0:
			detail += " · 待出发 %d · 可用 %d" % [selected.queued_population, floori(selected.available_population)]
		if selected.faction >= 0 and faction_count > 2:
			detail = "%s · %s" % [faction_name(selected.faction), detail]
			if FACTIONS.allied(selected.faction, local_faction) and selected.faction != local_faction:
				detail += " · 增援抵达后归队友指挥"
	var selected_population_known: bool = selected != null and selected.is_population_visible()
	hud.update_state({"player_total": floori(player_population), "time": elapsed,
		"faction_count": faction_count, "faction_buildings": faction_buildings, "morale_stars": morale_stars, "faction_names": faction_names, "local_faction": local_faction,
		"faction_commanders": faction_commanders, "faction_skill_statuses": faction_skill_statuses, "faction_skill_active": faction_skill_active,
		"online": not match_config.is_empty(), "enemy_role": _enemy_role(),
		"global_paused": match_paused, "local_surrendered": has_surrendered(local_faction),
		"can_match_pause": can_request_match_control(local_faction), "can_surrender": can_request_match_control(local_faction),
		"pause_actor_name": faction_name(pause_faction) if pause_faction >= 0 else "",
		"map_title": map.definition.title, "map_mode": map.definition.mode_label(), "team_size": faction_count / 2,
		"percentage": percentage, "selected_name": KIND_NAMES[selected.kind] if selected != null else "",
		"send_count": dispatch_count(selected, percentage) if selected != null and selected.faction == local_faction else 0,
		"selected_population": floori(selected.population) if selected_population_known else -1, "selected_detail": detail,
		"selected_available_population": floori(selected.available_population) if selected_population_known else -1,
		"cooldowns": cooldowns, "skill_durations": active_durations, "armed_skill": armed_skill,
		"energy": energy, "energy_max": ENERGY_MAX, "energy_regen": energy_regen_for(local_faction), "energy_tower_count": energy_tower_count(local_faction), "energy_costs": SKILL_RULES.costs_for(faction_skills[local_faction].commander),
		"commander": faction_skills[local_faction].commander, "enemy_commander": faction_skills[opponent_faction()].commander,
		"skill_target_types": ["ground" if skill_is_ground(0) else "building", "ground" if skill_is_ground(1) else "building", "ground" if skill_is_ground(2) else "building", "ground" if skill_is_ground(3) else "building"], "ground_skill_radius": skill_radius(armed_skill),
		"forges": forge_count(local_faction), "selected_owned": selected != null and selected.faction == local_faction,
		"selected_faction": selected.faction if selected != null else -1, "selected_id": selected.building_id if selected != null else -1,
		"selected_kind": selected.kind if selected != null else -1, "selected_level": selected.level if selected != null else 0,
		"selected_max_level": selected.max_level if selected != null else 4,
		"construction_remaining": selected.construction_remaining if selected != null else 0.0,
		"conversion_target": selected.conversion_target if selected != null else -1,
		"upgrade_cost": selected.upgrade_cost if selected != null else 10, "convert_cost": CONVERSION_COST,
		"can_upgrade": selected != null and selected.faction == local_faction and not selected.is_constructing and selected.level < selected.max_level and selected.available_population >= selected.upgrade_cost})
	refresh_debug_panel()

func set_paused(value: bool) -> void:
	if finished or _closing:
		return
	if value != _local_menu:
		audio.play_ui(&"war_pause" if value else &"war_resume")
	_local_menu = value
	_cancel_drag()
	camera_rig.dragging = false
	_cancel_skill_drag()
	var pause_world := is_rule_paused()
	audio.set_world_paused(pause_world)
	world_effects.set_running(not pause_world)
	map.set_visual_paused(pause_world)
	for building: Node3D in buildings:
		building.set_visual_paused(pause_world)
	hud.set_paused(value)
	update_hud()

func restart() -> void:
	if _closing:
		return
	get_node("/root/Session/UIFeedback").play(&"order")
	if not match_config.is_empty():
		get_node("/root/Session").back_to_online_room()
	else:
		await prepare_shutdown()
		get_node("/root/Session").change_scene("res://scenes/block_war/block_war.tscn")

func exit_to_lobby() -> void:
	if _closing:
		return
	get_node("/root/Session/UIFeedback").play(&"cancel")
	await prepare_shutdown()
	get_node("/root/Session").back_to_lobby()

func prepare_shutdown() -> void:
	_closing = true
	_local_menu = true
	set_process(false)
	_cancel_drag()
	camera_rig.dragging = false
	# Reuse the project's native audio release acknowledgment before changing
	# scenes or closing the window, including a result sound still playing.
	var retiring_playbacks: Array[WeakRef] = audio.stop_all()
	while not retiring_playbacks.is_empty():
		await get_tree().process_frame
		retiring_playbacks = retiring_playbacks.filter(func(reference: WeakRef): return reference.get_ref() != null)
	await get_tree().process_frame

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _closing:
		await prepare_shutdown()
		get_tree().quit()

func _on_focus_exited() -> void:
	_cancel_drag()
	_cancel_skill_drag()
	update_hud()
	camera_rig.dragging = false

func clamp_to_map(point: Vector3) -> Vector3:
	var limits: Vector2 = map.definition.half_size - Vector2(6, 5)
	return Vector3(clampf(point.x, -limits.x, limits.x), 0.0, clampf(point.z, -limits.y, limits.y))

func _input(event: InputEvent) -> void:
	# Settings persist across scenes, including a host starting while a guest
	# is editing preferences. The native GUI still receives these events.
	if get_node("/root/Session/Settings").is_open():
		return
	if event is InputEventMouseMotion and camera_rig.dragging and not _local_menu:
		camera_rig.drag_by(event.relative)
		if armed_skill >= 0:
			_update_skill_drag(event.position)
		get_viewport().set_input_as_handled()
		return
	if armed_skill >= 0:
		if event is InputEventMouseMotion:
			_update_skill_drag(event.position)
			# Let native controls update hover ownership while the aim follows the pointer.
			return
		if event is InputEventKey and not event.pressed and (event.physical_keycode if event.physical_keycode != 0 else event.keycode) == _skill_keycode:
			release_skill_drag(get_viewport().get_mouse_position())
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				audio.play_ui(&"war_cancel")
				_cancel_skill_drag()
				update_hud()
				get_viewport().set_input_as_handled()
				return
			if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _skill_keycode == 0:
				release_skill_drag(event.position)
				# Native buttons also need the release to clear their mouse capture.
				return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_rig.dragging = false
		if event.button_index == MOUSE_BUTTON_LEFT and drag_source != null:
			var target: Node3D = pick_building(event.position) if not hud.is_pointer_blocked(event.position) else null
			if target != null and target != drag_source and event.position.distance_to(_drag_start) > 6.0:
				submit_player_command({"type": "dispatch", "source": drag_source.building_id, "target": target.building_id, "percent": percentage})
			elif target == drag_source and event.position.distance_to(_drag_start) <= 6.0:
				audio.play_ui(&"war_select")
			_cancel_drag()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _local_menu or finished or get_node("/root/Session/Settings").is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and selected != null:
		camera_rig.focus_at(selected.global_position)
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton or not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_MIDDLE:
			camera_rig.dragging = true
			_cancel_drag()
		MOUSE_BUTTON_WHEEL_UP:
			if drag_source != null:
				set_percentage(mini(100, percentage + 25))
			else:
				camera_rig.zoom_by(-3.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			if drag_source != null:
				set_percentage(maxi(25, percentage - 25))
			else:
				camera_rig.zoom_by(3.0)
		MOUSE_BUTTON_RIGHT:
			if armed_skill >= 0:
				audio.play_ui(&"war_cancel")
			_cancel_skill_drag()
			_cancel_drag()
			update_hud()
		MOUSE_BUTTON_LEFT:
			if armed_skill >= 0:
				get_viewport().set_input_as_handled()
				return
			var building: Node3D = pick_building(event.position)
			select_building(building)
			if building != null:
				if building.faction == local_faction:
					drag_source = building
					_drag_start = event.position
					hovered = null
				else:
					audio.play_ui(&"war_select")
	get_viewport().set_input_as_handled()

func pick_building(screen: Vector2) -> Node3D:
	var query := PhysicsRayQueryParameters3D.create(camera.project_ray_origin(screen), camera.project_ray_origin(screen) + camera.project_ray_normal(screen) * 250.0, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.collider.get_parent()

func _update_drag(screen: Vector2) -> void:
	hovered = pick_building(screen) if not hud.is_pointer_blocked(screen) else null
	order_route = PackedVector3Array()
	if hovered != null and hovered != drag_source:
		if drag_source.burrow_remaining > 0.0:
			var plan := RABBIT_SKILLS.burrow_plan(self, drag_source, hovered, percentage)
			if not plan.is_empty():
				order_route = PackedVector3Array([plan.entrance, plan.exit])
				order_route.append_array(plan.route)
		else:
			order_route = dispatch_route(drag_source, hovered)

func _cancel_drag() -> void:
	drag_source = null
	hovered = null
	# Packed arrays are shared with the route cache. Clearing this array would
	# erase a valid route and silently reject every later order for that pair.
	order_route = PackedVector3Array()

func faction_color(faction: int) -> Color:
	return FACTIONS.COLORS[faction]

func add_effect(at: Vector3, color: Color, kind: String, duration: float, radius: float = 3.8) -> void:
	effects.append({"at": at, "color": color, "kind": kind, "life": duration, "duration": duration, "radius": radius})
	if kind in ["capture", "skill", "impact"]:
		world_effects.burst(at, color, kind == "impact")
