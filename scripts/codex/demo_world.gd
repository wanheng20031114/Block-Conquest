extends "res://scripts/block_war/block_war.gd"
## An isolated training fixture around the real simulation, not a second set
## of skill rules. Session, network, window lifecycle and player input stay out.

signal cycle_completed

const CYCLE_SECONDS := 10.5
var demo_commander: StringName = &"squirrel"
var demo_skill := 0
var bear_hostile := false
var frog_siege := false
var pig_hostile := false
var cast_succeeded := false
var cast_count := 0
var dispatched := false
var followup_dispatched := false
var cast_at := 1.8
var dispatch_at := 0.5
var _cycle_done := false
var home: WarBuilding
var away: WarBuilding
var caption := "准备施放"
var before_population := 0.0
var after_population := 0.0

func _enter_tree() -> void:
	faction_count = 2
	morale.configure(faction_count)
	for faction: int in faction_count:
		var state := SkillState.new()
		state.commander = demo_commander if faction == 0 else &"squirrel"
		state.energy = ENERGY_MAX
		faction_skills.append(state)
	ai_enabled = false

func _ready() -> void:
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	home = $Map/Buildings/Home
	away = $Map/Buildings/Away
	var single := (demo_commander == &"squirrel" and demo_skill == 0) or (demo_commander == &"bear" and demo_skill == 0)
	var support := demo_commander == &"bear" and demo_skill == 2
	var refuge := demo_commander == &"fox" and demo_skill == 3
	away.visible = not single
	$Map/Buildings/Support.visible = support
	$Map/Buildings/Refuge.visible = refuge
	for building: WarBuilding in $Map/Buildings.get_children():
		building.set_process(building.visible)
		if not building.visible:
			continue
		building.viewer_faction = 0
		buildings.append(building)
		by_id[building.building_id] = building
		tower_clocks[building.building_id] = 0.0
		building.construction_completed.connect(_on_building_completed.bind(building))
	morale.changed.connect(_on_morale_changed)
	marches.unit_arrived.connect(_on_unit_arrived)
	marches.combat_death.connect(_on_march_combat_death)
	marches.departure_queue_changed.connect(_on_departure_queue_changed)
	marches.unit_departed.connect(_on_unit_departed)
	marches.unit_defeated.connect(_on_unit_defeated)
	marches.map_definition = map.definition
	world_effects.configure_surface(map.definition)
	_match_ready = true
	if single:
		camera_rig.position = Vector3(-9, 0, 0)
	elif support or refuge:
		camera_rig.position.z = -5.5
	_setup_example()
	for building: WarBuilding in buildings:
		building.refresh_visual()
	sync_environment_bonuses()
	before_population = away.population

func _setup_example() -> void:
	caption = "己方位于左侧，敌方位于右侧。"
	if demo_commander == &"squirrel":
		if demo_skill == 0:
			home.population = 10.0
			cast_at = 1.0
			caption = "向己方住宅施放征召军令。"
		elif demo_skill == 2:
			cast_at = 1.1
			caption = "敌军接近，为己方住宅提供防护。"
	elif demo_commander == &"rabbit":
		if demo_skill == 1:
			away.kind = 1
			away.level = 2
			cast_at = 1.3
			caption = "干扰敌方炮塔，暂停射击。"
		elif demo_skill == 2:
			cast_at = 2.3
		elif demo_skill == 3:
			dispatch_at = 1.6
			cast_at = 0.8
			home.population = 42.0
	elif demo_commander == &"bear":
		if demo_skill == 0:
			home.population = 20.0
			cast_at = 1.2
			caption = "把工具箱拖到己方住宅，直接升 1 级。"
		elif demo_skill == 1:
			away.population = 100.0
			home.population = 80.0
			cast_at = 0.9
			caption = "敌军开始出门，封住出兵建筑。"
		elif demo_skill == 2:
			cast_at = 1.3
		elif demo_skill == 3:
			away.population = 120.0
			cast_at = 1.3
			caption = "对敌方建筑施放：削弱防御，火球攻击敌军。" if bear_hostile else "对友方建筑施放：提高防御，火球拦截敌军。"
	elif demo_commander == &"frog":
		if demo_skill == 0:
			if frog_siege:
				away.population = 16.0
				cast_at = 5.7
				caption = "部队接近敌方住宅，雾气削弱建筑防御。"
			else:
				home.kind = 1
				cast_at = 1.3
		elif demo_skill == 1:
			cast_at = 2.3
		elif demo_skill == 2:
			away.kind = 1
			# Select the whole visible column, after its last row leaves the gate.
			cast_at = 2.2
		else:
			away.level = 3
			away.population = 100.0
			cast_at = 1.1
	elif demo_commander == &"fox":
		if demo_skill != 2:
			cast_at = 1.2
			away.population = 80.0
		if demo_skill == 1:
			morale.adjust(1, 1000.0)
	elif demo_commander == &"pig" and demo_skill < 2:
		cast_at = 0.8
		dispatch_at = 1.6
		home.population = 80.0 if demo_skill == 1 else 48.0
	elif demo_commander == &"pig" and demo_skill == 2:
		cast_at = 1.2
		away.population = 20.0
		camera_rig.position.y = 3.0
		caption = "选择建筑，2 秒内空投 40 名己方士兵。"

