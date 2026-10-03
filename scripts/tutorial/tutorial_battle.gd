extends "res://scripts/block_war/block_war.gd"
## A guided course around the real battle rules, isolated from match selection.
const LESSONS := preload("res://scripts/tutorial/tutorial_catalog.gd")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
const DIRECT_ACTIONS := ["capture", "dispatch", "reinforce_tower", "upgrade", "cast_building", "cast_ground", "fire_hit", "ratio", "zoom", "pan"]
const RESULT_HOLD := 0.75
const OBSERVED_ACTIONS := ["capture", "reinforce_tower", "upgrade", "cast_building", "cast_ground", "fire_hit"]
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
var recruit_result_population := 0.0
var result_ready_at := -1.0
var observation_hint := ""
var next_hint_at := 18.0
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
		faction_skills.append(state)
	ai_enabled = false

func _ready() -> void:
	super._ready()
	camera_rig.edge_scroll = false
	camera_rig.focus_at(Vector3(0, 0, 1), true)
	camera.size = 45.0
	camera_rig.zoom_target = camera.size
	camera_rig.clamp_destination()
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
	super._process(delta)
	if not tutorial_ready or _closing: return
	# Camera practice is judged by the rendered view, not by an attempted wheel
	# tick at a map boundary. The battle remains frozen until it actually moves.
	if simulation_paused and _can_direct_interact() and phase.action in ["zoom", "pan"] and _objective_met():
		accepted_action = true
		_continue()
	if practicing and not is_rule_paused() and not lesson_complete:
		practice_seconds += delta
		if _objective_met():
			if result_ready_at < 0.0: result_ready_at = elapsed
			if _result_visible_long_enough(): _queue_advance()
		else:
			result_ready_at = -1.0
		var hint := _observation_hint()
		if not hint.is_empty() and hint != observation_hint:
			observation_hint = hint
			tutor.show_hint(hint)
		elif not accepted_action and practice_seconds >= next_hint_at:
			next_hint_at += 18.0
			tutor.show_hint(_practice_hint())
	_update_guidance()

func simulate(delta: float) -> void:
	if not tutorial_ready or phase.action != "dispatch" or not accepted_action:
		super.simulate(delta)
		return
	# Stop this demonstration at its aiming opportunity, even if a slow frame
	# would otherwise carry the whole column into the destination building.
	var remaining := delta
	while remaining > 0.0 and not is_rule_paused():
		var step := minf(remaining, 0.05)
		super.simulate(step)
		if _army_exposed(0) >= 6: return
		remaining = maxf(0.0, remaining - step)

func _simulate_step(delta: float) -> void:
	# Observe the authoritative substeps, including frames that span an entire
	# skill. A frame-end sample can miss every accelerated soldier.
	_observe_practice()
	super._simulate_step(delta)
	_observe_practice()

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
	result_ready_at = -1.0
	observation_hint = ""
	next_hint_at = 18.0
	phase_start_energy = energy
	phase_start_zoom = camera.size
	phase_start_camera = camera_rig.position
	select_building(by_id[0] if phase.focus in ["upgrade", "selection"] else null)
	_set_teaching_pause(true)
	tutor.set_objective("%02d / %02d  ·  %s" % [LESSONS.IDS.find(lesson_id) + 1, LESSONS.IDS.size(), LESSONS.title(lesson_id)], phase.goal, "%d / %d" % [phase_index + 1, lesson_steps.size()])
	tutor.show_instruction(phase.title, phase.body, "继续" if phase.action == "read" else "开始观察", _is_direct_action())
	_update_guidance()

func _queue_advance() -> void:
	if advance_queued: return
	advance_queued = true
	_set_teaching_pause(true)
	_next_phase.call_deferred()

func _continue() -> void:
	if _closing or lesson_complete or advance_queued or _local_menu: return
	if phase.action == "read":
		_queue_advance()
		return
	practicing = true
	tutor.dismiss_instruction()
	_set_teaching_pause(false)
	var goal := str(phase.get("watch_goal", phase.goal)) if accepted_action else str(phase.goal)
	if accepted_action and phase.action == "capture": goal = "观察占领与部队入驻"
	if accepted_action and phase.action == "upgrade": goal = "观察住宅升级完成"
	tutor.set_objective("%02d / %02d  ·  %s" % [LESSONS.IDS.find(lesson_id) + 1, LESSONS.IDS.size(), LESSONS.title(lesson_id)], goal, "%d / %d" % [phase_index + 1, lesson_steps.size()])
	_update_guidance()

