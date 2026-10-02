extends SceneTree
## Native input verifies a browsable full-scale railway and saved progression.

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
	await create_timer(0.8, true, false, true).timeout

func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down: bool in [true, false]:
		mouse(point, MOUSE_BUTTON_LEFT, down)

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
	create_timer(150.0, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		capture_directory = args[0]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var session := root.get_node("Session")
	var saved_progress: int = session.campaign_completed_count
	session.campaign_completed_count = 3
	var preferences: Dictionary = session.settings.snapshot()
	var had_selection: bool = session.has_meta("campaign_selected_stage")
	var previous_selection: int = session.get_meta("campaign_selected_stage", 0)
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = resolution
		session.set_meta("campaign_selected_stage", 0)
		change_scene_to_file("res://scenes/lobby.tscn")
		await scene_changed
		await settle()
		click(current_scene.get_node("%Campaign"))
		await scene_changed
		await session.transition.completed
		if current_scene.diorama.intro_running:
			await current_scene.diorama.intro_finished
		await settle()
		var atlas: Control = current_scene
		var diorama: SubViewportContainer = atlas.diorama
		check(atlas.scene_file_path == "res://scenes/campaign/campaign_map.tscn", "home opens the campaign")
		check(atlas.stops.size() == 6 and atlas.station_shortcuts.size() == 6, "six world markers and six persistent station shortcuts exist")
		check(diorama.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and is_equal_approx(diorama.camera.fov, 30.0), "reference uses a 30 degree perspective lens")
		check(is_equal_approx(diorama.camera.position.z, diorama.STATION_DISTANCE), "default camera shows a station region instead of compressing the whole world")
		check(is_equal_approx(diorama.camera_rig.position.x, clampf(diorama.anchors[3].position.x - 2.0, -14.0, 112.0)), "initial camera visits the latest progress station")
		check(atlas.selected_index == 0, "inspected stage remains separate from saved progress")
		check(atlas.get_node("%Start").text.contains("再次挑战"), "cleared stations offer replay")
		check(atlas.get_node("%Progress").text.contains("03 / 06"), "saved progress is displayed")
		var parked_at: Vector3 = diorama.train.global_position
		check(parked_at.distance_to(diorama.parking_anchors[3].global_position) < 0.05, "train parks at the current station's actual stopping position")
		await capture("campaign-%d" % resolution.x)
		for index: int in 6:
			click(atlas.station_shortcuts[index])
			await settle()
			var stop: Button = atlas.stops[index]
			check(atlas.selected_index == index, "persistent native button selects station %d" % index)
			check(atlas.get_node("%StageTitle").text == stop.stage.title, "title matches the inspected station")
			check(atlas.get_node("%Description").text == stop.stage.description, "description matches the inspected station")
			check(atlas.get_node("%Start").disabled == (index > 3), "only unlocked stations can start")
			check(stop.completed == (index < 3), "completed badges reflect victories")
			check(diorama.train.global_position.distance_to(parked_at) < 0.02, "camera focus never moves the saved progress train")
			check(is_equal_approx(diorama.camera_rig.position.x, clampf(diorama.anchors[index].position.x - 2.0, -14.0, 112.0)), "station selection moves the camera and frames the world boundary")
			check(stop.visible, "the focused station marker is visible")
			var projection_error: float = atlas.stage_positions[index].distance_to(diorama.camera.unproject_position(diorama.anchors[index].global_position))
			check(projection_error < 0.1, "marker follows station %d (error %.3f px)" % [index, projection_error])
			check(stop.position.distance_to(atlas.stage_positions[index] + atlas.MARKER_OFFSET) < 0.1, "marker uses the latest camera projection")
			check(atlas.stops.filter(func(item: Button): return item.selected).size() == 1, "exactly one world marker is selected")
		await capture("campaign-snow-%d" % resolution.x)
		click(atlas.get_node("%Overview"))
		await settle()
		check(diorama.overview and is_equal_approx(diorama.camera.position.z, diorama.OVERVIEW_DISTANCE), "overview reveals the whole route")
		check(atlas.stops.all(func(stop: Button): return stop.visible), "all six world station markers fit the overview")
		await capture("campaign-overview-%d" % resolution.x)
		click(atlas.stops[2])
		await settle()
		check(atlas.selected_index == 2, "native projected world marker selects its station")
		var input_area: Control = atlas.get_node("%MapInput")
		var middle: Vector2 = input_area.get_global_rect().get_center() + Vector2(170, -65)
		var distance_before: float = diorama.camera.position.z
		mouse(middle, MOUSE_BUTTON_WHEEL_UP, true)
		mouse(middle, MOUSE_BUTTON_WHEEL_UP, false)
		check(diorama.camera.position.z < distance_before, "native wheel input zooms the landscape")
		var target_before: Vector3 = diorama.camera_rig.position
		mouse(middle, MOUSE_BUTTON_LEFT, true)
		var drag := InputEventMouseMotion.new()
		drag.position = middle + Vector2(100, 20)
		drag.global_position = drag.position
		drag.relative = Vector2(100, 20)
		drag.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(drag, true)
		mouse(drag.position, MOUSE_BUTTON_LEFT, false)
		check(diorama.camera_rig.position.distance_to(target_before) > 1.0, "native drag input browses the full-size world")
		check(diorama.train.global_position.distance_to(parked_at) < 0.02, "drag and zoom preserve the parked train")
		click(atlas.get_node("%ReturnTrain"))
		await settle()
		check(atlas.selected_index == 3 and is_equal_approx(diorama.camera.position.z, diorama.STATION_DISTANCE), "return-to-train restores the current station framing")
		key(KEY_1)
		await settle()
		check(atlas.selected_index == 0, "number row selects the first stage")
		atlas.station_shortcuts[0].grab_focus()
		key(KEY_RIGHT)
		await settle()
		check(atlas.selected_index == 1, "native keyboard focus follows station order")
		key(KEY_KP_6)
		await settle()
		check(atlas.selected_index == 5, "numeric keypad selects the last stage")
		click(atlas.get_node("%Previous"))
		await settle()
		check(atlas.selected_index == 4, "previous button selects the preceding station")
		click(atlas.get_node("%Next"))
		await settle()
		check(atlas.selected_index == 5 and atlas.get_node("%Next").disabled, "next button reaches the final station")
		click(atlas.get_node("%Settings"))
		await settle()
		check(session.settings.is_open(), "settings opens from the campaign")
		check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings freezes the landscape")
		key(KEY_3)
		check(atlas.selected_index == 5, "modal settings blocks campaign hotkeys")
		click(session.settings.menu.get_node("%Close"))
		await settle()
		check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "closing settings resumes the landscape")
		key(KEY_ESCAPE)
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "escape returns home")
		check(current_scene.get_node("%Campaign").has_focus(), "home restores the campaign entry focus")
	# Different window shapes keep every persistent shortcut available.
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	if current_scene.diorama.intro_running:
		await current_scene.diorama.intro_finished
	for resolution: Vector2i in [Vector2i(1920, 820), Vector2i(1440, 1080)]:
		root.size = resolution
		await settle()
		check(is_equal_approx(current_scene.get_node("%Atlas").scale.x, current_scene.get_node("%Atlas").scale.y), "wide/tall windows retain uniform scene scale")
		for shortcut: Button in current_scene.station_shortcuts:
			check(current_scene.get_global_rect().encloses(shortcut.get_global_rect()), "every station remains reachable in wide/tall windows")
	check(session.settings.snapshot() == preferences, "browsing does not change settings")
	check(session.campaign_completed_count == 3, "browsing does not advance campaign progress")
	session.campaign_completed_count = saved_progress
	if not had_selection:
		session.remove_meta("campaign_selected_stage")
	else:
		session.set_meta("campaign_selected_stage", previous_selection)
	print("CAMPAIGN_MAP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
