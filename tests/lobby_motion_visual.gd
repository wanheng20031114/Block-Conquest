extends SceneTree
## Actual 24 fps render on a private desktop. Only synthetic viewport input;
## the scene-authored cursor is a recording overlay, never a game UI element.
const POINTER := preload("res://tests/lobby_motion_pointer.tscn")
const FRAMES := 432
var toy: LobbyDiorama
var cursor: Polygon2D
var mouse_point := Vector2(610, 700)
var output_directory: String
var taps := 0

func _initialize() -> void:
	# Passive native picking otherwise reads the unrelated OS cursor.
	physics_frame.connect(_feed_mouse)
	_run.call_deferred()

func _feed_mouse() -> void:
	var event := InputEventMouseMotion.new()
	event.position = mouse_point
	event.global_position = mouse_point
	root.push_input(event, true)

func click() -> void:
	_feed_mouse()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = mouse_point
		event.global_position = mouse_point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func project(at: Vector3) -> Vector2:
	return toy.global_position + toy.camera.unproject_position(at) * toy.size / Vector2(toy.viewport.size)

func save_still(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_directory.path_join(name + ".png"))

func _run() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func(): quit(3))
	output_directory = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	toy = current_scene.get_node("%Diorama")
	var overlay := POINTER.instantiate()
	root.add_child(overlay)
	cursor = overlay.get_node("Cursor")
	var session: Node = root.get_node("Session")
	var original: Dictionary = session.settings.snapshot()
	for building: LobbyOutpost in toy.outposts:
		building.touched.connect(func(_outpost): taps += 1)
	var start := Vector2(610, 700)
	var home_point := Vector2.ZERO
	var east_point := Vector2.ZERO
	var water_point := Vector2.ZERO
	var main_button: Button = current_scene.get_node("%BlockWarMode")
	var settings_button: Button = current_scene.get_node("%Settings")
	for frame: int in FRAMES:
		if frame == 40:
			home_point = project(toy.outposts[0].global_position + Vector3(0, 1.3, 0))
			east_point = project(toy.outposts[1].global_position + Vector3(0, 1.1, 0))
			water_point = project(Vector3(3.0, -0.6, 4.1))
		if frame >= 40 and frame <= 80:
			mouse_point = start.lerp(home_point, smoothstep(40, 80, frame))
		elif frame >= 130 and frame <= 170:
			mouse_point = home_point.lerp(east_point, smoothstep(130, 170, frame))
		elif frame >= 200 and frame <= 235:
			mouse_point = east_point.lerp(water_point, smoothstep(200, 235, frame))
		elif frame >= 280 and frame <= 310:
			mouse_point = water_point.lerp(main_button.get_global_rect().get_center(), smoothstep(280, 310, frame))
		elif frame >= 318 and frame <= 335:
			mouse_point = main_button.get_global_rect().get_center().lerp(settings_button.get_global_rect().get_center(), smoothstep(318, 335, frame))
		elif frame >= 360 and frame <= 375:
			mouse_point = settings_button.get_global_rect().get_center().lerp(session.settings.menu.get_node("%Close").get_global_rect().get_center(), smoothstep(360, 375, frame))
		elif frame >= 396:
			mouse_point = start
		if frame in [104, 175, 240, 336, 376]:
			click()
		cursor.visible = frame >= 40 and frame < 396
		cursor.position = mouse_point
		_feed_mouse()
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png(output_directory.path_join("frame_%04d.png" % frame)) != OK:
			quit(1)
			return
	var correct: bool = taps == 2 and not session.settings.is_open() and session.settings.snapshot() == original
	cursor.hide()
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(960, 540), Vector2i(1024, 768)]:
		root.size = resolution
		for frame: int in 6:
			await process_frame
		await save_still("home_%dx%d" % [resolution.x, resolution.y])
	print("LOBBY_MOTION_VISUAL frames=", FRAMES, " taps=", taps, " correct=", correct)
	quit(0 if correct else 1)
