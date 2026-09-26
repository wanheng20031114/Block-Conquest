extends Node3D
## Building-node conquest. Population is simulated here; marches only transport it.

const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺"]
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
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
const RABBIT_SKILLS := preload("res://scripts/block_war/war_rabbit_skills.gd")

class SkillState extends RefCounted:
	var commander: StringName = &"squirrel"
	var energy := 30.0
	var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var durations: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var recruit_target_id := -1

var faction_skills: Array[SkillState] = []
# The input layer and HUD expose only the human commander's account.
var cooldowns: Array[float]:
	get: return faction_skills[PLAYER].cooldowns
var active_durations: Array[float]:
	get: return faction_skills[PLAYER].durations
var energy: float:
	get: return faction_skills[PLAYER].energy
	set(value): faction_skills[PLAYER].energy = value

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
var order_route := PackedVector3Array()
var _hud_clock: float = 0.0
var _drag_start := Vector2.ZERO
var _match_ready: bool = false
var _previous_taa: bool = false
var _previous_auto_quit: bool = true
var _closing: bool = false
var rabbit_preview: Dictionary = {}
var recall_preview: Array[Dictionary] = []
var _rabbit_preview_target := -1
var _rabbit_preview_source := -1
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
	for faction: int in faction_count:
		var state := SkillState.new()
		state.commander = get_node("/root/Session").block_war_commander if faction % 2 == 0 else get_node("/root/Session").block_war_opponent_commander
		faction_skills.append(state)
	for faction: int in range(2, faction_count):
		_other_ai.append(AI_STRATEGY.new(faction))

func _ready() -> void:
	# MSAA keeps the small world-space badges and moving spear rows crisp.
	# TAA retains old Label3D glyphs when the garrison count changes.
	_previous_taa = get_viewport().use_taa
	get_viewport().use_taa = false
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	for building: Node3D in $Map/Buildings.get_children():
		buildings.append(building)
		by_id[building.building_id] = building
		tower_clocks[building.building_id] = 0.0
	marches.unit_arrived.connect(_on_unit_arrived)
	marches.unit_defeated.connect(world_effects.casualty)
	hud.percentage_changed.connect(set_percentage)
	hud.skill_requested.connect(request_skill)
	hud.pause_requested.connect(set_paused.bind(true))
	hud.resume_requested.connect(set_paused.bind(false))
	hud.restart_requested.connect(restart)
	hud.exit_requested.connect(exit_to_lobby)
	hud.upgrade_requested.connect(upgrade_selected)
	hud.convert_requested.connect(convert_selected)
	get_window().focus_exited.connect(_on_focus_exited)
	camera_rig.maximum_zoom = maxf(95.0, map.definition.half_size.y * 2.1)
	if map.definition.size_class > 0:
		camera_rig.focus_at(buildings[0].global_position, true)
		camera.far = 320.0
	select_building(buildings[0])
	_match_ready = true
	update_hud()
	hud.notify("拖动橙色住宅到中立据点，派出你的第一支民兵。")

func _exit_tree() -> void:
	get_viewport().use_taa = _previous_taa
	get_tree().auto_accept_quit = _previous_auto_quit

func _process(delta: float) -> void:
	if not _local_menu and not finished:
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
	if _local_menu or finished or delta <= 0.0:
		return
	# Integrate up to each completion before applying the next level's rules.
	# Long frames and multiple simultaneous builds keep the same production as
	# small steps, including a recruitment skill crossing the completion time.
	var remaining := delta
	while remaining > 0.0 and not finished:
		var step := remaining
		if ai_enabled:
			step = minf(step, maxf(ai_clock, 0.000001))
		if marches.has_marchers() or not projectiles.is_empty() or world_effects.has_fire():
			step = minf(step, 0.05)
		step = minf(step, world_effects.fire_step_limit())
		for building: WarBuilding in buildings:
			if building.is_constructing:
				step = minf(step, building.construction_remaining)
			if building.disruption_remaining > 0.0:
				step = minf(step, building.disruption_remaining)
		_simulate_step(step)
		remaining = maxf(0.0, remaining - step)

