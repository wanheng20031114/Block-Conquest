extends "res://scripts/block_war/block_war.gd"
## A guided course around the real battle rules, isolated from match selection.
const LESSONS := preload("res://scripts/tutorial/tutorial_catalog.gd")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
var lesson_id := "basics"
var progress_path := PROGRESS.SAVE_PATH
var lesson_steps: Array[Dictionary] = []
var phase_index := -1
var phase: Dictionary = {}
var practicing := false
var lesson_complete := false
var tutorial_ready := false
var advance_queued := false
var practice_seconds := 0.0
var accepted_action := false
var wave_started := false
var tower_shots := 0
var burned_enemies := 0
var haste_seen := false
var haste_arrived := false
var shield_damage_seen := false
var phase_start_energy := 0.0
var phase_start_zoom := 0.0
var phase_start_camera := Vector3.ZERO
var shield_previous_population := 0.0
var next_hint_at := 18.0
var _aiming_hold := false
@onready var tutor: CanvasLayer = $Tutorial

func _enter_tree() -> void:
	lesson_id = get_node("/root/Session").tutorial_lesson_id
	assert(lesson_id in LESSONS.IDS)
	var original := get_node("Map")
	remove_child(original)
	original.free()
	var authored: Node3D = load("res://scenes/tutorial/maps/%s.tscn" % lesson_id).instantiate()
	authored.name = "Map"
	add_child(authored)
	move_child(authored, 0)
	faction_count = 2
	morale.configure(faction_count)
	for faction: int in faction_count:
		var state := SkillState.new()
		state.commander = &"squirrel"
		# Explicit teaching supplies, independent of competitive starting energy.
		state.energy = 20.0
		faction_skills.append(state)
	ai_enabled = false

func _ready() -> void:
	super._ready()
	camera_rig.edge_scroll = false
	camera_rig.focus_at(Vector3(0, 0, 1), true)
	camera.size = 45.0
	camera_rig.zoom_target = camera.size
	camera_rig.clamp_destination()
	hud.get_node("%Toast").hide()
	hud.get_node("%PauseRestart").text = "重新练习本课"
	hud.get_node("%PauseExit").text = "返回课程列表"
	hud.get_node("%Resume").text = "继续教程"
	hud.get_node("%PauseCard/Title").text = "练习已暂停"
	hud.get_node("%PauseCard/Sub").text = "继续时仍会保留当前讲解与练习进度。"
	presentation_event.connect(_record_event)
	marches.unit_arrived.connect(_record_arrival)
	tutor.continue_requested.connect(_continue)
	tutor.replay_requested.connect(_replay)
	tutor.retry_requested.connect(restart)
	tutor.exit_requested.connect(exit_to_lobby)
	tutor.next_requested.connect(_next_lesson)
	lesson_steps = LESSONS.steps(lesson_id)
	if lesson_id in ["recruit", "drum", "shield", "fire"]:
		energy = SKILL_RULES.COSTS[["recruit", "drum", "shield", "fire"].find(lesson_id)] + 5.0
	if lesson_id == "morale": morale.adjust(0, 440.0)
	if lesson_id == "fire":
		# The authored lesson opens on an already approaching enemy column.
		issue_order(by_id[2], by_id[1], 100, 1)
		simulate(2.1)
	tutorial_ready = true
	_next_phase()

func _check_victory() -> void:
	# Course objectives own completion; empty opposing seats are intentional.
	pass

func _process(delta: float) -> void:
	_aiming_hold = tutorial_ready and practicing and not accepted_action and (phase.action in ["cast_building", "cast_ground", "fire_hit"] or (lesson_id == "morale" and phase.action == "capture"))
	super._process(delta)
	if not tutorial_ready or _closing: return
	if practicing and not is_rule_paused() and not lesson_complete:
		practice_seconds += delta
		_observe_practice()
		if _objective_met():
			_queue_advance()
		elif practice_seconds >= next_hint_at:
			next_hint_at += 18.0
			tutor.show_hint(_practice_hint())
	_update_guidance()

func simulate(delta: float) -> void:
	# First-time aiming has no time pressure. Input still uses the real skill
	# validation, but troops wait until a valid placement commits the skill.
	if _aiming_hold: return
	super.simulate(delta)