func _process(delta: float) -> void:
	if simulation_paused or _cycle_done:
		return
	# Stop exactly at demonstration decisions, then let the real battle engine
	# handle production, arrival, collisions, durations and native effect timing.
	var remaining := delta
	while remaining > 0.000001:
		if not dispatched and elapsed >= dispatch_at - 0.000001:
			dispatched = true
			_dispatch_example()
		if cast_count == 0 and elapsed >= cast_at - 0.000001:
			_cast_example()
		# Cancellation never resumes the old queue. Show a second, new order
		# only after the entire lock expires, using the same ordinary command.
		var next_order_at: float = cast_at + SKILL_RULES.BEAR_DURATIONS[1] + 0.6
		if demo_commander == &"bear" and demo_skill == 1 and not followup_dispatched and elapsed >= next_order_at - 0.000001:
			followup_dispatched = true
			assert(issue_order(away, home, 50, 1) > 0)
			caption = "封锁结束，重新下令后才会继续出兵。"
		var step := remaining
		if not dispatched:
			step = minf(step, maxf(0.000001, dispatch_at - elapsed))
		if cast_count == 0:
			step = minf(step, maxf(0.000001, cast_at - elapsed))
		if demo_commander == &"bear" and demo_skill == 1 and not followup_dispatched:
			step = minf(step, maxf(0.000001, next_order_at - elapsed))
		simulate(step)
		remaining -= step
	if elapsed >= CYCLE_SECONDS:
		_cycle_done = true
		cycle_completed.emit()

func _dispatch_example() -> void:
	var own_attack := (demo_commander == &"squirrel" and demo_skill == 1) or (demo_commander == &"rabbit" and demo_skill in [0, 1, 2, 3]) or (demo_commander == &"frog" and (demo_skill in [1, 2] or (demo_skill == 0 and frog_siege))) or (demo_commander == &"pig" and demo_skill < 2)
	var enemy_attack := (demo_commander == &"squirrel" and demo_skill in [2, 3]) or (demo_commander == &"rabbit" and demo_skill == 2) or (demo_commander == &"bear" and demo_skill > 0) or (demo_commander == &"frog" and (demo_skill == 1 or (demo_skill == 0 and not frog_siege))) or (demo_commander == &"fox" and demo_skill == 2) or (demo_commander == &"pig" and demo_skill == 3)
	if own_attack:
		var sent := issue_order(home, away, 100 if demo_commander == &"pig" else 50, 0)
		assert(sent > 0)
	if enemy_attack:
		var sent := issue_order(away, home, 50, 1)
		assert(sent > 0)

func _army_center(faction: int) -> Vector3:
	var at := Vector3.ZERO
	var count := 0
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.faction == faction and unit.is_exposed():
			at += unit.position
			count += 1
	assert(count > 0, "The scheduled skill requires real exposed soldiers.")
	return at / maxf(1, count)

func _cast_example() -> void:
	cast_count += 1
	if skill_is_ground(demo_skill, 0):
		var friendly := (demo_commander == &"squirrel" and demo_skill == 1) or (demo_commander == &"rabbit" and demo_skill == 0) or (demo_commander == &"frog" and (demo_skill == 2 or (demo_skill == 0 and frog_siege)))
		var center := _army_center(0 if friendly else 1)
		if demo_commander == &"frog" and demo_skill == 0 and frog_siege:
			center = away.global_position
		if (demo_commander == &"rabbit" and demo_skill == 2) or (demo_commander == &"frog" and demo_skill == 1):
			center = (_army_center(0) + _army_center(1)) * 0.5
		cast_succeeded = cast_ground_skill(demo_skill, center, 0)
	else:
		var enemy_target := demo_commander in [&"frog", &"fox"] or (demo_commander == &"rabbit" and demo_skill == 1) or (demo_commander == &"bear" and (demo_skill == 1 or (demo_skill == 3 and bear_hostile))) or (demo_commander == &"pig" and demo_skill == 2 and pig_hostile)
		cast_succeeded = cast_skill(demo_skill, away if enemy_target else home, 0)
	after_population = away.population
	assert(cast_succeeded, "Every codex example must pass the actual skill target and energy rules.")
	caption = _outcome_caption()

