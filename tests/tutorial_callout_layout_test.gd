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
	# Menu reveals use real time; a fixed frame count is too short at high FPS.
	await create_timer(0.4, true, false, true).timeout
	for frame: int in 3: await process_frame

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
	await inspect_current(label, side)

func inspect_current(label: String, side: String = "") -> void:
	await settle()
	var panel: Rect2 = game.tutor.instruction.get_global_rect()
	var anchor: Rect2 = game.tutor._spotlights[0]
	check(root.get_visible_rect().encloses(panel), label + " stays on screen")
	check(not panel.intersects(game.tutor.objective.get_global_rect()), label + " leaves objective visible")
	for target: Rect2 in game.tutor._spotlights:
		if panel.intersects(target.grow(-1.0)):
			print("CALLOUT_OVERLAP ", label, " panel=", panel, " spotlight=", target)
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
		if panel.intersects(game.tutor.gesture.gesture_bounds()):
			print("CALLOUT_OVERLAP ", label, " panel=", panel, " gesture=", game.tutor.gesture.gesture_bounds())
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
		for obstacle: Rect2 in game.tutor._annotation_obstacles:
			check(not rect.intersects(obstacle), name + " leaves neighboring buildings and their population visible")
		for subject: Dictionary in annotations._items:
			if subject.has("obstacle"):
				check(not rect.intersects(subject.obstacle), name + " leaves the building, population or complete action strip visible")
		for previous: int in index:
			check(not rect.intersects(rects[previous]), name + " does not cover another label")
		var line: PackedVector2Array = annotations._lines[index]
		for obstacle: Rect2 in game.tutor._annotation_obstacles:
			if not obstacle.has_point(item.target.get_center()):
				check(not annotations._crosses_rect(line[0], line[1], obstacle), name + " leader avoids neighboring buildings and their population")
		check(line[0].distance_to(line[1]) <= 180.0, name + " uses a short leader (" + str(snappedf(line[0].distance_to(line[1]), 1.0)) + "px)")

func advance_core(label: String, command: Dictionary = {}, review_label: String = "") -> void:
	var before: int = game.phase_index
	if command.is_empty():
		game._continue()
	else:
		check(game.submit_player_command(command).accepted, label + " accepts the actual teaching command")
	if not review_label.is_empty():
		game._replay()
		await inspect_current(review_label)
		if root.get_visible_rect().size.x < 1150.0:
			inspect_flipping_gesture(review_label)
		game._continue()
	for tick: int in 600:
		if game.phase_index > before: break
		game._process(0.1)
		await process_frame
	check(game.phase_index > before, label + " reaches its actual simulation result")

func inspect_stats(label: String) -> void:
	await inspect_current(label)
	check(game.tutor.stats_panel.visible, label + " shows its authored data table")
	var grid: GridContainer = game.tutor.stats_grid
	check(grid.columns == 2 and grid.get_child_count() == 8, label + " keeps the fixed four-row two-column layout")
	for index: int in game.phase.stats.size():
		var name_cell: Label = grid.get_child(index * 2)
		var value_cell: Label = grid.get_child(index * 2 + 1)
		check(name_cell.visible and value_cell.visible, label + " row is visible")
		check(absf(name_cell.get_rect().get_center().y - value_cell.get_rect().get_center().y) <= 1.0, label + " aligns each label and value")
		check(not name_cell.get_rect().intersects(value_cell.get_rect()), label + " separates labels from numbers")
		check(game.tutor.instruction.get_global_rect().encloses(value_cell.get_global_rect()), label + " keeps numerical values within the callout")
	for index: int in range(game.phase.stats.size() * 2, grid.get_child_count()):
		check(not grid.get_child(index).visible, label + " hides unused table cells")
	if game.phase.get("beat", "") == "forge_trial" and root.get_visible_rect().size.x < 1150.0:
		inspect_flipping_gesture(label)

func inspect_flipping_gesture(label: String) -> void:
	var diagram: Control = game.tutor.gesture
	var previous_phase: float = diagram.phase
	var bounds: Rect2 = diagram.gesture_bounds()
	var panel: Rect2 = game.tutor.instruction.get_global_rect()
	var showed_left := false
	var showed_right := false
	# Sample both sides of the legend's flip threshold without advancing the
	# AnimationPlayer clock or changing the permanent layout exclusions.
	for tick: int in range(1, 100):
		diagram.phase = float(tick) / 100.0
		diagram._update_diagram()
		showed_left = showed_left or diagram.mouse.position.x < diagram.cursor.position.x
		showed_right = showed_right or diagram.mouse.position.x > diagram.cursor.position.x
		check(bounds.encloses(diagram.mouse.get_global_rect()), label + " swept bounds contain mouse at " + str(tick))
		check(bounds.encloses(diagram.caption.get_global_rect()), label + " swept bounds contain caption at " + str(tick))
		check(not panel.intersects(diagram.mouse.get_global_rect()), label + " callout leaves mouse visible at " + str(tick))
		check(not panel.intersects(diagram.caption.get_global_rect()), label + " callout leaves caption visible at " + str(tick))
		var cursor_bounds := Rect2(diagram.cursor.global_position, Vector2.ZERO)
		for shape: Polygon2D in diagram.cursor.get_children():
			for point: Vector2 in shape.polygon:
				cursor_bounds = cursor_bounds.expand(shape.to_global(point))
		check(bounds.encloses(cursor_bounds), label + " swept bounds contain cursor and shadow at " + str(tick))
		check(not panel.intersects(cursor_bounds), label + " callout leaves cursor visible at " + str(tick))
		check(diagram.gesture_bounds() == bounds, label + " swept bounds stay fixed at " + str(tick))
	for at: Vector2 in [diagram._from, diagram._to]:
		# Maximum 36px click ripple, its stroke, and one pixel of antialiasing.
		var ripple := Rect2(at - Vector2.ONE * 38.0, Vector2.ONE * 76.0)
		check(bounds.encloses(ripple), label + " swept bounds contain the click ripple")
		check(not panel.intersects(ripple), label + " callout leaves the click ripple visible")
	check(showed_left and showed_right, label + " checks both sides of the native legend flip")
	diagram.phase = previous_phase
	diagram._update_diagram()

func inspect_core_tables(width: int) -> void:
	await load_lesson("core_buildings")
	game.set_process(false)
	await advance_core("core tower conversion", {"type": "convert", "building": 1, "kind": 1})
	check(game.by_id[1].kind == 1, "core tower table follows native construction")
	await inspect_stats("core_tower_stats_%d" % width)
	await advance_core("core tower defense")
	check(not game.tutor.stats_panel.visible, "next construction step removes the previous table")
	await advance_core("core forge conversion", {"type": "convert", "building": 1, "kind": 2})
	check(game.by_id[1].kind == 2, "core forge table follows native construction")
	await inspect_stats("core_forge_stats_%d" % width)
	await advance_core("core forge comparison", {"type": "dispatch", "source": 0, "target": 2, "percent": 50})
	await advance_core("core energy conversion", {"type": "convert", "building": 1, "kind": 3})
	check(game.by_id[1].kind == 3, "core energy table follows native construction")
	await inspect_stats("core_energy_stats_%d" % width)
	await advance_core("core energy recovery")
	await inspect_current("core_recruit_drag_%d" % width)
	await advance_core("core recruitment defense", {"type": "skill_building", "skill": 0, "target": 2}, "core_recruit_review_%d" % width)
	await inspect_current("core_counterattack_drag_%d" % width)
	await advance_core("core counterattack", {"type": "dispatch", "source": 2, "target": 3, "percent": 50})
	await inspect_current("core_haste_drag_%d" % width)
	var aim: Vector3 = game._aim_position()
	await advance_core("core haste attack", {"type": "skill_ground", "skill": 1, "x": aim.x, "z": aim.z})
	await inspect_current("core_shield_drag_%d" % width)
	await advance_core("core shield defense", {"type": "skill_building", "skill": 2, "target": 2})
	await inspect_current("core_fire_drag_%d" % width)
	aim = game._aim_position()
	await advance_core("core fire defense", {"type": "skill_ground", "skill": 3, "x": aim.x, "z": aim.z})
	check(game.lesson_complete, "core layout walkthrough completes through real skills")

func finish_validation(previous_progress: String, progress_file: String) -> void:
	await game.prepare_shutdown()
	root.get_node("Session").tutorial_progress_path = previous_progress
	if FileAccess.file_exists(progress_file): DirAccess.remove_absolute(progress_file)
	print("TUTORIAL_CALLOUT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	var previous_progress: String = session.tutorial_progress_path
	var progress_file := "res://.local/tutorial-layout-progress-%d.cfg" % OS.get_process_id()
	check(DirAccess.make_dir_recursive_absolute("res://.local") == OK, "isolated progress directory exists")
	session.tutorial_progress_path = progress_file
	var user_args := OS.get_cmdline_user_args()
	var core_only := user_args.has("--core-only")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 768)]:
		# An optional second user argument scopes visual follow-up to one width.
		if user_args.size() > 1 and user_args[1] != "--core-only" and resolution.x != int(user_args[1]):
			continue
		root.size = resolution
		root.content_scale_size = resolution
		if core_only:
			await inspect_core_tables(resolution.x)
			continue
		await load_lesson("core_command")
		await settle()
		await inspect_phase(4, "top_%d" % resolution.x, "below")
		await inspect_phase(5, "morale_%d" % resolution.x, "below")
		await inspect_phase(7, "skills_%d" % resolution.x, "above")
		await inspect_phase(6, "ratios_%d" % resolution.x, "right")
		game._continue()
		check(not game.tutor.is_instruction_visible(), "practice dismisses callout")
		game._replay()
		await settle()
		check(game.tutor.is_instruction_visible(), "replay restores callout")
		await load_lesson("core_command")
		await inspect_phase(2, "ownership_%d" % resolution.x)
		await inspect_phase(3, "building_drag_%d" % resolution.x)
		await inspect_core_tables(resolution.x)
		await load_lesson("house")
		await inspect_phase(1, "upgrade_%d" % resolution.x)
		check(game.tutor.annotations._items.size() == 1 and game.tutor.annotations._items[0].text == "升级", "upgrade only identifies its current action")
		game.by_id[0].level = 2
		game.by_id[0].population = 31.0
		game.by_id[0].refresh_visual()
		game.update_hud()
		await inspect_phase(2, "conversion_%d" % resolution.x)
		var conversion_labels: Array = game.tutor.annotations._items.map(func(item: Dictionary): return item.text)
		check(conversion_labels == ["铁匠铺", "炮塔"], "conversion names the two new symbols without repeating ownership or upgrade")
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
	if core_only:
		await finish_validation(previous_progress, progress_file)
		return
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
	await finish_validation(previous_progress, progress_file)
