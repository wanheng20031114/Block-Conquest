extends SceneTree
## Fullscreen railway containment and native station input.

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
	for down: bool in [true, false]:
		mouse(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, down)

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

func view_stays_inside(diorama: SubViewportContainer) -> bool:
	# Independently intersect corner rays with the lowest authored terrain surface.
	var camera: Camera3D = diorama.camera
	var extent: Vector2 = camera.get_viewport().get_visible_rect().size
	var ground := Plane(Vector3.UP, 5.0)
	for corner: Vector2 in [Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y)]:
		var hit: Variant = ground.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
		if hit == null or hit.x < -40.0 or hit.x > 128.0 or hit.z < 0.0 or hit.z > 40.0:
			return false
	return true

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		capture_directory = args[0]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var session := root.get_node("Session")
	var saved_progress: int = session.campaign_completed_count
	var saved_active: int = session.campaign_active_stage
	var preferences: Dictionary = session.settings.snapshot()
	var content_aspect := root.content_scale_aspect
	var had_selection: bool = session.has_meta("campaign_selected_stage")
	var previous_selection: int = session.get_meta("campaign_selected_stage", 0)
	session.campaign_completed_count = 3
	session.set_meta("campaign_selected_stage", 0)
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	while current_scene.diorama.intro_running:
		await process_frame
	await settle()
	var atlas: Control = current_scene
	var diorama: SubViewportContainer = atlas.diorama
	check(atlas.stops.size() == 6, "six projected station buttons remain playable")
	check(atlas.selected_index == 0 and atlas.stops[0].visible, "returning to an inspected station keeps selection and camera together")
	for removed: String in ["Header", "Footer", "Details", "StationShortcuts", "CameraControls", "ExploreHint", "IntroHint"]:
		check(atlas.find_child(removed, true, false) == null, "fullscreen map removes " + removed)
	check(diorama.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "railway retains perspective scenery")
	var parked_at: Vector3 = diorama.train.global_position
	check(parked_at.distance_to(diorama.parking_anchors[3].global_position) < 0.05, "train remains at the saved progress station")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1920, 820), Vector2i(1440, 1080)]:
		root.size = resolution
		await settle()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_size() == resolution, "rendering covers the full window without letterboxing at " + str(resolution))
		check(diorama.get_global_rect().is_equal_approx(atlas.get_global_rect()), "map fills viewport at " + str(resolution))
		check(atlas.get_node("%MapInput").get_global_rect().is_equal_approx(atlas.get_global_rect()), "map input covers the entire screen")
		check(Vector2(diorama.get_node("World").size).is_equal_approx(diorama.size), "3D viewport follows the actual aspect ratio")
		for index: int in 6:
			key((KEY_1 + index) as Key)
			var contained := true
			for frame: int in 18:
				await process_frame
				contained = contained and view_stays_inside(diorama)
			check(contained, "station %d tween stays inside map at %s" % [index + 1, resolution])
			check(atlas.selected_index == index, "number key selects station %d" % (index + 1))
			check(atlas.stops[index].visible, "focused station is reachable on screen")
			check(atlas.stops[index].completed == (index < 3), "completed badge follows progress")
			check(atlas.stops[index].unlocked == (index <= 3), "station availability follows progress")
			check(atlas.stops.filter(func(stop: Button): return stop.selected).size() == 1, "exactly one station is selected")
			check(is_equal_approx(diorama.camera.position.z, diorama.maximum_distance()), "default view uses the maximum covered vertical extent")
			check(atlas.stops[index].position.distance_to(diorama.stage_position(index) + atlas.MARKER_OFFSET) < 0.1, "station marker tracks camera projection")
			if resolution.x == 1600 and index in [0, 3, 5]:
				await capture("campaign-station-%d" % (index + 1))
		for steps: float in [-100.0, 100.0]:
			diorama.zoom_view(steps)
			for delta: Vector2 in [Vector2(-100000, -100000), Vector2(100000, -100000), Vector2(100000, 100000), Vector2(-100000, 100000)]:
				diorama.pan_view(delta)
				check(view_stays_inside(diorama), "extreme zoom/drag cannot expose map edges at " + str(resolution))
		check(is_equal_approx(diorama.camera.position.z, diorama.maximum_distance()), "zooming out stops at map height")
		check(diorama.train.global_position.distance_to(parked_at) < 0.02, "browsing never moves the progress train")
		diorama.focus_station(0, false)
		await settle()
		await capture("campaign-fullscreen-%d" % resolution.x)
	root.size = Vector2i(1600, 900)
	await settle()
	key(KEY_3)
	await settle()
	var middle := Vector2(180, 160)
	var distance_before: float = diorama.camera.position.z
	mouse(middle, MOUSE_BUTTON_WHEEL_UP, true)
	mouse(middle, MOUSE_BUTTON_WHEEL_UP, false)
	check(diorama.camera.position.z < distance_before, "wheel input zooms the landscape")
	var target_before: Vector3 = diorama.camera_rig.position
	mouse(middle, MOUSE_BUTTON_LEFT, true)
	var drag := InputEventMouseMotion.new()
	drag.position = middle + Vector2(100, 20)
	drag.global_position = drag.position
	drag.relative = Vector2(100, 20)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	mouse(drag.position, MOUSE_BUTTON_LEFT, false)
	check(diorama.camera_rig.position.distance_to(target_before) > 1.0, "drag input browses the map")
	check(view_stays_inside(diorama), "mouse browsing stays within terrain")
	key(KEY_KP_6)
	await settle()
	click(atlas.stops[5])
	key(KEY_ENTER)
	await settle()
	check(current_scene == atlas, "locked station cannot launch by click or Enter")
	key(KEY_LEFT)
	await settle()
	check(atlas.selected_index == 4, "left arrow selects the previous station")
	key(KEY_RIGHT)
	await settle()
	check(atlas.selected_index == 5, "right arrow selects the next station")
	key(KEY_P)
	await settle()
	check(session.settings.is_open(), "P opens settings without a top bar")
	check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings pauses map rendering")
	key(KEY_1)
	check(atlas.selected_index == 5, "settings blocks station hotkeys")
	click(session.settings.menu.get_node("%Close"))
	await settle()
	check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "closing settings resumes map rendering")
	key(KEY_1)
	await settle()
	click(atlas.stops[0])
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == session.COMMANDER_SCENE and session.campaign_active_stage == 0, "clicking an unlocked station opens its commander selection")
	session.back_to_campaign()
	await scene_changed
	await settle()
	key(KEY_2)
	await settle()
	key(KEY_ENTER)
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == session.COMMANDER_SCENE and session.campaign_active_stage == 1, "Enter launches the keyboard-selected station")
	session.back_to_campaign()
	await scene_changed
	await settle()
	key(KEY_ESCAPE)
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "Escape returns to the lobby")
	check(root.content_scale_aspect == content_aspect, "leaving the railway restores other menus' scaling")
	check(current_scene.get_node("%Campaign").has_focus(), "lobby restores campaign entry focus")
	check(session.settings.snapshot() == preferences, "browsing preserves preferences")
	check(session.campaign_completed_count == 3, "browsing and commander selection preserve progress")
	session.campaign_completed_count = saved_progress
	session.campaign_active_stage = saved_active
	if had_selection:
		session.set_meta("campaign_selected_stage", previous_selection)
	else:
		session.remove_meta("campaign_selected_stage")
	print("CAMPAIGN_MAP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
