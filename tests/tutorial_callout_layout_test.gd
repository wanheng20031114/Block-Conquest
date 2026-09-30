extends SceneTree
## Exercise real course targets and wrapped text, including changing window size.

var failures: Array[String] = []
var checks := 0
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func settle() -> void:
	for frame: int in 12: await process_frame

func load_lesson(id: String) -> void:
	if game != null: await game.prepare_shutdown()
	root.get_node("Session").tutorial_lesson_id = id
	change_scene_to_file("res://scenes/tutorial/tutorial_battle.tscn")
	await scene_changed
	game = current_scene
	game.audio.muted = true
	await settle()

func inspect_phase(index: int, label: String, side: String = "") -> void:
	game.phase_index = index - 1
	game._next_phase()
	await settle()
	var panel: Rect2 = game.tutor.instruction.get_global_rect()
	var anchor: Rect2 = game.tutor._spotlights[0]
	check(root.get_visible_rect().encloses(panel), label + " stays on screen")
	check(not panel.intersects(game.tutor.objective.get_global_rect()), label + " leaves objective visible")
	for target: Rect2 in game.tutor._spotlights:
		check(not panel.intersects(target.grow(-1.0)), label + " leaves highlighted subject visible")
	match side:
		"below":
			check(panel.position.y >= anchor.end.y and panel.position.y - anchor.end.y <= 25.0, label + " sits immediately below its subject")
		"above":
			check(panel.end.y <= anchor.position.y and anchor.position.y - panel.end.y <= 25.0, label + " sits immediately above its subject")
		"right":
			check(panel.position.x >= anchor.end.x and panel.position.x - anchor.end.x <= 284.0, label + " sits beside the percentage column and its mouse caption")
	if game.tutor.gesture.visible:
		check(not panel.intersects(game.tutor.gesture.gesture_bounds()), label + " leaves demonstration visible")
	var position_before: Vector2 = game.tutor.instruction.position
	await settle()
	check(game.tutor.instruction.position.is_equal_approx(position_before), label + " does not jitter between layouts")
	print("CALLOUT ", label, " panel=", panel, " target=", anchor)
	if not OS.get_cmdline_user_args().is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(label + ".png")) == OK, label + " screenshot")

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	await load_lesson("interface")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768)]:
		root.size = resolution
		root.content_scale_size = resolution
		await settle()
		await inspect_phase(0, "top_%d" % resolution.x, "below")
		await inspect_phase(1, "morale_%d" % resolution.x, "below")
		await inspect_phase(2, "skills_%d" % resolution.x, "above")
		await inspect_phase(3, "ratios_%d" % resolution.x, "right")
		game._continue()
		check(not game.tutor.is_instruction_visible(), "practice dismisses callout")
		game._replay()
		await settle()
		check(game.tutor.is_instruction_visible(), "replay restores callout")
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	await load_lesson("basics")
	await inspect_phase(2, "building_drag")
	await load_lesson("house")
	await inspect_phase(1, "upgrade")
	await load_lesson("recruit")
	await inspect_phase(1, "skill_drag")
	# The legend flips above/left near screen edges, including the cursor's
	# opening approach. Its reserved area must include the rendered controls.
	game.set_process(false)
	var diagram: Control = game.tutor.gesture
	diagram.set_gesture(Vector2(1530, 830), Vector2(1420, 700), "drag")
	diagram.player.pause()
	for beat: float in [0.05, 0.3, 0.5, 0.75]:
		diagram.phase = beat
		diagram._update_diagram()
		check(diagram.gesture_bounds().encloses(diagram.mouse.get_global_rect()), "edge gesture reserves mouse at " + str(beat))
		check(diagram.gesture_bounds().encloses(diagram.caption.get_global_rect()), "edge gesture reserves caption at " + str(beat))
	game.tutor.show_completion("完成", "可以继续下一课。", true)
	await settle()
	check(game.tutor.instruction.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()), "completion resets to screen center")
	await game.prepare_shutdown()
	print("TUTORIAL_CALLOUT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
