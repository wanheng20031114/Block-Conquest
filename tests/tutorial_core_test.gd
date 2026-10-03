extends SceneTree
## Complete the two core courses with native input and unchanged battle rules.
const BATTLE := preload("res://scenes/tutorial/tutorial_battle.tscn")
const ORDINARY := preload("res://scenes/block_war/block_war.tscn")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
const COURSES: Array[String] = ["core_command", "core_buildings"]
var checks := 0
var failures: Array[String] = []
var game: Node3D
var session: Node
var output := ""
var progress_path := ""
var events: Array[Dictionary] = []
var shield_contacts := 0
var haste_witnessed := false
var user_progress: Variant

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func frames(count: int = 4) -> void:
	for frame: int in count:
		await process_frame

func motion(at: Vector2, relative: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)

func mouse(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_MIDDLE if pressed and button == MOUSE_BUTTON_MIDDLE else 0)
	root.push_input(event, true)

func click(control: Control) -> void:
	var at := control.get_global_rect().get_center()
	motion(at)
	mouse(at, true)
	mouse(at, false)

func drag(from: Vector2, to: Vector2) -> void:
	motion(from)
	mouse(from, true)
	motion(from.lerp(to, 0.5), (to - from) * 0.5, MOUSE_BUTTON_MASK_LEFT)
	motion(to, (to - from) * 0.5, MOUSE_BUTTON_MASK_LEFT)
	mouse(to, false)

func snapshot() -> Dictionary:
	var state := {"elapsed": game.elapsed, "energy": game.energy, "buildings": {},
		"enemies": game.marches.total_for(1), "incoming": game.marches.total_for(0),
		"shields": game.shields.duplicate(), "fire": game.fire_states.size(),
		"cooldowns": game.cooldowns.duplicate(), "durations": game.active_durations.duplicate()}
	for building: WarBuilding in game.buildings:
		state.buildings[building.building_id] = {"faction": building.faction, "kind": building.kind,
			"population": building.population, "level": building.level,
			"construction": building.construction_remaining}
	return state

func record_event(kind: String, payload: Dictionary) -> void:
	events.append({"kind": kind, "payload": payload.duplicate(true)})

func record_arrival(target: int, faction: int, _strength: float, _bonus: float, _energy: bool) -> void:
	if faction == 1 and game.shields.has(target) and game.by_id[target].faction == 0:
		shield_contacts += 1

func event_count(kind: String, faction: int = -2) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.kind == kind and (faction == -2 or event.payload.get("faction", -2) == faction):
			count += 1
	return count

func dispatched_to(target: int, faction: int = 0) -> int:
	var count := 0
	for event: Dictionary in events:
		if event.kind == "dispatch" and event.payload.faction == faction and event.payload.target == target:
			count += int(event.payload.count)
	return count

func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func act(action: String) -> void:
	match action:
		"capture", "dispatch", "reinforce_tower":
			var source: WarBuilding = game.by_id[int(game.phase.source)]
			var target: WarBuilding = game.by_id[int(game.phase.target)]
			drag(game.camera.unproject_position(source.global_position + Vector3.UP * 1.5),
				game.camera.unproject_position(target.global_position + Vector3.UP * 1.5))
		"convert":
			var names: Array[String] = ["House", "Tower", "Forge", "Energy"]
			click(game.hud.get_node("UI/Selection/BuildingActions/Convert" + names[int(game.phase.kind)]))
		"upgrade":
			click(game.hud.get_node("UI/Selection/BuildingActions/Upgrade"))
		"ratio":
			# The core course accepts any changed ratio, not only the old 25% task.
			click(game.hud.get_node("UI/Percentages/Stack/P75"))
			check(game.percentage == 75, "core ratio practice accepts a different non-default percentage")
		"zoom":
			mouse(Vector2(960, 450), true, MOUSE_BUTTON_WHEEL_UP)
			game.camera_rig._process(0.2)
			game._process(0.0)
		"pan":
			mouse(Vector2(960, 450), true, MOUSE_BUTTON_MIDDLE)
			motion(Vector2(1060, 450), Vector2(100, 0), MOUSE_BUTTON_MASK_MIDDLE)
			game.camera_rig._process(0.2)
			mouse(Vector2(1060, 450), false, MOUSE_BUTTON_MIDDLE)
			game._process(0.0)
		"cast_building", "cast_ground", "fire_hit":
			var from: Vector2 = game.hud.get_node("UI/Skills/Row/Skill%d" % int(game.phase.skill)).get_global_rect().get_center()
			var to: Vector2 = game.camera.unproject_position(game._aim_position())
			var before := snapshot()
			mouse(from, true)
			mouse(to, true, MOUSE_BUTTON_RIGHT)
			mouse(to, false)
			check(game.armed_skill == -1 and not game.accepted_action and snapshot() == before, "cancelling a core skill aim spends no time or resources")
			drag(from, to)
		_:
			check(false, "core course has a native input driver for " + action)

