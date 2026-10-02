extends SceneTree
## Native input and real rendered scenes exercise the route preview end to end.

var checks := 0
var failures: Array[String] = []
var capture_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func settle() -> void:
	await create_timer(0.75, true, false, true).timeout

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func capture(name: String) -> void:
	if capture_directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name + ".png")) == OK, "save " + name)

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		capture_directory = args[0]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var session := root.get_node("Session")
	var preferences: Dictionary = session.settings.snapshot()
	var had_selection: bool = session.has_meta("campaign_selected_stage")
	var previous_selection: int = session.get_meta("campaign_selected_stage", 0)
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = resolution
		session.set_meta("campaign_selected_stage", 0)
		change_scene_to_file("res://scenes/lobby.tscn")
		await scene_changed
		await settle()
		var lobby: Control = current_scene
		check(lobby.get_global_rect().encloses(lobby.get_node("%Campaign").get_global_rect()), "campaign entry fits the home")
		await capture("lobby-%d" % resolution.x)
		click(lobby.get_node("%Campaign"))
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.scene_file_path == "res://scenes/campaign/campaign_map.tscn", "home opens the campaign route")
		var atlas: Control = current_scene
		var route: Curve2D = atlas.route
		check(atlas.stops.size() == 6, "the planned campaign has exactly six stops")
		var diorama: SubViewportContainer = atlas.diorama
		check(diorama.get_node("World").own_world_3d, "campaign renders an isolated 3D world")
		check(diorama.camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "native orthographic camera preserves the map view")
		check(diorama.anchors.size() == 6, "the six stages have physical scene anchors")
		var maximum_riser := 0.0
		var trail: Curve3D = diorama.world_route.curve
		for sample: int in range(1, trail.point_count):
			maximum_riser = maxf(maximum_riser, absf(trail.get_point_position(sample).y - trail.get_point_position(sample - 1).y))
		check(maximum_riser < 0.29, "the trail crosses terraces on small risers without vertical jumps")
		check(atlas.selected_index == 0, "first visit starts at the woodland")
		check(is_equal_approx(atlas.get_node("%MapViewport").size.aspect(), 16.0 / 9.0), "atlas keeps its 16:9 proportions")
		check(atlas.get_node("%Status").text.contains("关卡制作中"), "unimplemented missions are explicitly presented as a route preview")
		await capture("campaign-%d" % resolution.x)
		for index: int in 6:
			var stop: Button = atlas.stops[index]
			check(atlas.get_global_rect().encloses(stop.get_global_rect()), "stage %d hit area fits" % index)
			var point: Vector2 = atlas.stage_positions[index]
			var anchor: Marker3D = diorama.anchors[index]
			check(point.distance_to(diorama.camera.unproject_position(anchor.global_position)) < 0.1, "stage %d projects its physical landmark" % index)
			check(not diorama.camera.is_position_behind(anchor.global_position), "stage %d is in front of the camera" % index)
			var world_path: Curve3D = diorama.world_route.curve
			check(world_path.get_closest_point(anchor.position).distance_to(anchor.position) < 0.02, "stage %d lies on the physical mountain trail" % index)
			check(route.get_closest_point(point).distance_to(point) < 0.1, "stage %d belongs to the authored curve" % index)
			click(stop)
			await settle()
			check(atlas.selected_index == index, "native click selects stage %d" % index)
			check(atlas.get_node("%StageTitle").text == stop.stage.title, "detail title matches the chosen stage")
			check(atlas.get_node("%Description").text == stop.stage.description, "detail copy matches the chosen stage")
			check(atlas.get_node("%Traveler").position.distance_to(point) < 1.0, "selection traveler reaches the chosen stop")
			check(atlas.stops.filter(func(item: Button): return item.selected).size() == 1, "only one marker is selected")
			check(is_equal_approx(stop.get_node("Badge").position.y, -9.0), "selected marker settles at a stable height")
		check(atlas.get_node("%Next").disabled and not atlas.get_node("%Previous").disabled, "pager respects the last stop")
		await capture("campaign-snow-%d" % resolution.x)
		key(KEY_1)
		await settle()
		check(atlas.selected_index == 0, "number row selects the first stage")
		check(atlas.get_node("%Previous").disabled and not atlas.get_node("%Next").disabled, "pager respects the first stop")
		atlas.stops[0].grab_focus()
		key(KEY_RIGHT)
		await settle()
		check(atlas.selected_index == 1, "native right navigation follows journey order")
		key(KEY_KP_6)
		await settle()
		check(atlas.selected_index == 5, "numeric keypad also selects stages")
		click(atlas.get_node("%Previous"))
		await settle()
		check(atlas.selected_index == 4, "previous button selects the neighboring stop")
		click(atlas.get_node("%Next"))
		await settle()
		check(atlas.selected_index == 5, "next button selects the neighboring stop")
		# Retargeting a live tween must not accumulate lift or change hit targets.
		for code: Key in [KEY_2, KEY_5, KEY_1, KEY_4, KEY_6]:
			key(code)
		await settle()
		check(atlas.selected_index == 5, "rapid input preserves the final requested stop")
		check(atlas.get_node("%Traveler").position.distance_to(atlas.stage_positions[5]) < 1.0, "rapidly interrupted motion reaches its final destination")
		for index: int in atlas.stops.size():
			var stop: Button = atlas.stops[index]
			check(stop.position.distance_to(atlas.stage_positions[index] - Vector2(38, 66)) < 0.1, "selection never moves the projected hit area")
		click(atlas.get_node("%Settings"))
		await settle()
		check(session.settings.is_open(), "settings opens from the campaign")
		check(atlas.get_node("%Snow").speed_scale == 0.0, "ambient snow pauses under settings")
		check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings freezes the model viewport")
		key(KEY_3)
		check(atlas.selected_index == 5, "modal settings blocks route hotkeys")
		click(session.settings.menu.get_node("%Close"))
		await settle()
		check(not session.settings.is_open() and atlas.get_node("%Snow").speed_scale == 1.0, "closing settings restores the atlas")
		check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "closing settings resumes the models")
		key(KEY_ESCAPE)
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "escape returns to the home")
		check(current_scene.get_node("%Campaign").has_focus(), "home restores focus to the campaign entry")
		click(current_scene.get_node("%Campaign"))
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.selected_index == 5, "returning remembers the inspected stop without recording a completed mission")
		click(current_scene.get_node("%Back"))
		await scene_changed
		await session.transition.completed
		await settle()
	# Wider and taller windows retain every route marker without stretching art.
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	for resolution: Vector2i in [Vector2i(1920, 820), Vector2i(1440, 1080)]:
		root.size = resolution
		await settle()
		check(is_equal_approx(current_scene.get_node("%Atlas").scale.x, current_scene.get_node("%Atlas").scale.y), "nonstandard aspect ratios keep equal atlas scales")
		for stop: Button in current_scene.stops:
			check(current_scene.get_global_rect().encloses(stop.get_global_rect()), "nonstandard aspect ratio retains each marker")
	check(session.settings.snapshot() == preferences, "route browsing never changes player preferences")
	if not had_selection:
		session.remove_meta("campaign_selected_stage")
	else:
		session.set_meta("campaign_selected_stage", previous_selection)
	print("CAMPAIGN_MAP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
