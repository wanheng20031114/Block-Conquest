extends SceneTree
## Black-box coverage of the whole orthographic view, including the lower water plane.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(1200, 900), Vector2i(2100, 900), Vector2i(3200, 900), Vector2i(900, 1600)]
const EDGE_TARGETS: Array[Vector3] = [Vector3(-10000, 0, -10000), Vector3(10000, 0, -10000), Vector3(10000, 0, 10000), Vector3(-10000, 0, 10000)]
const PAN_ACTIONS: Array[StringName] = [&"war_pan_left", &"war_pan_right", &"war_pan_up", &"war_pan_down"]
const TOLERANCE := 0.03
var game: Node3D
var checks := 0
var failures: Array[String] = []
var scenario := ""


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		var failure := scenario + ": " + label
		failures.append(failure)
		printerr("FAIL ", failure)


func _view_error() -> String:
	var camera: Camera3D = game.camera
	camera.force_update_transform()
	var viewport: Rect2 = camera.get_viewport().get_visible_rect()
	var corners: Array[Vector2] = [viewport.position, Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]
	if not is_finite(camera.size) or camera.size <= 0.0:
		return "invalid orthographic size %s" % camera.size
	for height: float in [0.0, -1.18]:
		var allowed: Rect2 = game.map.definition.camera_bounds
		if height == 0.0:
			allowed = allowed.grow(-2.0)
		allowed = allowed.grow(TOLERANCE)
		var plane := Plane(Vector3.UP, height)
		for corner: Vector2 in corners:
			var hit: Variant = plane.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
			if hit == null:
				return "corner %s does not intersect y=%s" % [corner, height]
			var point: Vector3 = hit
			if not allowed.has_point(Vector2(point.x, point.z)):
				return "corner %s hits %s outside %s at size=%s" % [corner, point, allowed, camera.size]
	return ""


func _check_view(label: String) -> void:
	var error := _view_error()
	check(error.is_empty(), label + ("; " + error if not error.is_empty() else ""))


func _advance(count: int, label: String) -> void:
	var first_error := ""
	for frame: int in count:
		# Vary frame durations so movement/zoom cannot rely on identical lerp rates.
		var delta: float = [1.0 / 120.0, 1.0 / 30.0, 0.1][frame % 3]
		game.camera_rig._process(delta)
		var error := _view_error()
		if first_error.is_empty() and not error.is_empty():
			first_error = "frame %d: %s" % [frame, error]
	check(first_error.is_empty(), label + ("; " + first_error if not first_error.is_empty() else ""))


func _resize(resolution: Vector2i) -> void:
	# Matching the canvas reference size makes every requested aspect ratio real
	# even when the project uses canvas_items stretching or a headless window.
	root.content_scale_size = resolution
	root.size = resolution
	await process_frame
	await process_frame
	game.camera_rig._process(0.0)
	var visible: Vector2 = root.get_visible_rect().size
	check(is_equal_approx(visible.x / visible.y, float(resolution.x) / resolution.y), "native viewport uses the requested aspect ratio")
	_check_view("resize keeps the entire view on the rendered map")


func _exercise_movement() -> void:
	game.camera_rig.zoom_by(-100000.0)
	_advance(75, "zooming in keeps every intermediate view inside the map")
	check(game.camera_rig.zoom_target > 0.0 and game.camera_rig.zoom_target <= 24.0 + TOLERANCE, "closest zoom respects the configured minimum or a smaller viewport fit")
	for direction: float in [-1.0, 1.0]:
		game.camera_rig.focus_at(Vector3.ZERO, true)
		var before: Vector3 = game.camera_rig.position
		var relative := Vector2.ONE * direction * 100000.0
		game.camera_rig.drag_by(relative)
		_advance(60, "large drag %s from map center stays inside the map" % relative)
		var displacement: Vector3 = game.camera_rig.position - before
		check(displacement.x * direction < -TOLERANCE and displacement.z * direction < -TOLERANCE, "large drag %s moves the displayed camera in the opposite X/Z directions, displacement=%s" % [relative, displacement])
	for target: Vector3 in EDGE_TARGETS:
		game.camera_rig.focus_at(target, true)
		_check_view("instant focus at %s is clamped before the next frame" % target)
		check(game.camera_rig.position.is_equal_approx(game.camera_rig.destination), "instant focus synchronizes the displayed and requested positions")
	for relative: Vector2 in [Vector2(-100000, -100000), Vector2(100000, -100000), Vector2(100000, 100000), Vector2(-100000, 100000)]:
		game.camera_rig.drag_by(relative)
		_advance(60, "large drag %s never exposes the map exterior" % relative)
		var bounded_target: Vector3 = game.camera_rig.destination
		game.camera_rig.drag_by(relative)
		check(game.camera_rig.destination.is_equal_approx(bounded_target), "repeated outward drag does not accumulate an unreachable destination")
		_check_view("repeated outward drag preserves the current view")
	for action: StringName in PAN_ACTIONS:
		Input.action_press(action)
		_advance(75, "held %s remains bounded on every frame" % action)
		Input.action_release(action)
	Input.action_press(&"war_pan_right")
	Input.action_press(&"war_pan_down")
	_advance(75, "diagonal keyboard movement remains bounded")
	Input.action_release(&"war_pan_right")
	Input.action_release(&"war_pan_down")
	game.camera_rig.focus_at(EDGE_TARGETS[0])
	_advance(75, "animated focus remains bounded throughout its approach")