func verify_beat(beat: String, start: Dictionary, result: Dictionary) -> void:
	match beat:
		"make_tower", "make_forge", "make_energy":
			var expected := 1 if beat == "make_tower" else (2 if beat == "make_forge" else 3)
			check(result.buildings[1].kind == expected and result.buildings[1].construction == 0.0, beat + " finishes an actual native conversion")
			check(event_count("construction_complete", 0) == 1, beat + " emits the native completion exactly once")
		"tower_demo":
			check(event_count("tower_volley", 0) > 0, "newly built tower really shoots at the teaching wave")
			check(result.enemies == 0 and result.buildings[1].faction == 0, "tower demonstration resolves with the player's tower intact")
		"forge_trial":
			check(start.buildings[2].population == 24.0 and start.buildings[2].faction == -1 and start.buildings[2].level == 1, "forge comparison begins against exactly 24 neutral level-one defenders")
			check(dispatched_to(2) == 20, "native fifty-percent drag commits exactly 20 attackers")
			check(result.buildings[2].faction == 0 and result.buildings[2].population > 0.0, "twenty attackers truly capture the 24-defender position with forge attack bonus")
			check(result.incoming == 0, "forge comparison waits for the complete attacking column")
		"energy_demo":
			check(result.energy - start.energy >= 3.0 - 0.001, "native energy tower produces the demonstrated recovery")
			check(result.elapsed - start.elapsed <= 4.0, "energy observation stays brief")
		"recruit_defense":
			check(event_count("skill", 0) == 1 and dispatched_to(2, 1) == 22, "recruitment triggers its real skill and authored enemy attack")
			check(result.buildings[2].faction == 0 and result.buildings[2].population > 0.0 and result.enemies == 0, "recruitment genuinely preserves the threatened outpost")
			check(result.durations[0] == 0.0, "recruitment finishes its full effect before the next instruction")
		"counterattack":
			check(dispatched_to(3) == 20 and result.incoming > 0, "counterattack dispatches twenty soldiers and pauses while they remain available for haste")
		"haste_attack":
			check(haste_witnessed, "native haste actually accelerates a visible marcher")
			check(result.incoming == 0 and result.buildings[3].faction == 1 and result.buildings[3].population > 0.0, "haste attack resolves without prematurely capturing the enemy staging point")
		"shield_defense":
			check(shield_contacts > 0, "enemy soldiers deal real damage during the shield's active span")
			check(result.buildings[2].faction == 0 and result.buildings[2].population > 0.0 and result.enemies == 0, "shielded outpost truly survives the counterattack")
		"fire_defense":
			var burned := 0
			for event: Dictionary in events:
				if event.kind == "casualty" and event.payload.faction == 1 and event.payload.burning:
					burned += 1
			check(burned >= 20, "the fire skill eliminates a substantial part of the large enemy column")
			check(result.enemies == 0 and result.buildings[2].faction == 0, "fire demonstration clears the threat and preserves the outpost")
			check(result.fire == 0, "the fire fully dissipates before advancing")

