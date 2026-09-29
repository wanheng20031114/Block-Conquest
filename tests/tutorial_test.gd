extends SceneTree
## Complete all eleven authored lessons through native input and real rules.
const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const BATTLE := preload("res://scenes/tutorial/tutorial_battle.tscn")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var output := "res://.local/tutorial/review"

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func mouse(at: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else (MOUSE_BUTTON_MASK_MIDDLE if pressed and button == MOUSE_BUTTON_MIDDLE else 0)
	root.push_input(event, true)

func motion(at: Vector2, relative: Vector2 = Vector2.ZERO, buttons: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = buttons
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

func capture(label: String) -> void:
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func _run() -> void:
	create_timer(220.0, true, false, true).timeout.connect(func(): quit(3))
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1600, 900)
	var session: Node = root.get_node("Session")
	var original_map: String = session.block_war_map_id
	var original_commander: StringName = session.block_war_commander
	var settings: GameSettings = session.settings
	var settings_before := settings.snapshot()
	var isolated_progress := output.path_join("test_progress_%d.cfg" % OS.get_process_id())
	var preferences := settings.defaults()
	preferences.music_enabled = false
	settings._apply_values(preferences, false)
	for id: String in CATALOG.IDS:
		session.tutorial_lesson_id = id
		game = BATTLE.instantiate()
		game.progress_path = isolated_progress
		root.add_child(game)
		current_scene = game
		game.set_process(false)
		await physics_frame
		for frame: int in 8: await process_frame
		check(game.simulation_paused and not game.ai_enabled and game.network_match == null, id + " opens paused and offline")
		var time_before: float = game.elapsed
		var population_before: float = game.by_id[0].population
		var energy_before: float = game.energy
		game._process(3.0)
		check(is_equal_approx(time_before, game.elapsed) and is_equal_approx(population_before, game.by_id[0].population) and is_equal_approx(energy_before, game.energy), id + " lecture freezes all simulation resources")
		await capture(id + "_intro")
		var completed_steps := 0
		while not game.lesson_complete and completed_steps < 12:
			var index: int = game.phase_index
			var action: String = game.phase.action
			click(game.tutor.continue_button)
			await process_frame
			if action == "read":
				check(game.phase_index > index or game.lesson_complete, id + " read advances")
				completed_steps += 1
				continue
			check(game.practicing and not game.simulation_paused, id + " practice accepts input")
			var rejected: Dictionary = game.submit_player_command({"type": "convert", "building": 0, "kind": 2})
			check(not rejected.accepted, id + " unrelated command cannot disrupt lesson")
			match action:
				"capture", "dispatch", "reinforce_tower":
					var from: Vector2 = game.camera.unproject_position(game.by_id[0].global_position + Vector3.UP * 1.5)
					var to: Vector2 = game.camera.unproject_position(game.by_id[1].global_position + Vector3.UP * 1.5)
					drag(from, to)
					check(game.accepted_action, id + " real building drag accepted")
				"ratio": click(game.hud.get_node("UI/Percentages/Stack/P25"))
				"zoom":
					mouse(Vector2(960, 450), true, MOUSE_BUTTON_WHEEL_UP)
					game.camera_rig._process(0.2)
				"pan":
					mouse(Vector2(960, 450), true, MOUSE_BUTTON_MIDDLE)
					motion(Vector2(1060, 450), Vector2(100, 0), MOUSE_BUTTON_MASK_MIDDLE)
					game.camera_rig._process(0.2)
					mouse(Vector2(1060, 450), false, MOUSE_BUTTON_MIDDLE)
				"upgrade": click(game.hud.get_node("UI/Selection/BuildingActions/Upgrade"))
				"cast_building", "cast_ground", "fire_hit":
					game._process(0.0)
					var still: float = game.elapsed
					game._process(10.0)
					check(game.elapsed == still, id + " aiming grants unlimited thinking time")
					var from: Vector2 = game.hud.get_node("UI/Skills/Row/Skill%d" % int(game.phase.skill)).get_global_rect().get_center()
					var to: Vector2 = game.camera.unproject_position(game._aim_position())
					# A real right-click cancellation must leave supplies intact.
					var supply: float = game.energy
					mouse(from, true)
					mouse(to, true, MOUSE_BUTTON_RIGHT)
					mouse(to, false)
					check(game.armed_skill == -1 and game.energy == supply and not game.accepted_action, id + " right-click cancellation is harmless")
					drag(from, to)
					check(game.accepted_action, id + " real skill drag accepted")
					await capture(id + "_cast")
			var ticks := 0
			while game.phase_index == index and not game.lesson_complete and ticks < 500:
				game._process(0.1)
				ticks += 1
				await process_frame
			check(game.phase_index > index or game.lesson_complete, id + "/" + action + " reaches real objective")
			if game.phase_index == index and not game.lesson_complete:
				print("STUCK ", id, " action=", action, " accepted=", game.accepted_action, " units=", game.marches.total_for(1), " tower_shots=", game.tower_shots, " haste=", game.haste_seen, " burned=", game.burned_enemies, " shield_damage=", game.shield_damage_seen)
				break
			completed_steps += 1
		check(game.lesson_complete and game.simulation_paused, id + " finishes with frozen completion card")
		if id == "morale": check(game.morale.level(0) >= 1, "morale lesson truly crosses first star")
		if id == "forge": check(game.forge_count(0) == 1 and game.attack_bonus(0) > 0, "forge bonus is real")
		await capture(id + "_complete")
		await game.prepare_shutdown()
		game.free()
		game = null
		await process_frame
	check(PROGRESS.completed_lessons(isolated_progress).size() == 11, "all eleven completions saved separately")
	DirAccess.remove_absolute(isolated_progress)
	check(session.block_war_map_id == original_map and session.block_war_commander == original_commander, "lessons preserve skirmish map and commander")
	settings._apply_values(settings_before, false)
	print("TUTORIAL_TEST checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