func _simulate_step(delta: float) -> void:
	elapsed += delta
	var recruiting := _tick_recruitment(delta)
	for state: SkillState in faction_skills:
		state.energy = minf(ENERGY_MAX, state.energy + ENERGY_REGEN * delta)
		for index: int in 4:
			state.cooldowns[index] = maxf(0.0, state.cooldowns[index] - delta)
			state.durations[index] = maxf(0.0, state.durations[index] - delta)
	for id: int in shields.keys():
		shields[id] = maxf(0.0, float(shields[id]) - delta)
		if shields[id] <= 0.0:
			shields.erase(id)
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
	audio.tick_marches(delta, marches)
	world_effects.tick(delta)
	world_effects.update_skills(delta, faction_skills, shields, by_id, marches)
	_tick_fire_buildings()
	for index: int in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0.0:
			effects.remove_at(index)
	for building: WarBuilding in buildings:
		# End-of-step restoration: movement and already-fired projectiles still
		# belong to the interval during which the building was disabled.
		var restored := building.advance_disruption(delta)
		if restored and building.faction >= 0 and building.kind == 1 and tower_clocks[building.building_id] <= 0.0:
			_fire_tower(building)
		var converting := building.conversion_target >= 0
		if building.advance_construction(delta):
			if converting and building.kind != 0:
				_cancel_building_recruitment(building.building_id)
			audio.play_world(&"war_upgrade", building.global_position)
			if building.faction == PLAYER:
				hud.notify("改建完成 · %s" % KIND_NAMES[building.kind] if converting else "%s已升至 %d 级" % [KIND_NAMES[building.kind], building.level])
			update_hud()
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

func _cancel_recruitment(faction: int = PLAYER) -> void:
	faction_skills[faction].recruit_target_id = -1
	faction_skills[faction].durations[0] = 0.0

func _cancel_building_recruitment(building_id: int) -> void:
	for faction: int in faction_count:
		if faction_skills[faction].recruit_target_id == building_id:
			_cancel_recruitment(faction)

func set_percentage(value: int) -> void:
	if value in [25, 50, 75, 100] and value != percentage and not _local_menu and not finished:
		percentage = value
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

func issue_order(source: Node3D, target: Node3D, amount_percent: int, faction: int = PLAYER) -> int:
	if finished or _local_menu or source == null or target == null or source == target:
		return 0
	if source.faction != faction or amount_percent not in [25, 50, 75, 100]:
		return 0
	var count := floori(source.population * amount_percent / 100.0)
	if count < 1:
		if faction == PLAYER:
			hud.notify("当前比例不足 1 名民兵 · 按 4 派出全部驻军")
			audio.play_ui(&"war_denied")
		return 0
	var route: PackedVector3Array = map.get_building_route(source, target)
	if route.size() < 2:
		if faction == PLAYER:
			hud.notify("没有可通行的路线")
			audio.play_ui(&"war_denied")
		return 0
	source.population -= count
	source.refresh_visual()
	marches.send(source.building_id, target.building_id, faction, count, route, 1.0)
	if faction == PLAYER:
		audio.play_ui(&"war_order")
		var verb := "增援" if FACTIONS.allied(target.faction, PLAYER) else "进攻"
		var transfer := " · 抵达后归队友指挥" if target.faction != PLAYER and FACTIONS.allied(target.faction, PLAYER) else ""
		hud.notify("%d 名民兵出发 · %s%s%s" % [count, verb, KIND_NAMES[target.kind], transfer])
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

func attack_bonus(faction: int) -> float:
	return 0.1 * forge_count(faction)

func defense_bonus(building: Node3D) -> float:
	var value: float = 0.05 * building.level if building.kind == 1 else 0.0
	if shields.has(building.building_id):
		value += SKILL_RULES.SHIELD_DEFENSE
	return value

func combat_multiplier(faction: int, target: Node3D) -> float:
	# Sum percentage-point bonuses before scaling troops. Preview and AI use
	# this same live coefficient, including ownership and construction changes.
	return 1.0 + attack_bonus(faction) - defense_bonus(target)