func _outcome_caption() -> String:
	match demo_commander:
		&"squirrel": return ["持续征召，住宅驻军增加。", "己军移速 +%d%%，离圈后延续 %d 秒。" % [roundi((SKILL_RULES.HASTE_MULTIPLIER - 1.0) * 100.0), SKILL_RULES.HASTE_LINGER], "建筑防御力 +%d%%，持续 %d 秒。" % [roundi(SKILL_RULES.SHIELD_DEFENSE * 100.0), SKILL_RULES.DURATIONS[2]], "火焰消灭接触的敌我行军部队，并伤害敌方驻军。"][demo_skill]
		&"rabbit": return ["攻击力 +%d%%，移速 +%d%%，持续 %d 秒。" % [roundi(SKILL_RULES.RABBIT_RUSH_ATTACK_BONUS * 100.0), roundi((SKILL_RULES.RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), SKILL_RULES.RABBIT_DURATIONS[0]], "敌方炮塔停止射击，停工结束后恢复。", "范围内双方行军返回各自出发建筑。", "兔洞派兵攻击力 +%d%%，持续至进入建筑。" % roundi(SKILL_RULES.BURROW_ATTACK_BONUS * 100.0)][demo_skill]
		&"bear":
			if demo_skill == 3 and bear_hostile:
				return "敌方防御 -%d%%，无护罩；火球每 %.2f 秒攻击敌军。" % [roundi(absf(SKILL_RULES.BEAR_CURSE_DEFENSE) * 100.0), SKILL_RULES.BEAR_HOSTILE_ORB_INTERVAL]
			return ["立即升 1 级，驻军不消耗。", "出兵任务已取消，未出门士兵留守 %d 秒。" % SKILL_RULES.BEAR_DURATIONS[1], "双方防御力 +%d%%，支援方分担一半伤害。" % roundi(SKILL_RULES.BEAR_LINK_DEFENSE * 100.0), "友方防御 +%d%%并获得护罩；火球每 %.1f 秒攻击敌军。" % [roundi(SKILL_RULES.BEAR_WARD_DEFENSE * 100.0), SKILL_RULES.BEAR_ORB_INTERVAL]][demo_skill]
		&"frog":
			if demo_skill == 0 and frog_siege:
				return "雾内敌方建筑防御力 -%d%%；雾散后恢复。" % roundi(-SKILL_RULES.FROG_BUILDING_DEFENSE * 100.0)
			return ["敌军攻击力 -%d%%，持续至进入建筑；炮塔无法攻击雾内士兵。" % roundi(SKILL_RULES.FROG_WEAKNESS * 100.0), "选中的双方士兵滞空，落地后继续行军。", "己方士兵完全隐身，避开炮塔攻击直至进入建筑。", "敌方驻军减少 %d%%，建筑降至 1 级。" % roundi(SKILL_RULES.FROG_STRIKE_FRACTION * 100.0)][demo_skill]
		&"fox": return ["炸弹削减敌方驻军。", "敌方士气转移至己方，双方星级随之变化。", "选中的敌军归属转为己方，沿原路线行军。", "敌方驻军离开据点，前往同阵营避难建筑。"][demo_skill]
		&"pig": return ["最多 %d 人，攻击力 +%d%%、移速 +%d%%，持续至入城。" % [SKILL_RULES.PIG_CHARGE_LIMIT, roundi(SKILL_RULES.PIG_CHARGE_ATTACK_BONUS * 100.0), roundi(SKILL_RULES.PIG_CHARGE_SPEED_BONUS * 100.0)], "下次派兵直线飞行，最多 %d 人。" % SKILL_RULES.PIG_FLIGHT_LIMIT, "选择建筑，%d 秒内空投 %d 名己方士兵。" % [SKILL_RULES.PIG_AIRLIFT_DURATION, SKILL_RULES.PIG_AIRLIFT_COUNT], "范围内敌我行军部队全部死亡，建筑驻军减少 50%。"][demo_skill]
	return ""

func fit_camera(aspect: float) -> void:
	# Camera3D KEEP_HEIGHT measures orthographic size vertically.
	# https://docs.godotengine.org/en/stable/classes/class_camera3d.html
	var single := buildings.size() == 1
	var width := 12.0 if single else 26.0
	var min_height := 17.0 if buildings.size() > 2 else 13.0
	if demo_commander == &"pig" and demo_skill == 2:
		# Include the complete descent and wind trails above either destination.
		min_height = 15.0
	camera.size = maxf(min_height, width / aspect)

func set_running(value: bool) -> void:
	simulation_paused = not value
	world_effects.set_running(value)
	for building: WarBuilding in buildings:
		building.set_visual_paused(not value)
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED

func _check_victory() -> void:
	pass

func update_hud() -> void:
	pass

func _exit_tree() -> void:
	pass

func _notification(_what: int) -> void:
	pass

func _input(_event: InputEvent) -> void:
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass
