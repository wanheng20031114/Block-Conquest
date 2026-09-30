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
			var bottom := anchor.end.y
			for target: Rect2 in game.tutor._spotlights: bottom = maxf(bottom, target.end.y)
			check(panel.position.y >= bottom and panel.position.y - bottom <= 25.0, label + " sits immediately below its subjects")
		"above":
			check(panel.end.y <= anchor.position.y and anchor.position.y - panel.end.y <= 25.0, label + " sits immediately above its subject")
		"right":
			check(panel.position.x >= anchor.end.x and panel.position.x - anchor.end.x <= 284.0, label + " sits beside the percentage column and its mouse caption")
	if game.tutor.gesture.visible:
		check(not panel.intersects(game.tutor.gesture.gesture_bounds()), label + " leaves demonstration visible")
	inspect_annotations(label)
	var position_before: Vector2 = game.tutor.instruction.position
	var annotation_positions: Array[Rect2] = game.tutor.annotations.annotation_rects()
	await settle()
	check(game.tutor.instruction.position.is_equal_approx(position_before), label + " does not jitter between layouts")
	check(game.tutor.annotations.annotation_rects() == annotation_positions, label + " annotations do not follow the animated mouse")
	print("CALLOUT ", label, " panel=", panel, " target=", anchor)
	if not OS.get_cmdline_user_args().is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(label + ".png")) == OK, label + " screenshot")

func inspect_annotations(label: String) -> void:
	var annotations: Control = game.tutor.annotations
	var rects: Array[Rect2] = annotations.annotation_rects()
	check(rects.size() == annotations._items.size(), label + " labels every requested subject")
	for index: int in rects.size():
		var rect := rects[index]
		var item: Dictionary = annotations._items[index]
		var name := label + " annotation " + str(item.text)
		check(root.get_visible_rect().encloses(rect), name + " stays on screen")
		check(not rect.intersects(game.tutor.objective.get_global_rect()), name + " leaves objective visible")
		check(not rect.intersects(game.tutor.instruction.get_global_rect()), name + " leaves explanation visible")
		check(not rect.intersects(item.target), name + " leaves its subject visible")
		for previous: int in index:
			check(not rect.intersects(rects[previous]), name + " does not cover another label")
		var line: PackedVector2Array = annotations._lines[index]
		check(line[0].distance_to(line[1]) <= 180.0, name + " uses a short leader (" + str(snappedf(line[0].distance_to(line[1]), 1.0)) + "px)")

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768)]:
		root.size = resolution
		root.content_scale_size = resolution
		await load_lesson("interface")
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
		await load_lesson("basics")
		await inspect_phase(1, "ownership_%d" % resolution.x)
		await inspect_phase(2, "building_drag_%d" % resolution.x)
		await load_lesson("house")
		await inspect_phase(1, "upgrade_%d" % resolution.x)
		await load_lesson("tower")
		await inspect_phase(0, "tower_range_%d" % resolution.x)
		for lesson: String in ["recruit", "drum", "shield", "fire"]:
			await load_lesson(lesson)
			if lesson == "drum":
				game._continue()
				check(game.issue_order(game.by_id[0], game.by_id[1], 50, 0) > 0, "drum layout uses a real departure")
				game.simulate(0.25)
				check(game._army_exposed(0) > 0, "drum layout labels exposed units")
			await inspect_phase(1, "%s_drag_%d" % [lesson, resolution.x])
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	await load_lesson("recruit")
	await inspect_phase(1, "edge_gesture")
	# The legend flips above/left near screen edges, including the cursor's
	# opening approach. Its reserved area must include the rendered controls.
	game.set_process(false)
	var diagram: Control = game.tutor.gesture
	diagram.set_gesture(Vector2(1530, 830), Vector2(1420, 700), "drag")
	diagram.player.pause()
	var fixed_exclusions: Array[Rect2] = diagram.annotation_exclusion_rects()
	for beat: float in [0.05, 0.3, 0.5, 0.75]:
		diagram.phase = beat
		diagram._update_diagram()
		check(diagram.gesture_bounds().encloses(diagram.mouse.get_global_rect()), "edge gesture reserves mouse at " + str(beat))
		check(diagram.gesture_bounds().encloses(diagram.caption.get_global_rect()), "edge gesture reserves caption at " + str(beat))
		check(diagram.annotation_exclusion_rects() == fixed_exclusions, "annotation exclusions stay fixed at " + str(beat))
	game.tutor.show_completion("完成", "可以继续下一课。", true)
	await settle()
	check(game.tutor.instruction.get_global_rect().get_center().is_equal_approx(root.get_visible_rect().get_center()), "completion resets to screen center")
	await game.prepare_shutdown()
	print("TUTORIAL_CALLOUT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