func _on_unit_arrived(target_id: int, faction: int, strength: float) -> void:
	var target: Node3D = by_id[target_id]
	if FACTIONS.allied(target.faction, faction):
		# Entering a teammate's building transfers command with the garrison.
		# Ownership stays with the recipient; later orders use that building's faction.
		target.population += strength
		audio.play_world(&"war_reinforce", target.global_position)
	else:
		var damage: float = strength * combat_multiplier(faction, target)
		if target.population + 0.00001 >= damage:
			target.population = maxf(0.0, target.population - damage)
		else:
			var survivors: float = strength * (1.0 - target.population / damage)
			var previous_faction: int = target.faction
			target.cancel_construction()
			target.clear_disruption()
			target.faction = faction
			_cancel_building_recruitment(target_id)
			target.population = survivors
			target.level = maxi(1, target.level - 1)
			shields.erase(target_id)
			target.pulse_capture()
			add_effect(target.global_position, faction_color(faction), "capture", 1.1)
			if faction == PLAYER:
				audio.play_ui(&"war_capture")
			elif previous_faction == PLAYER:
				audio.play_ui(&"war_lost")
			if faction == PLAYER:
				hud.notify("已占领%s · %s" % [KIND_NAMES[target.kind], "每秒 +%s 民兵" % target.production_rate if target.kind == 0 else ("炮塔开始拦截敌军" if target.kind == 1 else "全军攻击 +10%")])
			tower_clocks[target_id] = 0.6
		if effects.size() < 80:
			add_effect(target.global_position, faction_color(faction), "hit", 0.2)
		audio.play_world(&"war_melee", target.global_position)
	target.refresh_visual()

func _fire_tower(building: Node3D) -> void:
	if building.disruption_remaining > 0.0:
		return
	var targets: Array[WarMarches.MarchUnit] = marches.acquire_targets(building.global_position, building.faction, tower_range(building), building.level)
	if targets.is_empty():
		return
	tower_clocks[building.building_id] = tower_interval(building)
	building.fire_at(targets[0].position)
	var muzzle: Vector3 = building.muzzle_position()
	world_effects.hit(muzzle, (targets[0].position - muzzle).normalized(), true)
	for target: WarMarches.MarchUnit in targets:
		var destination := target.position + Vector3(0, 0.65, 0)
		projectiles.append({"target": target, "at": muzzle, "position": muzzle, "previous": muzzle,
			"to": destination, "age": 0.0, "duration": clampf(muzzle.distance_to(destination) / 32.0, 0.07, 0.48)})
	world_effects.render_projectiles(projectiles)
	audio.play_world(&"cannon_shot", building.global_position)

func _tick_projectiles(delta: float) -> void:
	for index: int in range(projectiles.size() - 1, -1, -1):
		var shot: Dictionary = projectiles[index]
		var target: WarMarches.MarchUnit = shot.target
		shot.age += delta
		shot.previous = shot.position
		if target.alive:
			shot.to = target.position + Vector3(0, 0.65, 0)
		var progress := minf(1.0, shot.age / shot.duration)
		shot.position = shot.at.lerp(shot.to, progress) + Vector3(0, sin(progress * PI) * 0.65, 0)
		if progress >= 1.0:
			var direction: Vector3 = (shot.to - shot.at).normalized()
			if not marches.hit_target(target, direction):
				world_effects.hit(shot.to, direction)
			projectiles.remove_at(index)
	world_effects.render_projectiles(projectiles)

func _tick_fire_buildings() -> void:
	for fire: WarFireWave in world_effects.get_node("FireWaves").get_children():
		if fire.age >= WarFireWave.BURN_TIME:
			continue
		for building: WarBuilding in buildings:
			if FACTIONS.allied(building.faction, fire.faction) or fire.hit_buildings.has(building.building_id):
				continue
			var offset := Vector2(building.global_position.x - fire.global_position.x, building.global_position.z - fire.global_position.z)
			if offset.length() <= fire.front(fire.age):
				fire.hit_buildings[building.building_id] = true
				building.population = maxf(0.0, building.population - IMPACT_DAMAGE * (1.0 - defense_bonus(building)))
				building.refresh_visual()

func tower_range(building: Node3D) -> float:
	return 9.0 + building.level * 2.0

func tower_interval(building: Node3D) -> float:
	return maxf(0.55, 1.5 - 0.3 * (building.level - 1))