func _next_phase() -> void:
	advance_queued = false
	phase_index += 1
	if phase_index >= lesson_steps.size():
		_complete_lesson()
		return
	phase = lesson_steps[phase_index]
	practicing = false
	practice_seconds = 0.0
	accepted_action = false
	next_hint_at = 18.0
	select_building(by_id[0] if phase.focus in ["upgrade", "selection"] else null)
	_set_teaching_pause(true)
	tutor.set_objective("%02d / %02d  ·  %s" % [LESSONS.IDS.find(lesson_id) + 1, LESSONS.IDS.size(), LESSONS.title(lesson_id)], phase.goal, "跟随讲解，然后亲自试一次。" if phase.action != "read" else "战场已暂停，可以安心阅读。", "%d / %d" % [phase_index + 1, lesson_steps.size()])
	tutor.show_instruction(phase.title, phase.body, "明白，继续" if phase.action == "read" else "开始练习")
	_update_guidance()

func _queue_advance() -> void:
	if advance_queued: return
	advance_queued = true
	_set_teaching_pause(true)
	_next_phase.call_deferred()

func _continue() -> void:
	if _closing or lesson_complete or advance_queued: return
	if phase.action == "read":
		_queue_advance()
		return
	if not practicing:
		phase_start_energy = energy
		phase_start_zoom = camera.size
		phase_start_camera = camera_rig.position
	practicing = true
	tutor.dismiss_instruction()
	_set_teaching_pause(false)
	if phase.action == "shield_defense" and not wave_started:
		wave_started = true
		shield_previous_population = by_id[1].population
		issue_order(by_id[2], by_id[1], 100, 1)
	tutor.set_objective("%02d / %02d  ·  %s" % [LESSONS.IDS.find(lesson_id) + 1, LESSONS.IDS.size(), LESSONS.title(lesson_id)], phase.goal, "练习瞄准时部队会等待，放准后才继续。" if phase.action in ["cast_building", "cast_ground", "fire_hit"] else "需要帮助时点「再看讲解」。拖错可按右键取消。", "%d / %d" % [phase_index + 1, lesson_steps.size()])

func _replay() -> void:
	if lesson_complete or _closing or advance_queued: return
	_set_teaching_pause(true)
	if phase.action not in ["zoom", "pan"]:
		# Restore a useful teaching view if a new player has panned away.
		camera.size = 45.0
		camera_rig.zoom_target = camera.size
		camera_rig.focus_at(Vector3(0, 0, 1), true)
	tutor.show_instruction(phase.title, phase.body, "继续练习" if practicing else ("明白，继续" if phase.action == "read" else "开始练习"))

func _set_teaching_pause(value: bool) -> void:
	simulation_paused = value
	camera_rig.set_process(not value and not _local_menu)
	_cancel_drag()
	_cancel_skill_drag()
	camera_rig.dragging = false
	hud.set_process_unhandled_key_input(not value or _local_menu)
	sync_match_control_presentation()

func set_paused(value: bool) -> void:
	super.set_paused(value)
	if not tutorial_ready: return
	tutor.visible = not value
	hud.set_process_unhandled_key_input(value or not simulation_paused)
	camera_rig.set_process(not value and not simulation_paused)

func _input(event: InputEvent) -> void:
	if not tutorial_ready: return
	if simulation_paused and not _local_menu:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("pause")):
			set_paused(true)
			get_viewport().set_input_as_handled()
		return
	super._input(event)

func _unhandled_input(event: InputEvent) -> void:
	if simulation_paused: return
	super._unhandled_input(event)

func request_skill(index: int, from_keyboard: bool = false) -> void:
	if not tutorial_ready or not practicing or simulation_paused or int(phase.get("skill", -1)) != index:
		if tutorial_ready: tutor.show_hint("先完成左上角的目标；技能会在对应课程中逐个练习。")
		return
	super.request_skill(index, from_keyboard)

