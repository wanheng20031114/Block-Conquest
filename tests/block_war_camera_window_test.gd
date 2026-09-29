extends SceneTree
## Native Windows display changes run on the private desktop GPU runner.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var output: String

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func view_inside_map() -> bool:
	var viewport := root.get_visible_rect()
	game.camera.force_update_transform()
	for height: float in [0.0, -1.18]:
		var allowed: Rect2 = game.map.definition.camera_bounds
		allowed = allowed.grow(-2.0 if height == 0.0 else 0.0).grow(0.03)
		for corner: Vector2 in [viewport.position, Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]:
			var hit: Variant = Plane(Vector3.UP, height).intersects_ray(game.camera.project_ray_origin(corner), game.camera.project_ray_normal(corner))
			if hit == null or not allowed.has_point(Vector2(hit.x, hit.z)):
				return false
	return is_finite(game.camera.size) and game.camera.size > 0.0

func frames(count: int = 8) -> void:
	for frame: int in count:
		await process_frame

func display_check(label: String) -> void:
	var all_inside := true
	for frame: int in 10:
		await process_frame
		all_inside = view_inside_map() and all_inside
	check(all_inside, label + " remains bounded through native window notifications")
	print("CAMERA_WINDOW ", label, " mode=", root.mode, " window=", root.size, " viewport=", root.get_visible_rect().size, " zoom=", game.camera.size)

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " GPU screenshot saved")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	if DisplayServer.get_name() == "headless":
		printerr("Run this native-window check with the GPU private desktop runner.")
		quit(2)
		return
	output = OS.get_cmdline_user_args()[0]
	var session := root.get_node("Session")
	var settings: GameSettings = session.settings
	# Exercise the real settings flow without overwriting the player's preferences.
	settings.settings_path = output.path_join("settings.cfg")
	settings._apply_values(settings.defaults(), false)
	var saved_preferences := settings.snapshot()
	session.block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.zoom_by(10000.0)
	for frame: int in 90: game.camera_rig._process(1.0 / 30.0)
	game.camera_rig.focus_at(Vector3(10000, 0, -10000), true)
	var original_reference := root.content_scale_size
	for resolution: Vector2i in [Vector2i(1024, 768), Vector2i(2560, 720), Vector2i(900, 1200), Vector2i(1600, 900)]:
		DisplayServer.window_set_size(resolution)
		await display_check("resize %s" % resolution)
		check(root.content_scale_size == original_reference, "native resize retains the project's canvas reference size")
	await capture("native_window")
	# Resize must work while camera processing is blocked by both pause and settings.
	game.set_paused(true)
	settings.open_menu()
	for mode: Window.Mode in [Window.MODE_MAXIMIZED, Window.MODE_WINDOWED, Window.MODE_FULLSCREEN, Window.MODE_WINDOWED]:
		root.mode = mode
		await display_check("modal mode %s" % mode)
		check(game._local_menu and settings.is_open(), "display changes preserve the local menu and settings")
	root.mode = Window.MODE_MINIMIZED
	await frames()
	root.mode = Window.MODE_WINDOWED
	await display_check("restore from minimized")
	check(game._local_menu and settings.is_open(), "minimize and restore do not resume battle controls")
	# Verify the settings dialog's apply/revert path, including render scaling.
	var candidate := settings.snapshot()
	candidate.window_mode = 1
	candidate.resolution = Vector2i(1280, 720)
	settings.apply_preferences(candidate)
	await display_check("settings fullscreen preview")
	check(settings.display_timer.time_left > 0.0, "display preview starts its real revert timer")
	await capture("fullscreen_settings")
	settings.display_timer.timeout.emit()
	await display_check("settings automatic revert")
	check(settings.window_mode == saved_preferences.window_mode and settings.resolution == saved_preferences.resolution, "preview timeout restores the original display preference")
	check(settings._display_previous.is_empty(), "preview timeout clears pending display state")
	var initial_position: Vector3 = game.camera_rig.position
	var initial_zoom: float = game.camera.size
	for scale: float in [0.5, 0.75, 1.0]:
		root.scaling_3d_scale = scale
		await display_check("render scale %s" % scale)
		check(game.camera_rig.position.distance_to(initial_position) < 0.01 and absf(game.camera.size - initial_zoom) < 0.01, "3D render resolution does not change world framing")
	settings.close_menu()
	game.set_paused(false)
	game.camera_rig.zoom_by(-10000.0)
	for frame: int in 90: game.camera_rig._process(1.0 / 30.0)
	game.camera_rig.focus_at(Vector3.ZERO, true)
	var before: Vector3 = game.camera_rig.position
	game.camera_rig.drag_by(Vector2(120, 40))
	for frame: int in 30: game.camera_rig._process(1.0 / 30.0)
	check(game.camera_rig.position.distance_to(before) > 0.1 and view_inside_map(), "camera still pans safely after all modal and display changes")
	await capture("restored_controls")
	await game.prepare_shutdown()
	print("BLOCK_WAR_CAMERA_WINDOW checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