func request_skill(index: int, from_keyboard: bool = false) -> void:
	if not _skill_available(index):
		return
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
	var valid: bool
	if faction_skills[PLAYER].commander == SKILL_RULES.RABBIT and armed_skill in [2, 3]:
		_refresh_rabbit_preview(refresh_preview)
		valid = not recall_preview.is_empty() if armed_skill == 2 else not rabbit_preview.is_empty()
	else:
		valid = ground_skill_target.is_finite() if skill_is_ground(armed_skill) else _valid_skill_target(armed_skill, hovered)
	hud.set_skill_drag_target(valid, screen)
	overlay.queue_redraw()

func release_skill_drag(screen: Vector2) -> void:
	var index := armed_skill
	_update_skill_drag(screen, true)
	var target := hovered
	var success := false
	if skill_is_ground(index) and ground_skill_target.is_finite():
		success = cast_ground_skill(index, ground_skill_target)
	elif not skill_is_ground(index) and _valid_skill_target(index, target):
		if faction_skills[PLAYER].commander != SKILL_RULES.RABBIT or index != 3 or not rabbit_preview.is_empty():
			success = cast_skill(index, target, PLAYER, _rabbit_preview_source)
	_cancel_skill_drag()
	if success and target != null:
		select_building(target)
	update_hud()
	overlay.queue_redraw()

func _cancel_skill_drag() -> void:
	armed_skill = -1
	_skill_keycode = 0
	ground_skill_target = Vector3.INF
	hovered = null
	rabbit_preview = {}
	recall_preview = []
	_rabbit_preview_target = -1
	_rabbit_preview_source = -1
	_rabbit_preview_time = -1.0

func skill_is_ground(index: int, faction: int = PLAYER) -> bool:
	return index >= 0 and SKILL_RULES.is_ground(index, faction_skills[faction].commander)

func skill_radius(index: int, faction: int = PLAYER) -> float:
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		return SKILL_RULES.RABBIT_HASTE_RADIUS if index == 0 else SKILL_RULES.RECALL_RADIUS
	return SKILL_RULES.HASTE_RADIUS if index == 1 else IMPACT_RADIUS

func _refresh_rabbit_preview(force: bool = false) -> void:
	var id: int = hovered.building_id if hovered != null else -1
	var changed := id != _rabbit_preview_target
	if not force and not changed and elapsed - _rabbit_preview_time < 0.1:
		return
	_rabbit_preview_time = elapsed
	_rabbit_preview_target = id
	if changed:
		_rabbit_preview_source = -1
	if armed_skill == 2:
		recall_preview = RABBIT_SKILLS.recall_plan(self, hovered, PLAYER)
	else:
		rabbit_preview = RABBIT_SKILLS.burrow_plan(self, hovered, PLAYER, _rabbit_preview_source)
		if _rabbit_preview_source < 0 and not rabbit_preview.is_empty():
			_rabbit_preview_source = rabbit_preview.source.building_id

func can_cast_skill(index: int, faction: int = PLAYER) -> bool:
	return index >= 0 and index < 4 and faction >= 0 and faction < faction_count and not _local_menu and not finished and faction_skills[faction].cooldowns[index] <= 0.0 and faction_skills[faction].energy >= SKILL_RULES.costs_for(faction_skills[faction].commander)[index]

func _skill_available(index: int, faction: int = PLAYER) -> bool:
	if faction != PLAYER:
		return can_cast_skill(index, faction)
	if index < 0 or index >= 4 or _local_menu or finished:
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

func _valid_skill_target(index: int, target: Node3D, faction: int = PLAYER) -> bool:
	if target == null:
		return false
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		match index:
			1: return FACTIONS.hostile(target.faction, faction) and target.disruption_remaining <= 0.0
			2: return not RABBIT_SKILLS.recall_plan(self, target, faction).is_empty()
			3: return not RABBIT_SKILLS.burrow_plan(self, target, faction).is_empty()
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