func _replay() -> void:
	if lesson_complete or _closing or advance_queued: return
	_set_teaching_pause(true)
	if phase.action not in ["zoom", "pan"]:
		# Restore a useful teaching view if a new player has panned away.
		camera.size = 45.0
		camera_rig.zoom_target = camera.size
		camera_rig.focus_at(Vector3(0, 0, 1), true)
	tutor.show_instruction(phase.title, phase.body, "继续" if phase.action == "read" else "继续观察", _is_direct_action() and not accepted_action)
	_update_guidance()

func _is_direct_action() -> bool:
	return phase.get("action", "") in DIRECT_ACTIONS

func _can_direct_interact() -> bool:
	if not tutorial_ready or _closing or lesson_complete or advance_queued or _local_menu:
		return false
	if get_node("/root/Session/Settings").is_open(): return false
	return (practicing and not simulation_paused) or (_is_direct_action() and not accepted_action)

func _can_issue_lesson_action() -> bool:
	if not _can_direct_interact(): return false
	if not accepted_action: return true
	# Observe one committed action. A failed capture can be reinforced once its
	# first column has resolved; other actions cannot be repeated mid-effect.
	return phase.action == "capture" and by_id[int(phase.target)].faction != local_faction and marches.incoming_for(int(phase.target), local_faction) == 0

func _sync_teaching_input() -> void:
	var direct := _can_direct_interact()
	hud.set_process_unhandled_key_input(_local_menu or not simulation_paused or direct)
	camera_rig.set_process(not _local_menu and (not simulation_paused or (direct and phase.action in ["zoom", "pan"])))
	camera_rig.keyboard_pan = not simulation_paused or (direct and phase.action == "pan")

func _set_teaching_pause(value: bool) -> void:
	simulation_paused = value
	if value:
		# A previous view gesture must not drift into the next camera objective.
		camera_rig.destination = camera_rig.position
		camera_rig.zoom_target = camera.size
	_cancel_drag()
	_cancel_skill_drag()
	camera_rig.dragging = false
	_sync_teaching_input()
	sync_match_control_presentation()

func set_paused(value: bool) -> void:
	super.set_paused(value)
	if not tutorial_ready: return
	tutor.visible = not value
	_sync_teaching_input()

func _input(event: InputEvent) -> void:
	if not tutorial_ready: return
	if get_node("/root/Session/Settings").is_open(): return
	if simulation_paused and not _local_menu:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed("pause")):
			set_paused(true)
			get_viewport().set_input_as_handled()
			return
		if not _can_direct_interact(): return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and drag_source != null:
		# Cancellation also works outside the spotlight; the dimmer would
		# otherwise consume this before the normal unhandled-input callback.
		audio.play_ui(&"war_cancel")
		_cancel_drag()
		update_hud()
		get_viewport().set_input_as_handled()
		return
	# _input precedes GUI picking. A release over a tutorial card must never
	# dispatch to a building behind it, even when the drag began in a cutout.
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _pointer_over_tutorial(event.position):
		_cancel_drag()
		_cancel_skill_drag()
		update_hud()
	super._input(event)

func _pointer_over_tutorial(screen: Vector2) -> bool:
	for panel: Control in [tutor.instruction, tutor.objective, tutor.hint]:
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(screen): return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if simulation_paused:
		if not _can_direct_interact(): return
		if not event is InputEventMouseButton or not event.pressed: return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if phase.action not in ["capture", "dispatch", "reinforce_tower", "upgrade"]: return
			MOUSE_BUTTON_MIDDLE:
				if phase.action != "pan": return
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if phase.action != "zoom" and drag_source == null: return
			MOUSE_BUTTON_RIGHT: pass
			_: return
	super._unhandled_input(event)

