extends Node3D
## Building-node conquest. Population is simulated here; marches only transport it.

const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺"]
const SKILL_COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 60.0]
const SKILL_DURATIONS: Array[float] = [6.0, 8.0, 10.0, 0.0]
const SKILL_ENERGY_COSTS: Array[float] = [30.0, 40.0, 35.0, 60.0]
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 2.0
const RECRUIT_RATE := 5.0
const IMPACT_RADIUS := 4.5
const IMPACT_DAMAGE := 35.0
const CONVERSION_COST := 20
const PLAYER := 0
const ENEMY := 1
const AI_STRATEGY := preload("res://scripts/block_war/war_ai.gd")

var buildings: Array[Node3D] = []
var by_id: Dictionary = {}
var selected: Node3D
var drag_source: Node3D
var hovered: Node3D
var percentage: int = 50
var elapsed: float = 0.0
var cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var active_durations: Array[float] = [0.0, 0.0, 0.0, 0.0]
var energy: float = ENERGY_MAX
var armed_skill: int = -1
var _skill_keycode := 0
var ground_skill_target := Vector3.INF
var _recruit_target_id: int = -1
var finished: bool = false
var _local_menu: bool = false
var ai_enabled: bool = true
var ai_clock: float = 6.0
var _ai_strategy := AI_STRATEGY.new()
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

@onready var map: Node3D = $Map
@onready var marches: Node3D = $Marches
@onready var camera_rig: Node3D = $CameraRig
@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var hud: CanvasLayer = $HUD
@onready var audio: Node = $Audio
@onready var overlay: Control = $Orders/Overlay
@onready var world_effects: Node3D = $Effects

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
		_simulate_step(step)
		remaining = maxf(0.0, remaining - step)

func _simulate_step(delta: float) -> void:
	elapsed += delta
	energy = minf(ENERGY_MAX, energy + ENERGY_REGEN * delta)
	var recruiting_id := _tick_recruitment(delta)
	for index: int in 4:
		cooldowns[index] = maxf(0.0, cooldowns[index] - delta)
		active_durations[index] = maxf(0.0, active_durations[index] - delta)
	for id: int in shields.keys():
		shields[id] = maxf(0.0, float(shields[id]) - delta)
		if shields[id] <= 0.0:
			shields.erase(id)
	for building: Node3D in buildings:
		# Reinforcement can exceed the soft cap. Only automatic growth stops there.
		if building.faction >= 0 and building.kind == 0 and building.population < building.capacity and building.building_id != recruiting_id:
			building.population = minf(building.capacity, building.population + building.production_rate * delta)
		if building.faction >= 0 and building.kind == 1:
			tower_clocks[building.building_id] = maxf(0.0, float(tower_clocks[building.building_id]) - delta)
			if tower_clocks[building.building_id] <= 0.0:
				_fire_tower(building)
		building.refresh_visual()
	marches.tick(delta, world_effects.fire_segments(delta))
	_tick_projectiles(delta)
	audio.tick_marches(delta, marches)
	world_effects.tick(delta, not shields.is_empty())
	_tick_fire_buildings()
	for index: int in range(effects.size() - 1, -1, -1):
		effects[index].life -= delta
		if effects[index].life <= 0.0:
			effects.remove_at(index)
	for building: WarBuilding in buildings:
		var converting := building.conversion_target >= 0
		if building.advance_construction(delta):
			if converting and building.building_id == _recruit_target_id and building.kind != 0:
				_cancel_recruitment()
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

func _tick_recruitment(delta: float) -> int:
	if _recruit_target_id < 0:
		return -1
	var target: Node3D = by_id[_recruit_target_id]
	if target.faction != PLAYER or target.kind != 0:
		_cancel_recruitment()
		return -1
	# Integrate only the remaining effect time, including a tick that crosses its
	# end. Level-dependent production stops at the soft cap, even if a long tick's
	# recruitment crosses that cap; the +5/s bonus itself remains uncapped.
	var active_time := minf(delta, active_durations[0])
	var rate: float = target.production_rate
	var ordinary_time := minf(active_time, maxf(0.0, target.capacity - target.population) / (RECRUIT_RATE + rate))
	target.population += RECRUIT_RATE * active_time + rate * ordinary_time
	if target.population < target.capacity:
		target.population = minf(target.capacity, target.population + rate * (delta - active_time))
	if delta >= active_durations[0]:
		_recruit_target_id = -1
	return target.building_id

func _cancel_recruitment() -> void:
	_recruit_target_id = -1
	active_durations[0] = 0.0

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
		var verb := "增援" if target.faction == PLAYER else "进攻"
		hud.notify("%d 名民兵出发 · %s%s" % [count, verb, KIND_NAMES[target.kind]])
		add_effect(target.global_position, Color(1.0, 0.77, 0.3), "order", 0.65)
	update_hud()
	return count

func forge_levels(faction: int) -> int:
	if faction < 0:
		return 0
	var levels: int = 0
	for building: Node3D in buildings:
		if building.faction == faction and building.kind == 2:
			levels += building.level
	return levels