func cast_skill(index: int, target: Node3D, faction: int = PLAYER, locked_source: int = -1) -> bool:
	if not _skill_available(index, faction):
		return false
	if not _valid_skill_target(index, target, faction):
		if faction == PLAYER:
			if faction_skills[faction].commander == SKILL_RULES.RABBIT:
				hud.notify(["拖至战场地面后松手", "选择尚未停工的敌方建筑", "选择附近有部队可召回的自己的建筑", "附近需要有至少 22 人的自己的建筑"][index])
			else:
				hud.notify("选择尚未受此军令影响的己方或盟友住宅" if index == 0 else ("选择尚未受防护罩保护的己方或盟友建筑" if index == 2 else "拖至战场地面后松手"))
			audio.play_ui(&"war_denied")
		return false
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		if not RABBIT_SKILLS.cast(self, index, target, faction, locked_source):
			return false
		_commit_skill(index, faction)
		audio.play_world([&"war_skill_drum", &"war_rebuild", &"war_skill_command", &"war_march"][index], target.global_position)
		target.refresh_visual()
		update_hud()
		return true
	match index:
		0:
			faction_skills[faction].recruit_target_id = target.building_id
			add_effect(target.global_position, Color(1.0, 0.8, 0.25), "skill", 1.1)
		2:
			shields[target.building_id] = SKILL_DURATIONS[2]
			add_effect(target.global_position, Color(0.45, 0.8, 1.0), "skill", 1.1)
	_commit_skill(index, faction)
	var skill_sounds: Array[StringName] = [&"war_skill_command", &"war_skill_drum", &"war_skill_shield"]
	audio.play_world(skill_sounds[index], target.global_position)
	if faction == PLAYER:
		hud.notify("%s · %s" % [SKILL_RULES.NAMES[index], SKILL_RULES.effect_text(index)])
	if target != null:
		target.refresh_visual()
	world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
	update_hud()
	return true

func cast_ground_skill(index: int, at: Vector3, faction: int = PLAYER) -> bool:
	if not skill_is_ground(index, faction) or not _skill_available(index, faction):
		return false
	if not _valid_ground_skill_target(at):
		if faction == PLAYER:
			hud.notify("请选择战场内的地面 · 右键取消")
			audio.play_ui(&"war_denied")
		return false
	var center := Vector3(at.x, 0.0, at.z)
	if faction_skills[faction].commander == SKILL_RULES.RABBIT:
		marches.create_haste_zone(faction, center, SKILL_RULES.RABBIT_HASTE_RADIUS, SKILL_RULES.RABBIT_DURATIONS[0], SKILL_RULES.RABBIT_HASTE_MULTIPLIER, SKILL_RULES.RABBIT)
		_commit_skill(index, faction)
		audio.play_world(&"war_skill_drum", center)
		world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
		update_hud()
		return true
	if index == 1:
		marches.create_haste_zone(faction, center, SKILL_RULES.HASTE_RADIUS, SKILL_DURATIONS[1], SKILL_RULES.HASTE_MULTIPLIER)
	else:
		var fire: WarFireWave = world_effects.start_fire(center, IMPACT_RADIUS, faction)
		marches.ignite_at(center, fire.front(0.0))
		_tick_fire_buildings()
	_commit_skill(index, faction)
	audio.play_world(&"war_skill_drum" if index == 1 else &"war_skill_breach", center)
	if faction == PLAYER:
		hud.notify("疾行区域已展开 · 圈内自己的部队提速，离开恢复" if index == 1 else "火焰已点燃 · 接触火焰的双方士兵都会死亡")
	world_effects.update_skills(0.0, faction_skills, shields, by_id, marches)
	update_hud()
	return true

func _commit_skill(index: int, faction: int = PLAYER) -> void:
	var state := faction_skills[faction]
	state.energy -= SKILL_RULES.costs_for(state.commander)[index]
	state.cooldowns[index] = SKILL_RULES.cooldowns_for(state.commander)[index]
	state.durations[index] = SKILL_RULES.durations_for(state.commander)[index]
	if faction == PLAYER:
		_cancel_skill_drag()
		_cancel_drag()

func _valid_ground_skill_target(at: Vector3) -> bool:
	return at.is_finite() and absf(at.x) <= map.definition.half_size.x and absf(at.z) <= map.definition.half_size.y

func skill_ground_at(screen: Vector2) -> Vector3:
	if not get_viewport().get_visible_rect().has_point(screen) or hud.is_pointer_blocked(screen):
		return Vector3.INF
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null or not _valid_ground_skill_target(hit):
		return Vector3.INF
	return hit