func submit_player_command(command: Dictionary) -> Dictionary:
	if not practicing or simulation_paused or lesson_complete or _closing:
		return {"accepted": false, "reason": "tutorial_paused"}
	var kind := str(command.get("type", ""))
	var allowed := false
	match phase.action:
		"capture", "dispatch", "reinforce_tower":
			allowed = kind == "dispatch" and command.get("source") == phase.source and command.get("target") == phase.target
		"upgrade":
			allowed = kind == "upgrade" and command.get("building") == phase.target
		"cast_building":
			allowed = kind == "skill_building" and command.get("skill") == phase.skill and command.get("target") == phase.target
		"cast_ground", "fire_hit":
			if kind == "skill_ground" and command.get("skill") == phase.skill:
				var aim := Vector3(float(command.x), 0, float(command.z))
				var centre := _army_center(int(phase.army))
				allowed = Vector2(aim.x, aim.z).distance_to(Vector2(centre.x, centre.z)) < skill_radius(int(phase.skill)) * 0.9
	if not allowed:
		tutor.show_hint("这一步请先完成：" + str(phase.goal) + "。跟随示范，再试一次。")
		return {"accepted": false, "reason": "tutorial_objective"}
	var result := super.submit_player_command(command)
	if result.accepted:
		accepted_action = true
		if phase.action == "reinforce_tower" and not wave_started:
			wave_started = true
			issue_order(by_id[2], by_id[1], 100, 1)
	return result

func _record_event(kind: String, payload: Dictionary) -> void:
	if kind == "tower_shot" and payload.faction == 0: tower_shots += 1
	if kind == "casualty" and payload.faction == 1 and payload.burning: burned_enemies += 1

func _record_arrival(target: int, faction: int, _strength: float, _bonus: float, _energy_origin: bool) -> void:
	if faction == 0 and target == 1 and haste_seen: haste_arrived = true

func _observe_practice() -> void:
	if lesson_id == "drum":
		for unit: WarMarches.MarchUnit in marches._units:
			if unit.order.faction == 0 and unit.is_exposed() and marches.speed_multiplier(unit) > morale.speed(0) + 0.1:
				haste_seen = true
	if phase.action == "shield_defense":
		if shields.has(1) and by_id[1].population < shield_previous_population:
			shield_damage_seen = true
		shield_previous_population = by_id[1].population

func _objective_met() -> bool:
	match phase.action:
		"capture": return accepted_action and by_id[int(phase.target)].faction == 0 and (lesson_id != "morale" or morale.level(0) >= 1)
		"ratio": return percentage == 25
		"zoom": return absf(camera.size - phase_start_zoom) >= 0.8
		"pan": return camera_rig.position.distance_to(phase_start_camera) >= 1.0 and not camera_rig.dragging
		"upgrade": return accepted_action and by_id[0].level >= 2 and not by_id[0].is_constructing
		"dispatch": return accepted_action and _army_exposed(0) >= 6
		"reinforce_tower", "cast_building": return accepted_action
		"tower_defense": return tower_shots > 0 and wave_started and marches.total_for(1) == 0 and by_id[1].faction == 0
		"energy_watch": return energy >= minf(ENERGY_MAX, phase_start_energy + 5.0)
		"recruit_watch": return by_id[0].population >= 46.0
		"cast_ground": return accepted_action and haste_seen
		"haste_arrival": return haste_seen and haste_arrived
		"shield_defense": return shield_damage_seen and wave_started and marches.total_for(1) == 0 and by_id[1].faction == 0
		"fire_hit": return accepted_action and burned_enemies >= 3
	return false

func _army_exposed(faction: int) -> int:
	var count := 0
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.faction == faction and unit.is_exposed(): count += 1
	return count

func _army_center(faction: int) -> Vector3:
	var centre := Vector3.ZERO
	var count := 0
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.faction == faction and unit.is_exposed():
			centre += unit.position
			count += 1
	return centre / count if count > 0 else by_id[1].global_position

func _practice_hint() -> String:
	if phase.action in ["shield_defense", "tower_defense", "fire_hit", "haste_arrival"] and marches.total_for(1 if lesson_id != "drum" else 0) == 0:
		return "点「重练」即可立即重来，不必等待技能冷却。"
	if phase.action == "upgrade": return "先点住宅，再点建筑旁的升级按钮。施工需要 10 秒；驻军不足时住宅会继续生产。"
	if phase.action in ["cast_ground", "fire_hit"]: return "把技能拖向动画指向的队伍；放错位置可右键取消。"
	return "跟随动画完成左上角目标；点「再看讲解」可暂停复习。"

func _world_rect(at: Vector3, radius: float = 3.8) -> Rect2:
	var result := Rect2(camera.unproject_position(at), Vector2.ZERO)
	for x: float in [-radius, radius]:
		for y: float in [0.0, 5.0]:
			for z: float in [-radius, radius]:
				result = result.expand(camera.unproject_position(at + Vector3(x, y, z)))
	return result.grow(10.0)

func _ui_rect(path: String) -> Rect2:
	return (hud.get_node(path) as Control).get_global_rect().grow(8.0)