func attack_multiplier(faction: int) -> float:
	return 1.0 + 0.1 * forge_levels(faction)

func defense_multiplier(building: Node3D) -> float:
	var value: float = 1.0 + 0.1 * forge_levels(building.faction) + 0.1 * (building.level - 1)
	if shields.has(building.building_id):
		value *= 2.0
	return value

func _on_unit_arrived(target_id: int, faction: int, strength: float) -> void:
	var target: Node3D = by_id[target_id]
	if target.faction == faction:
		target.population += strength
		audio.play_world(&"war_reinforce", target.global_position)
	else:
		var damage: float = strength * attack_multiplier(faction) / defense_multiplier(target)
		if target.population + 0.00001 >= damage:
			target.population = maxf(0.0, target.population - damage)
		else:
			var survivors: float = strength * (1.0 - target.population / damage)
			var previous_faction: int = target.faction
			target.cancel_construction()
			target.faction = faction
			if target_id == _recruit_target_id:
				_cancel_recruitment()
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
				hud.notify("已占领%s · %s" % [KIND_NAMES[target.kind], "每秒 +%s 民兵" % target.production_rate if target.kind == 0 else ("炮塔开始拦截敌军" if target.kind == 1 else "全军攻防提升")])
			tower_clocks[target_id] = 0.6
		if effects.size() < 80:
			add_effect(target.global_position, faction_color(faction), "hit", 0.2)
		audio.play_world(&"war_melee", target.global_position)
	target.refresh_visual()

func _fire_tower(building: Node3D) -> void:
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
		if fire.age > WarFireWave.BURN_TIME:
			continue
		for building: WarBuilding in buildings:
			if building.faction == PLAYER or fire.hit_buildings.has(building.building_id):
				continue
			var offset := Vector2(building.global_position.x - fire.global_position.x, building.global_position.z - fire.global_position.z)
			if offset.length() <= fire.front(fire.age):
				fire.hit_buildings[building.building_id] = true
				building.population = maxf(0.0, building.population - IMPACT_DAMAGE / defense_multiplier(building))
				building.refresh_visual()

func tower_range(building: Node3D) -> float:
	return 9.0 + building.level * 2.0

func tower_interval(building: Node3D) -> float:
	return maxf(0.55, 1.5 - 0.3 * (building.level - 1))

func request_skill(index: int, from_keyboard: bool = false) -> void:
	if not _skill_available(index):
		return
	_cancel_drag()
	armed_skill = index
	_skill_keycode = [KEY_Q, KEY_W, KEY_E, KEY_R][index] if from_keyboard else 0
	_update_skill_drag(get_viewport().get_mouse_position())
	update_hud()
	overlay.queue_redraw()

func _update_skill_drag(screen: Vector2) -> void:
	ground_skill_target = skill_ground_at(screen)
	var over_battlefield: bool = get_viewport().get_visible_rect().has_point(screen) and not hud.is_pointer_blocked(screen)
	hovered = pick_building(screen) if over_battlefield and armed_skill in [0, 2] else null
	var valid := ground_skill_target.is_finite() if armed_skill in [1, 3] else _valid_skill_target(armed_skill, hovered)
	hud.set_skill_drag_target(valid, screen)
	overlay.queue_redraw()

func release_skill_drag(screen: Vector2) -> void:
	var index := armed_skill
	_update_skill_drag(screen)
	var target := hovered
	var success := false
	if index == 3 and ground_skill_target.is_finite():
		success = cast_ground_skill(index, ground_skill_target)
	elif index == 1 and ground_skill_target.is_finite():
		success = cast_skill(index, null)
	elif index in [0, 2] and _valid_skill_target(index, target):
		success = cast_skill(index, target)
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

func can_cast_skill(index: int) -> bool:
	return index >= 0 and index < 4 and not _local_menu and not finished and cooldowns[index] <= 0.0 and energy >= SKILL_ENERGY_COSTS[index]

func _skill_available(index: int) -> bool:
	if index < 0 or index >= 4 or _local_menu or finished:
		return false
	if cooldowns[index] > 0.0:
		hud.notify("技能冷却中 · 还需 %d 秒" % ceili(cooldowns[index]))
		audio.play_ui(&"war_denied")
		return false
	if energy < SKILL_ENERGY_COSTS[index]:
		hud.notify("技力不足 · 需要 %d，还差 %d" % [int(SKILL_ENERGY_COSTS[index]), ceili(SKILL_ENERGY_COSTS[index] - energy)])
		audio.play_ui(&"war_denied")
		return false
	return true

func _valid_skill_target(index: int, target: Node3D) -> bool:
	if index == 1:
		return true
	if target == null:
		return false
	if index == 0:
		return target.faction == PLAYER and target.kind == 0
	if index == 2:
		return target.faction == PLAYER
	return false