func request_skill(index: int, from_keyboard: bool = false) -> void:
	if not _can_issue_lesson_action() or int(phase.get("skill", -1)) != index:
		return
	# The native skill validator shares the simulation pause gate. Open it only
	# for this synchronous preview request; no world frame can run in between.
	var teaching_pause := simulation_paused
	simulation_paused = false
	super.request_skill(index, from_keyboard)
	simulation_paused = teaching_pause

func can_cast_skill(index: int, faction: int = -2) -> bool:
	if not simulation_paused:
		return super.can_cast_skill(index, faction)
	var preview_faction := local_faction if faction == -2 else faction
	if not _can_direct_interact() or preview_faction != local_faction or int(phase.get("skill", -1)) != index:
		return false
	# Ground previews query this read-only availability method while the lesson
	# is frozen. Reuse native resource/cooldown rules without opening execution.
	simulation_paused = false
	var available := super.can_cast_skill(index, faction)
	simulation_paused = true
	return available

func release_skill_drag(screen: Vector2) -> void:
	if _pointer_over_tutorial(screen):
		_cancel_skill_drag()
		update_hud()
		return
	super.release_skill_drag(screen)

func set_percentage(value: int) -> void:
	if not tutorial_ready:
		super.set_percentage(value)
		return
	if not _can_direct_interact(): return
	if simulation_paused and phase.action != "ratio" and drag_source == null: return
	super.set_percentage(value)
	if phase.action == "ratio" and percentage == 25:
		accepted_action = true
		_continue()

func submit_player_command(command: Dictionary) -> Dictionary:
	if not _can_issue_lesson_action():
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
		tutor.show_hint(str(phase.goal))
		return {"accepted": false, "reason": "tutorial_objective"}
	# Validate and commit through the same rules as ordinary battles. A failed
	# attempt restores the lecture pause without spending time or advancing.
	var teaching_pause := simulation_paused
	var recruitment_population: float = by_id[int(phase.target)].population if phase.action == "cast_building" and int(phase.skill) == 0 else 0.0
	simulation_paused = false
	var result := super.submit_player_command(command)
	simulation_paused = teaching_pause
	if result.accepted:
		accepted_action = true
		observation_hint = ""
		if phase.action == "cast_building" and int(phase.skill) == 0:
			recruit_result_population = recruitment_population + RECRUIT_RATE * SKILL_DURATIONS[0]
		if teaching_pause: _continue()
		if (phase.action == "reinforce_tower" or (phase.action == "cast_building" and int(phase.skill) == 2)) and not wave_started:
			wave_started = true
			issue_order(by_id[2], by_id[1], 100, 1)
	return result

func _record_event(kind: String, payload: Dictionary) -> void:
	if kind == "tower_volley" and payload.faction == 0: tower_shots += 1
	if kind == "casualty" and payload.faction == 1 and payload.burning: burned_enemies += 1

func _record_arrival(target: int, faction: int, _strength: float, _bonus: float, _energy_origin: bool) -> void:
	if faction == 0 and target == 1 and haste_seen: haste_arrived = true
	# The native arrival handler has applied damage, and the shield has not yet
	# ticked down. This also witnesses damage in a frame crossing shield expiry.
	if lesson_id == "shield" and target == 1 and faction == 1 and shields.has(1) and by_id[1].faction == 0:
		shield_damage_seen = true

func _observe_practice() -> void:
	if lesson_id == "drum":
		for unit: WarMarches.MarchUnit in marches._units:
			if unit.order.faction == 0 and unit.is_exposed() and marches.speed_multiplier(unit) > morale.speed(0) + 0.1:
				haste_seen = true