func run_course(id: String) -> void:
	session.tutorial_lesson_id = id
	game = BATTLE.instantiate()
	game.progress_path = progress_path
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.presentation_event.connect(record_event)
	game.marches.unit_arrived.connect(record_arrival)
	await physics_frame
	await frames(8)
	check(game.tutorial_ready and game.simulation_paused and not game.ai_enabled and game.network_match == null, id + " starts as an isolated paused course")
	var phases := 0
	while not game.lesson_complete and phases < 50:
		var index: int = game.phase_index
		var action: String = game.phase.action
		var beat := str(game.phase.get("beat", ""))
		var label := "%s/%02d/%s/%s" % [id, index, beat, action]
		events.clear()
		shield_contacts = 0
		haste_witnessed = false
		await frames()
		var before := snapshot()
		game._process(12.0)
		check(snapshot() == before, label + " grants unlimited thinking time without advancing resources or armies")
		if beat in ["forge_trial", "counterattack"]:
			game.set_percentage(75)
			check(game.percentage == 50, beat + " preserves the supplied twenty-soldier example")
			var rejected: Dictionary = game.submit_player_command({"type": "dispatch", "source": game.phase.source, "target": game.phase.target, "percent": 75})
			check(not rejected.accepted and not game.accepted_action and snapshot() == before, beat + " rejects a mismatched order without spending supplies")
		if not beat.is_empty():
			await capture(id + "_%02d_" % index + beat)
		var direct: bool = game._is_direct_action()
		if direct:
			check(not game.tutor.continue_button.visible, label + " directly accepts the taught action")
			act(action)
			check(game.accepted_action or game.phase_index > index, label + " accepts native input")
		else:
			click(game.tutor.continue_button)
		if action == "read":
			await process_frame
			check(game.phase_index > index or game.lesson_complete, label + " continues through the real instruction button")
			phases += 1
			continue
		var result := snapshot()
		var ticks := 0
		while game.phase_index == index and not game.lesson_complete and not game.step_retry_pending and ticks < 700:
			game._process(0.1)
			for unit: WarMarches.MarchUnit in game.marches._units:
				if unit.order.faction == 0 and unit.is_exposed() and game.marches.speed_multiplier(unit) > game.morale.speed(0) + 0.1:
					haste_witnessed = true
			result = snapshot()
			ticks += 1
			await process_frame
		check(game.phase_index > index or game.lesson_complete, label + " reaches its real simulation objective")
		if game.phase_index == index and not game.lesson_complete:
			printerr("CORE_STUCK ", label, " ", JSON.stringify(result), " accepted=", game.accepted_action, " burned=", game.burned_enemies, " retry=", game.step_retry_pending)
			break
		verify_beat(beat, before, result)
		print("CORE_PHASE ", label, " seconds=", result.elapsed - before.elapsed, " population=", result.buildings)
		phases += 1
	check(game.lesson_complete and game.simulation_paused, id + " reaches a frozen completion card")
	await capture(id + "_complete")
	await game.prepare_shutdown()
	game.free()
	game = null
	await process_frame