func upgrade_selected() -> void:
	if _local_menu or finished or selected == null or selected.faction != PLAYER or selected.level >= selected.max_level or selected.is_constructing:
		return
	var cost: int = selected.upgrade_cost
	if selected.population < cost:
		hud.notify("升级需要 %d 名驻军" % cost)
		audio.play_ui(&"war_denied")
		return
	selected.population -= cost
	selected.begin_construction()
	selected.refresh_visual()
	audio.play_world(&"war_rebuild", selected.global_position)
	hud.notify("%s开始升级 · 10 秒后完成" % KIND_NAMES[selected.kind])
	update_hud()

func convert_selected(kind: int) -> void:
	if _local_menu or finished or selected == null or selected.faction != PLAYER or kind not in [0, 1, 2] or selected.kind == kind or selected.is_constructing:
		return
	if selected.population < CONVERSION_COST:
		hud.notify("改建需要 %d 名驻军" % CONVERSION_COST)
		audio.play_ui(&"war_denied")
		return
	selected.population -= CONVERSION_COST
	selected.begin_construction(kind)
	selected.refresh_visual()
	audio.play_world(&"war_rebuild", selected.global_position)
	hud.notify("开始改建%s · 10 秒后完成" % KIND_NAMES[kind])
	update_hud()

func _ai_turn() -> void:
	_ai_strategy.take_turn(self)
	for strategy: RefCounted in _other_ai:
		strategy.take_turn(self)

func team_total_for(faction: int) -> int:
	var count: float = marches.team_total_for(faction)
	for building: WarBuilding in buildings:
		if FACTIONS.allied(building.faction, faction):
			count += building.population
	return floori(count)

func incoming_damage_for(building: WarBuilding, incoming: Dictionary[Vector2i, int]) -> float:
	var damage := 0.0
	for faction: int in faction_count:
		if FACTIONS.hostile(building.faction, faction):
			damage += incoming.get(Vector2i(building.building_id, faction), 0) * combat_multiplier(faction, building)
	return damage

func total_for(faction: int) -> int:
	var count: float = marches.total_for(faction)
	for building: Node3D in buildings:
		if building.faction == faction:
			count += building.population
	return floori(count)

func _check_victory() -> void:
	if finished:
		return
	var remaining: Array[bool] = [marches.team_total_for(PLAYER) > 0, marches.team_total_for(ENEMY) > 0]
	var can_make_progress: bool = remaining[PLAYER] or remaining[ENEMY]
	for building: Node3D in buildings:
		if building.faction < 0:
			continue
		remaining[building.faction % 2] = true
		# Fractions in separate garrisons cannot be combined without a full soldier
		# leaving one doorway. An existing or unfinished residence can still grow it.
		if building.kind == 0 or building.conversion_target == 0 or floori(building.population) >= 1:
			can_make_progress = true
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
	_local_menu = true
	_cancel_drag()
	camera_rig.dragging = false
	_cancel_skill_drag()
	if winner < 0:
		hud.show_draw()
	else:
		hud.show_result(winner == PLAYER)
	audio.set_world_paused(true)
	world_effects.set_running(false)
	map.set_visual_paused(true)
	for building: Node3D in buildings:
		building.set_visual_paused(true)
	if winner >= 0:
		audio.play_ui(&"war_victory" if winner == PLAYER else &"war_defeat")
	update_hud()