func _exercise_zoom() -> void:
	game.camera_rig.focus_at(EDGE_TARGETS[2], true)
	game.camera_rig.zoom_by(100000.0)
	var farthest: float = game.camera_rig.zoom_target
	check(farthest > 0.0 and farthest <= game.camera_rig.maximum_zoom + TOLERANCE, "wheel zoom is capped by the map fit and configured maximum")
	_advance(90, "zooming out from a corner preserves the entire view on every frame")
	check(absf(game.camera.size - farthest) < TOLERANCE, "displayed zoom converges to its bounded target")
	game.camera_rig.zoom_by(100000.0)
	check(is_equal_approx(game.camera_rig.zoom_target, farthest), "additional outward wheel input cannot exceed the fitted maximum")
	for target: Vector3 in EDGE_TARGETS:
		game.camera_rig.focus_at(target, true)
		_check_view("instant focus remains safe at the widest zoom")
	game.camera_rig.zoom_by(-100000.0)
	game.camera_rig.focus_at(EDGE_TARGETS[1])
	_advance(90, "simultaneous inward zoom and focus remain bounded")
	check(absf(game.camera_rig.zoom_target - minf(24.0, farthest)) < TOLERANCE, "closest zoom uses 24 meters unless the viewport fit requires less")
	for amount: float in [12.0, -6.0, 18.0, -30.0, 100000.0]:
		game.camera_rig.zoom_by(amount)
		_advance(6, "reversing the wheel during zoom keeps the view bounded")
	_advance(75, "interrupted wheel sequence settles within the map")


func _exercise_menu_resize(resolution: Vector2i) -> void:
	game.camera_rig.focus_at(EDGE_TARGETS[2], true)
	game.set_paused(true)
	check(game._local_menu, "pause menu is open before resizing")
	await _resize(resolution)
	var before: Vector3 = game.camera_rig.position
	var target_before: Vector3 = game.camera_rig.destination
	Input.action_press(&"war_pan_right")
	_advance(12, "resized pause-menu view remains inside the map")
	Input.action_release(&"war_pan_right")
	check(game._local_menu and game.camera_rig.position.is_equal_approx(before) and game.camera_rig.destination.is_equal_approx(target_before), "bounds correction does not resume keyboard panning behind the menu")
	game.set_paused(false)
	_advance(12, "closing the menu does not restore stale pre-resize camera targets")


func _check_edges() -> void:
	var window_size := Vector2(1600, 900)
	check(game.camera_rig.edge_direction(Vector2(800, 450), window_size) == Vector2.ZERO, "window center does not edge-scroll")
	check(game.camera_rig.edge_direction(Vector2(-10, 450), window_size) == Vector2.LEFT, "pointer beyond the left window edge retains the correct direction")
	check(game.camera_rig.edge_direction(Vector2(1610, 450), window_size) == Vector2.RIGHT, "pointer beyond the right window edge retains the correct direction")
	check(game.camera_rig.edge_direction(Vector2(800, -10), window_size) == Vector2.UP, "pointer beyond the top window edge retains the correct direction")
	check(game.camera_rig.edge_direction(Vector2(800, 910), window_size) == Vector2.DOWN, "pointer beyond the bottom window edge retains the correct direction")
	check(game.camera_rig.edge_direction(Vector2(1610, -10), window_size) == Vector2(1, -1), "window corner combines both edge directions")


func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var original_map: String = session.block_war_map_id
	var original_size := root.size
	var original_scale := root.content_scale_size
	for definition: Resource in CATALOG.MAPS:
		root.content_scale_size = RESOLUTIONS[0]
		root.size = RESOLUTIONS[0]
		session.block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.camera_rig.edge_scroll = false
		game.camera_rig.keyboard_pan = true
		game.ai_enabled = false
		game.audio.muted = true
		scenario = "%s initial" % definition.map_id
		check(game.map.definition == definition, "the real selected battle map is loaded")
		_check_view("initial scene entry already contains the entire view")
		_check_edges()
		for index: int in RESOLUTIONS.size():
			var resolution := RESOLUTIONS[index]
			scenario = "%s %dx%d" % [definition.map_id, resolution.x, resolution.y]
			await _resize(resolution)
			_exercise_movement()
			_exercise_zoom()
			await _exercise_menu_resize(RESOLUTIONS[(index + 1) % RESOLUTIONS.size()])
		if definition.map_id == "rift":
			scenario = "rift 6000x600 minimum-zoom fit"
			await _resize(Vector2i(6000, 600))
			_exercise_zoom()
			check(game.camera_rig.zoom_target < 24.0, "extreme aspect ratio fits the whole view below the configured minimum zoom")
		print("CAMERA_BOUNDS_MAP ", definition.map_id, " checks=", checks, " failures=", failures.size())
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		game = null
	session.block_war_map_id = original_map
	root.content_scale_size = original_scale
	root.size = original_size
	print("BLOCK_WAR_CAMERA_BOUNDS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