func _update_guidance() -> void:
	if phase.is_empty() or lesson_complete or _local_menu: return
	var rectangles: Array[Rect2] = []
	var focus := str(phase.focus)
	if focus.begins_with("building:"):
		rectangles.append(_world_rect(by_id[int(focus.get_slice(":", 1))].global_position))
	elif focus.begins_with("army:"):
		rectangles.append(_world_rect(_army_center(int(focus.get_slice(":", 1))), 4.8))
	elif focus.begins_with("skill:"):
		rectangles.append(_ui_rect("UI/Skills/Row/Skill" + focus.get_slice(":", 1)))
		rectangles.append(_world_rect(_aim_position(), 4.4))
	else:
		match focus:
			"buildings":
				rectangles.append(_world_rect(by_id[0].global_position))
				rectangles.append(_world_rect(by_id[1].global_position))
			"top": rectangles.append(_ui_rect("UI/Top"))
			"morale": rectangles.append(_ui_rect("UI/Top/Balance"))
			"skills": rectangles.append(_ui_rect("UI/Skills"))
			"ratios": rectangles.append(_ui_rect("UI/Percentages"))
			"selection", "upgrade":
				rectangles.append(_world_rect(by_id[0].global_position))
				rectangles.append(_ui_rect("UI/Selection/BuildingActions"))
			"energy":
				rectangles.append(_world_rect(by_id[1].global_position))
				rectangles.append(_ui_rect("UI/Skills"))
	tutor.set_spotlights(rectangles)
	match phase.action:
		"capture", "dispatch", "reinforce_tower":
			tutor.set_gesture(camera.unproject_position(by_id[int(phase.source)].global_position + Vector3.UP * 1.6), camera.unproject_position(by_id[int(phase.target)].global_position + Vector3.UP * 1.6), "drag")
		"cast_building", "cast_ground", "fire_hit":
			tutor.set_gesture(_ui_rect("UI/Skills/Row/Skill%d" % int(phase.skill)).get_center(), camera.unproject_position(_aim_position()), "drag")
		"upgrade":
			var at := _ui_rect("UI/Selection/BuildingActions/Upgrade").get_center()
			tutor.set_gesture(at, at, "click")
		"ratio":
			var at := _ui_rect("UI/Percentages/Stack/P25").get_center()
			tutor.set_gesture(at, at, "click")
		"zoom":
			var at := get_viewport().get_visible_rect().size * Vector2(0.6, 0.55)
			tutor.set_gesture(at, at, "scroll")
		"pan":
			var at := get_viewport().get_visible_rect().size * Vector2(0.6, 0.55)
			tutor.set_gesture(at, at + Vector2(100, -45), "pan")
		_: tutor.clear_gesture()

func _aim_position() -> Vector3:
	if phase.has("army"): return _army_center(int(phase.army))
	return by_id[int(phase.get("target", 0))].global_position + Vector3.UP * 1.5

func _complete_lesson() -> void:
	lesson_complete = true
	practicing = false
	_set_teaching_pause(true)
	tutor.clear_gesture()
	var saved := PROGRESS.mark_completed(lesson_id, progress_path)
	var has_next := LESSONS.IDS.find(lesson_id) + 1 < LESSONS.IDS.size()
	var body := LESSONS.summary(lesson_id) + ("\n这一关可以随时重玩，下一关也已经准备好了。" if has_next else "\n基础练习已经完成。回到主菜单，试试自己的第一场单人对局吧。")
	if saved != OK: body += "\n本次通关已完成，但进度暂时无法写入磁盘。"
	tutor.set_objective(LESSONS.title(lesson_id), "本课目标已完成", "已完成实际操作，可以继续下一课或随时重玩。", "%d / %d" % [lesson_steps.size(), lesson_steps.size()])
	tutor.show_completion("完成 · " + LESSONS.title(lesson_id), body, has_next)

func restart() -> void:
	if _closing: return
	await prepare_shutdown()
	get_node("/root/Session").start_tutorial(lesson_id)

func exit_to_lobby() -> void:
	if _closing: return
	await prepare_shutdown()
	get_node("/root/Session").start_tutorial()

func _next_lesson() -> void:
	if _closing or not lesson_complete: return
	var next := LESSONS.IDS.find(lesson_id) + 1
	await prepare_shutdown()
	get_node("/root/Session").start_tutorial(LESSONS.IDS[next] if next < LESSONS.IDS.size() else "")