func _objective_met() -> bool:
	match phase.action:
		"capture": return accepted_action and by_id[int(phase.target)].faction == 0 and marches.incoming_for(int(phase.target), 0) == 0 and (lesson_id != "morale" or morale.level(0) >= 1)
		"ratio": return percentage == 25
		"zoom": return absf(camera.size - phase_start_zoom) >= 0.8
		"pan": return camera_rig.position.distance_to(phase_start_camera) >= 1.0 and not camera_rig.dragging
		"upgrade": return accepted_action and by_id[0].level >= 2 and not by_id[0].is_constructing
		"dispatch": return accepted_action and _army_exposed(0) >= 6
		"reinforce_tower": return accepted_action and tower_shots > 0 and wave_started and marches.total_for(1) == 0 and marches.incoming_for(1, 0) == 0 and projectiles.is_empty() and by_id[1].faction == 0
		"cast_building":
			if not accepted_action: return false
			if int(phase.skill) == 0:
				return faction_skills[0].recruit_target_id < 0 and faction_skills[0].durations[0] <= 0.0 and by_id[int(phase.target)].population >= recruit_result_population - 0.0001
			return not shields.has(int(phase.target)) and shield_damage_seen and wave_started and marches.total_for(1) == 0 and by_id[int(phase.target)].faction == 0
		"energy_watch": return energy >= minf(ENERGY_MAX, phase_start_energy + 5.0)
		"cast_ground": return accepted_action and haste_seen and haste_arrived and not marches.haste_zones.has(0) and marches.incoming_for(1, 0) == 0
		"fire_hit": return accepted_action and burned_enemies >= 3 and fire_states.is_empty()
	return false

func _result_visible_long_enough() -> bool:
	if phase.action not in OBSERVED_ACTIONS: return true
	var hold := RESULT_HOLD
	# Hand-emitted motes outlive their ring. Their authored lifetime, rather
	# than cooldown or rendering quality, determines the final viewing period.
	if phase.action == "cast_building":
		hold = maxf(hold, world_effects.get_node("RecruitMotes" if int(phase.skill) == 0 else "ShieldMotes").lifetime)
	elif phase.action == "cast_ground":
		hold = maxf(hold, world_effects.get_node("HasteMotes").lifetime)
	elif phase.action in ["capture", "upgrade"]:
		var building: WarBuilding = by_id[int(phase.target)]
		if phase.action == "upgrade":
			for particles: GPUParticles3D in building._construction_particles:
				hold = maxf(hold, particles.lifetime)
		if building._capture_tween and building._capture_tween.is_running(): return false
		for effect: Dictionary in effects:
			if effect.kind == "capture" and effect.at == building.global_position: return false
	return elapsed - result_ready_at >= hold

func _observation_hint() -> String:
	if not accepted_action: return ""
	match phase.action:
		"capture":
			if marches.incoming_for(int(phase.target), 0) == 0 and by_id[int(phase.target)].faction != 0:
				return "兵力不足，再派一批。"
		"fire_hit":
			if fire_states.is_empty() and burned_enemies < 3: return "命中不足 3 人，点「重练」。"
		"cast_ground":
			if not marches.haste_zones.has(0) and not haste_seen: return "未加速到援军，点「重练」。"
		"cast_building", "reinforce_tower":
			if by_id[int(phase.target)].faction != 0: return "据点失守，点「重练」。"
	return ""

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
	if phase.action == "upgrade": return "点击住宅旁的向上箭头。"
	if phase.action in ["cast_ground", "fire_hit"]: return "将技能拖到标出的部队；右键取消。"
	return str(phase.goal)

func _world_rect(at: Vector3, radius: float = 3.8) -> Rect2:
	var result := Rect2(camera.unproject_position(at), Vector2.ZERO)
	for x: float in [-radius, radius]:
		for y: float in [0.0, 5.0]:
			for z: float in [-radius, radius]:
				result = result.expand(camera.unproject_position(at + Vector3(x, y, z)))
	return result.grow(10.0)

func _ui_rect(path: String) -> Rect2:
	return (hud.get_node(path) as Control).get_global_rect().grow(8.0)

func _ownership_label(building: WarBuilding) -> Dictionary:
	return {"text": "中立" if building.faction < 0 else ("己方" if building.faction == local_faction else "敌方"),
		"target": _mesh_rect(building.get_node("Visual/Flag")), "badge": true, "side": "right",
		"obstacle": _world_rect(building.global_position).merge(_population_rect(building))}

func _mesh_rect(mesh: MeshInstance3D) -> Rect2:
	var bounds := mesh.get_aabb()
	var result := Rect2(camera.unproject_position(mesh.to_global(bounds.position)), Vector2.ZERO)
	for corner: int in 8:
		result = result.expand(camera.unproject_position(mesh.to_global(bounds.get_endpoint(corner))))
	return result.grow(3.0)