func verify_fire_edges() -> void:
	var directions: Array[Vector3] = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
	for index: int in directions.size():
		session.tutorial_lesson_id = "core_buildings"
		game = BATTLE.instantiate()
		game.progress_path = progress_path
		root.add_child(game)
		current_scene = game
		game.set_process(false)
		# The vignette begins from the authored final chapter state. Only setup
		# skips earlier lessons; the enemy wave, player input and combat are real.
		game.by_id[1].kind = 3
		game.by_id[1].refresh_visual()
		game.by_id[2].faction = 0
		for phase: int in game.lesson_steps.size():
			if game.lesson_steps[phase].get("beat", "") == "fire_defense":
				game.phase_index = phase - 1
				break
		game._next_phase()
		await physics_frame
		await frames(8)
		game._process(0.0)
		var fire_phase: int = game.phase_index
		var instance := game.get_instance_id()
		var before := snapshot()
		var at: Vector3 = game._army_center(1) + directions[index] * game.skill_radius(3) * 0.85
		var from: Vector2 = game.hud.get_node("UI/Skills/Row/Skill3").get_global_rect().get_center()
		drag(from, game.camera.unproject_position(at))
		check(game.accepted_action, "native fire edge %d remains a legal aim inside the allowed radius" % index)
		for tick: int in 140:
			game._process(0.1)
			await process_frame
			if game.step_retry_pending or game.lesson_complete:
				break
		check(game.step_retry_pending or game.lesson_complete, "fire edge %d always reaches success or a recoverable result" % index)
		print("CORE_FIRE_EDGE ", JSON.stringify({"direction": str(directions[index]), "burned": game.burned_enemies, "retry": game.step_retry_pending, "complete": game.lesson_complete, "owner": game.by_id[2].faction, "enemies": game.marches.total_for(1)}))
		if game.step_retry_pending:
			check(game.burned_enemies < 40 and not game.lesson_complete and game.simulation_paused, "missed fire freezes a failed attempt instead of awarding completion")
			check(game.tutor.continue_button.visible and game.tutor.continue_button.text == "重试这一步", "missed fire exposes an actionable retry for just this step")
			await capture("core_fire_edge_%d_retry" % index)
			var failed := snapshot()
			game._process(12.0)
			check(snapshot() == failed, "failure explanation grants unlimited retry decision time")
			click(game.tutor.continue_button)
			await frames(8)
			game._process(0.0)
			check(game.get_instance_id() == instance and game.phase_index == fire_phase and not game.step_retry_pending, "native retry reuses the current battle and final phase")
			check(game.by_id[2].faction == 0 and game.marches.total_for(1) == 40 and game.cooldowns[3] == 0.0 and game.energy == 100.0, "native retry restores the outpost, one exact enemy wave and cast supplies")
			check(game.by_id[0].population == before.buildings[0].population and game.by_id[1].kind == before.buildings[1].kind and game.by_id[1].population == before.buildings[1].population, "native retry preserves the earlier chapter's other buildings")
			for building: WarBuilding in game.buildings:
				check(building.queued_population >= 0 and building.queued_population <= floori(building.population), "retry retains valid doorway reservations at building %d" % building.building_id)
			act("fire_hit")
			check(game.accepted_action, "native centered cast remains possible immediately after retry")
			for tick: int in 140:
				game._process(0.1)
				await process_frame
				if game.step_retry_pending or game.lesson_complete:
					break
		print("CORE_FIRE_RETRY_RESULT ", JSON.stringify({"direction": str(directions[index]), "burned": game.burned_enemies, "retry": game.step_retry_pending, "complete": game.lesson_complete, "owner": game.by_id[2].faction, "enemies": game.marches.total_for(1)}))
		check(game.lesson_complete and game.burned_enemies == 40 and game.marches.total_for(1) == 0 and game.by_id[2].faction == 0, "fire edge %d can finish by eliminating all forty soldiers" % index)
		await game.prepare_shutdown()
		game.free()
		game = null
		await process_frame

func verify_ordinary_construction() -> void:
	session.block_war_map_id = "rift"
	session.campaign_active_stage = -1
	game = ORDINARY.instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.ai_enabled = false
	await frames()
	var home: WarBuilding
	for building: WarBuilding in game.buildings:
		if building.faction == 0 and building.kind == 0:
			home = building
			break
	home.population = 40.0
	check(game.submit_player_command({"type": "convert", "building": home.building_id, "kind": 1}).accepted, "ordinary game still accepts native house-to-tower conversion")
	check(is_equal_approx(home.construction_remaining, 10.0), "ordinary conversion still takes the full ten seconds")
	game.simulate(9.9)
	check(home.kind == 0 and home.is_constructing, "ordinary construction retains the original building before ten seconds")
	game.simulate(0.1)
	check(home.kind == 1 and not home.is_constructing, "ordinary construction completes at the unchanged deadline")
	await game.prepare_shutdown()
	game.free()
	game = null
	await process_frame

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): printerr("TUTORIAL_CORE_TIMEOUT"); quit(3))
	output = ProjectSettings.globalize_path("res://.local/tutorial-core/test-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(output)
	progress_path = output.path_join("progress.cfg")
	user_progress = FileAccess.get_file_as_bytes(PROGRESS.SAVE_PATH) if FileAccess.file_exists(PROGRESS.SAVE_PATH) else null
	root.size = Vector2i(1600, 900)
	session = root.get_node("Session")
	var original := [session.block_war_map_id, session.block_war_commander, session.campaign_active_stage, session.tutorial_lesson_id]
	for id: String in COURSES:
		await run_course(id)
	check(PROGRESS.completed_lessons(progress_path).size() == COURSES.size(), "both core completions are saved only to the isolated progress file")
	await verify_fire_edges()
	await verify_ordinary_construction()
	session.block_war_map_id = original[0]
	session.block_war_commander = original[1]
	session.campaign_active_stage = original[2]
	session.tutorial_lesson_id = original[3]
	var after: Variant = FileAccess.get_file_as_bytes(PROGRESS.SAVE_PATH) if FileAccess.file_exists(PROGRESS.SAVE_PATH) else null
	check(after == user_progress, "core-course validation leaves the player's real tutorial record unchanged")
	print("TUTORIAL_CORE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