func update_hud() -> void:
	if not is_node_ready():
		return
	var detail: String = "住宅产兵 · 炮塔拦截 · 铁匠铺提升所属军团攻击"
	if selected != null:
		match selected.kind:
			0: detail = "每秒 +%s 民兵 · %d 人停产 · 援军不限" % [selected.production_rate, selected.capacity]
			1: detail = "射程 %d · 每 %.1f 秒拦截 %d 人 · 守备 +%d%%" % [tower_range(selected), tower_interval(selected), selected.level, selected.level * 5]
			2: detail = "所属军团攻击 +10% · 不可升级 · 不自动产兵"
		if shields.has(selected.building_id):
			detail += " · 防护罩 %ds" % ceili(shields[selected.building_id])
		if selected.disruption_remaining > 0.0:
			detail += " · 停工 %ds" % ceili(selected.disruption_remaining)
		if selected.faction >= 0 and faction_count > 2:
			detail = "%s · %s" % [FACTIONS.NAMES[selected.faction], detail]
			if FACTIONS.allied(selected.faction, PLAYER) and selected.faction != PLAYER:
				detail += " · 增援抵达后归队友指挥"
	hud.update_state({"player_total": team_total_for(PLAYER), "enemy_total": team_total_for(ENEMY), "time": elapsed,
		"map_title": map.definition.title, "map_mode": map.definition.mode_label(), "team_size": faction_count / 2,
		"percentage": percentage, "selected_name": KIND_NAMES[selected.kind] if selected != null else "",
		"send_count": floori(selected.population * percentage / 100.0) if selected != null else 0,
		"selected_population": floori(selected.population) if selected != null else 0, "selected_detail": detail,
		"cooldowns": cooldowns, "skill_durations": active_durations, "armed_skill": armed_skill,
		"energy": energy, "energy_max": ENERGY_MAX, "energy_regen": ENERGY_REGEN, "energy_costs": SKILL_RULES.costs_for(faction_skills[PLAYER].commander),
		"commander": faction_skills[PLAYER].commander, "enemy_commander": faction_skills[ENEMY].commander,
		"skill_target_types": ["ground", "building", "building", "building"] if faction_skills[PLAYER].commander == SKILL_RULES.RABBIT else ["building", "ground", "building", "ground"], "ground_skill_radius": skill_radius(armed_skill),
		"forges": forge_count(PLAYER), "selected_owned": selected != null and selected.faction == PLAYER,
		"selected_faction": selected.faction if selected != null else -1, "selected_id": selected.building_id if selected != null else -1,
		"selected_kind": selected.kind if selected != null else -1, "selected_level": selected.level if selected != null else 0,
		"selected_max_level": selected.max_level if selected != null else 4,
		"construction_remaining": selected.construction_remaining if selected != null else 0.0,
		"conversion_target": selected.conversion_target if selected != null else -1,
		"upgrade_cost": selected.upgrade_cost if selected != null else 10, "convert_cost": CONVERSION_COST,
		"can_upgrade": selected != null and selected.faction == PLAYER and not selected.is_constructing and selected.level < selected.max_level and selected.population >= selected.upgrade_cost})

func set_paused(value: bool) -> void:
	if finished or _closing:
		return
	if value != _local_menu:
		audio.play_ui(&"war_pause" if value else &"war_resume")
	_local_menu = value
	_cancel_drag()
	camera_rig.dragging = false
	_cancel_skill_drag()
	audio.set_world_paused(value)
	world_effects.set_running(not value)
	map.set_visual_paused(value)
	for building: Node3D in buildings:
		building.set_visual_paused(value)
	hud.set_paused(value)
	update_hud()

func restart() -> void:
	if _closing:
		return
	await prepare_shutdown()
	get_node("/root/Session").change_scene("res://scenes/block_war/block_war.tscn")

func exit_to_lobby() -> void:
	if _closing:
		return
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
				issue_order(drag_source, target, percentage)
			_cancel_drag()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and camera_rig.dragging and not _local_menu:
		camera_rig.drag_by(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if _local_menu or finished:
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
			if drag_source != null or armed_skill >= 0:
				audio.play_ui(&"war_cancel")
			armed_skill = -1
			ground_skill_target = Vector3.INF
			_cancel_drag()
			update_hud()
		MOUSE_BUTTON_LEFT:
			if armed_skill >= 0:
				get_viewport().set_input_as_handled()
				return
			var building: Node3D = pick_building(event.position)
			select_building(building)
			if building != null:
				audio.play_ui(&"war_select")
				if building.faction == PLAYER:
					drag_source = building
					_drag_start = event.position
					hovered = null
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
	var target: Node3D = pick_building(screen) if not hud.is_pointer_blocked(screen) else null
	if target != hovered:
		hovered = target
		order_route = PackedVector3Array()
		if hovered != null and hovered != drag_source:
			order_route = map.get_building_route(drag_source, hovered)
			audio.play_ui(&"war_drag")

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