func _army_rect(faction: int) -> Rect2:
	var result := Rect2(camera.unproject_position(_army_center(faction)), Vector2.ZERO)
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.order.faction == faction and unit.is_exposed():
			result = result.expand(camera.unproject_position(unit.position))
			result = result.expand(camera.unproject_position(unit.position + Vector3.UP * 1.5))
	return result.grow(8.0)

func _tower_range_rect(building: WarBuilding) -> Rect2:
	var result := Rect2(camera.unproject_position(building.global_position), Vector2.ZERO)
	for index: int in 64:
		var angle := TAU * float(index) / 64.0
		var edge := building.global_position + Vector3(cos(angle), 0, sin(angle)) * building.attack_range
		result = result.expand(camera.unproject_position(edge))
	return result.grow(14.0)

func _population_rect(building: WarBuilding) -> Rect2:
	var badge: MeshInstance3D = building.get_node("PopulationBadge")
	var center := camera.unproject_position(badge.global_position)
	var edge := camera.unproject_position(badge.global_position + camera.global_basis.x * 1.675 * badge.scale.x)
	var half_size := Vector2.ONE * center.distance_to(edge)
	return Rect2(center - half_size, half_size * 2.0).grow(4.0)

func _update_guidance() -> void:
	if phase.is_empty() or lesson_complete or _local_menu: return
	var rectangles: Array[Rect2] = []
	var labels: Array[Dictionary] = []
	# Once the real action starts, leave its result unobstructed. Reviewing the
	# explanation restores the same labels and demonstration while time freezes.
	if not tutor.is_instruction_visible():
		tutor.set_spotlights(rectangles)
		tutor.set_annotations(labels)
		tutor.set_interaction_regions(rectangles)
		tutor.clear_gesture()
		return
	var focus := str(phase.focus)
	# Labels teach the current concept; a highlighted building alone must not
	# reintroduce ownership and population captions throughout the course.
	var teaching_labels: Array = phase.labels
	if focus.begins_with("building:"):
		var building: WarBuilding = by_id[int(focus.get_slice(":", 1))]
		rectangles.append(_world_rect(building.global_position))
		if "ownership" in teaching_labels:
			labels.append(_ownership_label(building))
		if "population" in teaching_labels:
			labels.append({"text": "驻军", "target": _population_rect(building), "side": "above"})
		if "kind" in teaching_labels:
			labels.append({"text": KIND_NAMES[building.kind], "target": rectangles[0], "side": "below"})
		if "range" in teaching_labels:
			rectangles.append(_tower_range_rect(building))
			var edge := camera.unproject_position(building.global_position + Vector3.RIGHT * building.attack_range)
			labels.append({"text": "射程", "target": Rect2(edge - Vector2.ONE * 4.0, Vector2.ONE * 8.0), "side": "right"})
	elif focus.begins_with("army:"):
		var army := _army_rect(int(focus.get_slice(":", 1)))
		rectangles.append(army.grow(20.0))
		labels.append({"text": "己方部队" if focus == "army:0" else "敌方部队", "target": army})
	elif focus.begins_with("skill:"):
		rectangles.append(_ui_rect("UI/Skills/Row/Skill" + focus.get_slice(":", 1)))
		rectangles.append(_world_rect(_aim_position(), 4.4))
		labels.append({"text": SKILL_RULES.NAMES[int(phase.skill)], "target": rectangles[0], "side": "left"})
		if phase.has("army"):
			var army := _army_rect(int(phase.army))
			rectangles[1] = army.grow(20.0)
			labels.append({"text": "己方部队" if int(phase.army) == 0 else "敌方部队", "target": army})
	else:
		match focus:
			"buildings":
				rectangles.append(_world_rect(by_id[0].global_position))
				rectangles.append(_world_rect(by_id[1].global_position))
				if "ownership" in teaching_labels:
					labels.append(_ownership_label(by_id[0]))
					labels.append(_ownership_label(by_id[1]))
				if "population" in teaching_labels:
					labels.append({"text": "驻军", "target": _population_rect(by_id[0]), "side": "above"})
			"top":
				rectangles.append(_ui_rect("UI/Top/Balance/Segments"))
				rectangles.append(_ui_rect("UI/Top/Time"))
				labels.append({"text": "兵力占比", "target": rectangles[0], "side": "below"})
				labels.append({"text": "己方兵力", "target": _ui_rect("UI/Top/PlayerTotal"), "side": "left"})
				labels.append({"text": "敌方兵力", "target": _ui_rect("UI/Top/EnemyTotal"), "side": "right"})
				labels.append({"text": "时间", "target": rectangles[1], "side": "below"})
			"morale":
				rectangles.append(_ui_rect("UI/Top/Balance/Stars/Faction0"))
				rectangles.append(_ui_rect("UI/Top/Balance/Stars/Faction1"))
				labels.append({"text": "己方士气", "target": rectangles[0], "side": "below"})
				labels.append({"text": "敌方士气", "target": rectangles[1], "side": "below"})
			"skills", "skill_row":
				rectangles.append(_ui_rect("UI/Skills/Row"))
				labels.append({"text": "技能", "target": rectangles[0], "side": "left"})
				if focus == "skills":
					rectangles.append(_ui_rect("UI/Skills/EnergyBar"))
					labels.append({"text": "技力", "target": rectangles[1], "side": "right"})
			"energy_meter":
				rectangles.append(_ui_rect("UI/Skills/EnergyBar"))
				labels.append({"text": "技力", "target": rectangles[0], "side": "right"})
			"ratios":
				rectangles.append(_ui_rect("UI/Percentages"))
				labels.append({"text": "出兵比例", "target": rectangles[0], "side": "above"})
			"selection", "upgrade":
				rectangles.append(_world_rect(by_id[0].global_position))
				if focus == "upgrade":
					rectangles.append(_ui_rect("UI/Selection/BuildingActions/Upgrade"))
					labels.append({"text": "升级", "target": _ui_rect("UI/Selection/BuildingActions/Upgrade/Icon"), "side": "above",
						"obstacle": hud.get_node("UI/Selection/BuildingActions").get_global_rect()})
				else:
					# Reserve space for the wider caption before the shorter one.
					for kind: String in ["Forge", "Tower"]:
						var action_path := "UI/Selection/BuildingActions/Convert" + kind
						rectangles.append(_ui_rect(action_path))
						labels.append({"text": "炮塔" if kind == "Tower" else "铁匠铺", "target": _ui_rect(action_path + "/Icon"), "side": "above",
							"obstacle": hud.get_node("UI/Selection/BuildingActions").get_global_rect()})
			"energy":
				rectangles.append(_world_rect(by_id[1].global_position))
				rectangles.append(_ui_rect("UI/Skills/EnergyBar"))
				labels.append({"text": "能量塔", "target": rectangles[0], "side": "above"})
				labels.append({"text": "技力", "target": rectangles[1], "side": "right"})
	tutor.set_spotlights(rectangles)
	var annotation_obstacles: Array[Rect2] = []
	if not labels.is_empty():
		for building: WarBuilding in buildings:
			var bounds := _world_rect(building.global_position)
			if building.is_population_visible():
				bounds = bounds.merge(_population_rect(building))
			annotation_obstacles.append(bounds)
		if focus in ["selection", "upgrade"]:
			for action: Control in hud.get_node("UI/Selection/BuildingActions").get_children():
				if action.visible:
					annotation_obstacles.append(action.get_global_rect())
	tutor.set_annotations(labels, annotation_obstacles)
	var regions: Array[Rect2] = []
	if simulation_paused and _can_direct_interact():
		match phase.action:
			"capture", "dispatch", "reinforce_tower", "upgrade", "cast_building", "cast_ground", "fire_hit": regions.assign(rectangles)
			"ratio": regions.append(_ui_rect("UI/Percentages/Stack/P25"))
			"zoom", "pan":
				var view := get_viewport().get_visible_rect().size
				regions.append(Rect2(Vector2(160, 170), view - Vector2(320, 320)))
	tutor.set_interaction_regions(regions)
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
	var body := LESSONS.summary(lesson_id)
	if saved != OK: body += "\n进度保存失败，可重试本课。"
	tutor.set_objective(LESSONS.title(lesson_id), "本课目标已完成", "%d / %d" % [lesson_steps.size(), lesson_steps.size()])
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