func cast_skill(index: int, target: Node3D) -> bool:
	if not _skill_available(index):
		return false
	if not _valid_skill_target(index, target):
		hud.notify("拖至己方住宅后松手" if index == 0 else ("拖至己方建筑后松手" if index == 2 else "拖至战场地面后松手"))
		audio.play_ui(&"war_denied")
		return false
	match index:
		0:
			_recruit_target_id = target.building_id
			add_effect(target.global_position, Color(1.0, 0.8, 0.25), "skill", 1.1)
			hud.notify("征召军令 · 持续 6 秒，每秒补充 5 名民兵")
		1:
			marches.boost_faction(PLAYER, 8.0, 1.7)
			hud.notify("疾行战鼓 · 全军行速 +70%，持续 8 秒")
		2:
			shields[target.building_id] = 10.0
			world_effects.shield(target.global_position)
			add_effect(target.global_position, Color(0.45, 0.8, 1.0), "skill", 1.1)
			hud.notify("磐石壁垒 · 守备减伤 50%，持续 10 秒")
	_commit_skill(index)
	var skill_sounds: Array[StringName] = [&"war_skill_command", &"war_skill_drum", &"war_skill_shield"]
	audio.play_world(skill_sounds[index], target.global_position if target != null and index != 1 else camera_rig.global_position)
	if target != null:
		target.refresh_visual()
	update_hud()
	return true

func cast_ground_skill(index: int, at: Vector3) -> bool:
	if index != 3 or not _skill_available(index):
		return false
	if not _valid_ground_skill_target(at):
		hud.notify("请选择战场内的地面 · 右键取消")
		audio.play_ui(&"war_denied")
		return false
	var center := Vector3(at.x, 0.0, at.z)
	world_effects.start_fire(center, IMPACT_RADIUS)
	_commit_skill(index)
	audio.play_world(&"war_skill_breach", center)
	hud.notify("烈焰扩散 · 接触火焰的双方士兵都会死亡")
	update_hud()
	return true

func _commit_skill(index: int) -> void:
	energy -= SKILL_ENERGY_COSTS[index]
	cooldowns[index] = SKILL_COOLDOWNS[index]
	active_durations[index] = SKILL_DURATIONS[index]
	_cancel_skill_drag()
	_cancel_drag()

func _valid_ground_skill_target(at: Vector3) -> bool:
	return at.is_finite() and absf(at.x) <= map.HALF_SIZE.x and absf(at.z) <= map.HALF_SIZE.y

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

func total_for(faction: int) -> int:
	var count: float = marches.total_for(faction)
	for building: Node3D in buildings:
		if building.faction == faction:
			count += building.population
	return floori(count)

func _check_victory() -> void:
	if finished:
		return
	var remaining: Array[bool] = [marches.total_for(PLAYER) > 0, marches.total_for(ENEMY) > 0]
	var can_make_progress: bool = remaining[PLAYER] or remaining[ENEMY]
	for building: Node3D in buildings:
		if building.faction < 0:
			continue
		remaining[building.faction] = true
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
	var detail: String = "住宅产兵 · 炮塔拦截 · 铁匠铺提升全军攻防"
	if selected != null:
		match selected.kind:
			0: detail = "每秒 +%s 民兵 · %d 人停产 · 援军不限 · 守备 +%d%%" % [selected.production_rate, selected.capacity, (selected.level - 1) * 10]
			1: detail = "射程 %d · 每 %.1f 秒拦截 %d 人 · 不自动产兵" % [tower_range(selected), tower_interval(selected), selected.level]
			2: detail = "全军攻击与守备 +%d%% · 不自动产兵" % (selected.level * 10)
		if shields.has(selected.building_id):
			detail += " · 壁垒 %ds" % ceili(shields[selected.building_id])
	hud.update_state({"player_total": total_for(PLAYER), "enemy_total": total_for(ENEMY), "time": elapsed,
		"percentage": percentage, "selected_name": KIND_NAMES[selected.kind] if selected != null else "",
		"send_count": floori(selected.population * percentage / 100.0) if selected != null else 0,
		"selected_population": floori(selected.population) if selected != null else 0, "selected_detail": detail,
		"cooldowns": cooldowns, "skill_durations": active_durations, "armed_skill": armed_skill,
		"energy": energy, "energy_max": ENERGY_MAX, "energy_regen": ENERGY_REGEN, "energy_costs": SKILL_ENERGY_COSTS,
		"skill_target_types": ["building", "self", "building", "ground"], "ground_skill_radius": IMPACT_RADIUS,
		"forges": forge_levels(PLAYER), "selected_owned": selected != null and selected.faction == PLAYER,
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
	return Vector3(clampf(point.x, -34.0, 34.0), 0.0, clampf(point.z, -23.0, 23.0))

func _input(event: InputEvent) -> void:
	if armed_skill >= 0:
		if event is InputEventMouseMotion:
			_update_skill_drag(event.position)
			get_viewport().set_input_as_handled()
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
				get_viewport().set_input_as_handled()
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
	return Color(1.0, 0.65, 0.18) if faction == PLAYER else Color(0.2, 0.83, 0.67)

func add_effect(at: Vector3, color: Color, kind: String, duration: float, radius: float = 3.8) -> void:
	effects.append({"at": at, "color": color, "kind": kind, "life": duration, "duration": duration, "radius": radius})
	if kind in ["capture", "skill", "impact"]:
		world_effects.burst(at, color, kind == "impact")
