extends SceneTree
## Deterministic camera stress with the project's unchanged canvas reference size.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const REFERENCE_SIZE := Vector2i(1600, 900)
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1600, 900), Vector2i(960, 540), Vector2i(1200, 900), Vector2i(2100, 900), Vector2i(3200, 900), Vector2i(900, 1600), Vector2i(6000, 600), Vector2i(600, 2400), Vector2i(320, 180), Vector2i(256, 2048), Vector2i(4096, 256)]
const FRAME_TIMES: Array[float] = [0.0, 1.0 / 240.0, 1.0 / 60.0, 0.1, 0.5, 1.25]
const SPEEDS: Array[float] = [0.25, 1.0, 3.0]
const PAN_ACTIONS: Array[StringName] = [&"war_pan_left", &"war_pan_right", &"war_pan_up", &"war_pan_down"]
const BOUNDARY_TOLERANCE := 0.03
const MOTION_TOLERANCE := 0.02
const DRIFT_TOLERANCE := 0.01
const RANDOM_OPERATIONS := 320
const IDLE_FRAMES := 12000
var game: Node3D
var settings: GameSettings
var checks := 0
var failures: Array[String] = []
var observations := 0
var phase := ""
var phase_errors := 0
var first_error := ""
var reference_mode: int
var reference_aspect: int
var viewport_sizes: Array[Vector2i] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		var failure := phase + ": " + label
		failures.append(failure)
		printerr("FAIL ", failure)


func _begin(label: String) -> void:
	phase = "%s %s" % [game.map.definition.map_id, label]
	phase_errors = 0
	first_error = ""


func _finish() -> void:
	check(phase_errors == 0, "all sampled views remain valid; bad_samples=%d first=%s" % [phase_errors, first_error])


func _view_error() -> String:
	if root.content_scale_size != REFERENCE_SIZE or root.content_scale_mode != reference_mode or root.content_scale_aspect != reference_aspect:
		return "the project's canvas reference/stretch settings changed"
	var camera: Camera3D = game.camera
	var rig: Node3D = game.camera_rig
	if not rig.position.is_finite() or not rig.destination.is_finite():
		return "non-finite displayed or requested camera position"
	if not is_finite(camera.size) or camera.size <= 0.0 or not is_finite(rig.zoom_target) or rig.zoom_target <= 0.0:
		return "invalid displayed or requested orthographic size"
	camera.force_update_transform()
	var viewport: Rect2 = camera.get_viewport().get_visible_rect()
	if viewport.size.x <= 0.0 or viewport.size.y <= 0.0:
		return "non-positive viewport after a non-zero window resize"
	var corners: Array[Vector2] = [viewport.position, Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)]
	for height: float in [0.0, -1.18]:
		var bounds: Rect2 = game.map.definition.camera_bounds
		bounds = bounds.grow(-2.0 if height == 0.0 else 0.0).grow(BOUNDARY_TOLERANCE)
		var plane := Plane(Vector3.UP, height)
		for corner: Vector2 in corners:
			var hit: Variant = plane.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
			if hit == null:
				return "corner %s misses the y=%s plane" % [corner, height]
			var point: Vector3 = hit
			if not point.is_finite() or not bounds.has_point(Vector2(point.x, point.z)):
				return "corner=%s hit=%s bounds=%s size=%s window=%s viewport=%s" % [corner, point, bounds, camera.size, root.size, viewport.size]
	return ""


func _observe(label: String) -> void:
	observations += 1
	var error := _view_error()
	if not error.is_empty():
		phase_errors += 1
		if first_error.is_empty():
			first_error = label + ": " + error


func _tick(delta: float, label: String) -> void:
	game.camera_rig._process(delta)
	_observe(label)


func _settle(label: String) -> void:
	for frame: int in 180:
		_tick(1.0 / 60.0, label)
	check(game.camera_rig.position.distance_to(game.camera_rig.destination) < DRIFT_TOLERANCE and absf(game.camera.size - game.camera_rig.zoom_target) < DRIFT_TOLERANCE, label + " converges to both camera targets")


func _resize(size: Vector2i) -> void:
	# Change the actual window only. Letterboxing/expansion remains the project's
	# native decision; a changed window ratio need not change the logical viewport.
	root.size = size
	await process_frame
	_observe("first frame after resize to %s" % size)
	await process_frame
	_observe("second frame after resize to %s" % size)
	var visible := Vector2i(root.get_visible_rect().size)
	if not viewport_sizes.has(visible):
		viewport_sizes.append(visible)


func _near_center() -> void:
	game.camera_rig.zoom_by(-10000.0)
	_settle("return to close zoom")
	game.camera_rig.focus_at(Vector3.ZERO, true)
	_observe("return to center")


func _speed_and_reversal_cases() -> void:
	_begin("legal speeds and rapid reversals")
	for camera_speed: float in SPEEDS:
		for zoom_speed: float in SPEEDS:
			settings.camera_speed = camera_speed
			settings.zoom_speed = zoom_speed
			_near_center()
			var label := "pan=%s zoom=%s" % [camera_speed, zoom_speed]
			for direction: float in [-1.0, 1.0]:
				game.camera_rig.focus_at(Vector3.ZERO, true)
				var before: Vector3 = game.camera_rig.position
				game.camera_rig.drag_by(Vector2(48, 32) * direction)
				_settle(label + " drag")
				var movement: Vector3 = game.camera_rig.position - before
				check(movement.x * direction < -MOTION_TOLERANCE and movement.z * direction < -MOTION_TOLERANCE, label + " drag changes both displayed axes in the expected direction")
			game.camera_rig.focus_at(Vector3.ZERO, true)
			var start: Vector3 = game.camera_rig.position
			Input.action_press(&"war_pan_right")
			_tick(0.1, label + " keyboard")
			Input.action_release(&"war_pan_right")
			check(game.camera_rig.position.x > start.x + MOTION_TOLERANCE, label + " keyboard movement remains responsive")
			var near_zoom: float = game.camera_rig.zoom_target
			game.camera_rig.zoom_by(3.0)
			check(absf(game.camera_rig.zoom_target - near_zoom - 3.0 * zoom_speed) < MOTION_TOLERANCE, label + " ordinary wheel motion honors the legal zoom-speed setting")
			_settle(label + " wheel")
			for step: int in 96:
				var direction := -1.0 if step % 2 == 0 else 1.0
				game.camera_rig.drag_by(Vector2(160, 90) * direction)
				game.camera_rig.zoom_by(3.0 * direction)
				_tick(FRAME_TIMES[step % FRAME_TIMES.size()], label + " reversal %d" % step)
			_settle(label + " rapid reversal sequence")
			_near_center()
			game.camera_rig.drag_by(Vector2(48, 32))
			_settle(label + " final outward drag")
			var before_reverse: Vector3 = game.camera_rig.position
			game.camera_rig.drag_by(Vector2(-96, -64))
			_settle(label + " final reverse drag")
			check(game.camera_rig.position.x > before_reverse.x + MOTION_TOLERANCE and game.camera_rig.position.z > before_reverse.z + MOTION_TOLERANCE, label + " reversing direction still moves the camera after repeated interruptions")
	_finish()


func _instant_focus_during_zoom() -> void:
	_begin("instant focus while zoom is unfinished")
	settings.camera_speed = 1.0
	settings.zoom_speed = 1.0
	_near_center()
	for index: int in 8:
		game.camera_rig.zoom_by(18.0 if index % 2 == 0 else -18.0)
		_tick(1.0 / 240.0, "start zoom before instant focus")
		check(absf(game.camera.size - game.camera_rig.zoom_target) > MOTION_TOLERANCE, "fixture contains an unfinished zoom before instant focus")
		var sign_x := -1.0 if index % 2 == 0 else 1.0
		var sign_z := -1.0 if index % 4 < 2 else 1.0
		game.camera_rig.focus_at(Vector3(sign_x * 10000.0, 0, sign_z * 10000.0), true)
		_observe("instant focus before any following frame")
		for step: int in 6:
			_tick(FRAME_TIMES[step], "continue unfinished zoom after instant focus")
		_settle("focus and zoom completion")
	_finish()


func _mixed_sequence(seed_value: int) -> void:
	_begin("mixed sequence seed=%d" % seed_value)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var bounds: Rect2 = game.map.definition.camera_bounds
	for index: int in RANDOM_OPERATIONS:
		var label := "operation %d" % index
		match index % 8:
			0:
				game.camera_rig.drag_by(Vector2(random.randf_range(-2400.0, 2400.0), random.randf_range(-1800.0, 1800.0)))
			1:
				game.camera_rig.zoom_by(random.randf_range(-45.0, 45.0))
			2:
				game.camera_rig.focus_at(Vector3(random.randf_range(-bounds.size.x, bounds.size.x), 0.0, random.randf_range(-bounds.size.y, bounds.size.y)))
			3:
				var size_index := floori(float(index) / 8.0) % WINDOW_SIZES.size()
				await _resize(WINDOW_SIZES[size_index])
			4:
				game.camera_rig.zoom_by(random.randf_range(-24.0, 24.0))
				_tick(1.0 / 240.0, label + " unfinished zoom")
				game.camera_rig.focus_at(Vector3(random.randf_range(-1000.0, 1000.0), 0.0, random.randf_range(-1000.0, 1000.0)), true)
			5:
				game.camera_rig.drag_by(Vector2(random.randf_range(-32000.0, 32000.0), random.randf_range(-32000.0, 32000.0)))
			6:
				settings.camera_speed = SPEEDS[random.randi_range(0, SPEEDS.size() - 1)]
				settings.zoom_speed = SPEEDS[random.randi_range(0, SPEEDS.size() - 1)]
			7:
				var action := PAN_ACTIONS[random.randi_range(0, PAN_ACTIONS.size() - 1)]
				Input.action_press(action)
				_tick(FRAME_TIMES[random.randi_range(0, FRAME_TIMES.size() - 1)], label + " keyboard")
				Input.action_release(action)
		_observe(label + " before interpolation")
		for frame: int in random.randi_range(1, 5):
			_tick(FRAME_TIMES[random.randi_range(0, FRAME_TIMES.size() - 1)], label + " after interpolation")
	_settle("mixed sequence final targets")
	_finish()


func _window_restore() -> void:
	_begin("window restore remains operable")
	await _resize(REFERENCE_SIZE)
	settings.camera_speed = 1.0
	settings.zoom_speed = 1.0
	_near_center()
	for direction: float in [-1.0, 1.0]:
		game.camera_rig.focus_at(Vector3.ZERO, true)
		var before: Vector3 = game.camera_rig.position
		game.camera_rig.drag_by(Vector2(120, 80) * direction)
		_settle("drag after restoring window")
		var movement: Vector3 = game.camera_rig.position - before
		check(movement.x * direction < -MOTION_TOLERANCE and movement.z * direction < -MOTION_TOLERANCE, "restored window accepts drag in both directions")
	game.camera_rig.focus_at(Vector3.ZERO, true)
	var before_key: Vector3 = game.camera_rig.position
	Input.action_press(&"war_pan_left")
	_tick(0.1, "keyboard after restoring window")
	Input.action_release(&"war_pan_left")
	check(game.camera_rig.position.x < before_key.x - MOTION_TOLERANCE, "restored window accepts keyboard movement")
	var before_zoom: float = game.camera.size
	game.camera_rig.zoom_by(9.0)
	_settle("zoom after restoring window")
	check(game.camera.size > before_zoom + 1.0, "restored window can still zoom out")
	_finish()


func _idle_stability() -> void:
	_begin("12000 idle frames")
	game.camera_rig.zoom_by(10000.0)
	game.camera_rig.focus_at(Vector3(10000, 0, -10000))
	_settle("idle fixture settles at a fitted boundary")
	var position_before: Vector3 = game.camera_rig.position
	var destination_before: Vector3 = game.camera_rig.destination
	var zoom_before: float = game.camera.size
	var zoom_target_before: float = game.camera_rig.zoom_target
	var position_drift := 0.0
	var destination_drift := 0.0
	var zoom_drift := 0.0
	var zoom_target_drift := 0.0
	for frame: int in IDLE_FRAMES:
		_tick(FRAME_TIMES[frame % FRAME_TIMES.size()], "idle frame %d" % frame)
		position_drift = maxf(position_drift, game.camera_rig.position.distance_to(position_before))
		destination_drift = maxf(destination_drift, game.camera_rig.destination.distance_to(destination_before))
		zoom_drift = maxf(zoom_drift, absf(game.camera.size - zoom_before))
		zoom_target_drift = maxf(zoom_target_drift, absf(game.camera_rig.zoom_target - zoom_target_before))
	check(position_drift < DRIFT_TOLERANCE and destination_drift < DRIFT_TOLERANCE, "idle position/target do not drift: %s / %s meters" % [position_drift, destination_drift])
	check(zoom_drift < DRIFT_TOLERANCE and zoom_target_drift < DRIFT_TOLERANCE, "idle zoom/target do not drift: %s / %s meters" % [zoom_drift, zoom_target_drift])
	check(game.camera_rig.position.distance_to(game.camera_rig.destination) < DRIFT_TOLERANCE and absf(game.camera.size - game.camera_rig.zoom_target) < DRIFT_TOLERANCE, "idle camera remains converged after every frame interval")
	_finish()
	print("CAMERA_IDLE map=", game.map.definition.map_id, " frames=", IDLE_FRAMES, " position_drift=", position_drift, " destination_drift=", destination_drift, " zoom_drift=", zoom_drift, " zoom_target_drift=", zoom_target_drift)


func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	settings = session.get_node("Settings")
	var original_map: String = session.block_war_map_id
	var original_size := root.size
	var original_camera_speed := settings.camera_speed
	var original_zoom_speed := settings.zoom_speed
	reference_mode = root.content_scale_mode
	reference_aspect = root.content_scale_aspect
	phase = "project setup"
	check(root.content_scale_size == REFERENCE_SIZE, "the project starts with its native 1600x900 canvas reference")
	for map_index: int in CATALOG.MAPS.size():
		var definition: Resource = CATALOG.MAPS[map_index]
		root.size = REFERENCE_SIZE
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
		viewport_sizes.clear()
		var started := Time.get_ticks_msec()
		_begin("entry")
		_observe("first battle frame")
		_finish()
		_speed_and_reversal_cases()
		_instant_focus_during_zoom()
		await _mixed_sequence(6292026 + map_index * 104729)
		await _window_restore()
		_idle_stability()
		print("CAMERA_STRESS_MAP map=", definition.map_id, " operations=", RANDOM_OPERATIONS, " reference=", root.content_scale_size, " viewport_sizes=", viewport_sizes, " samples=", observations, " checks=", checks, " failures=", failures.size(), " ms=", Time.get_ticks_msec() - started)
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		game = null
	settings.camera_speed = original_camera_speed
	settings.zoom_speed = original_zoom_speed
	session.block_war_map_id = original_map
	root.size = original_size
	print("BLOCK_WAR_CAMERA_STRESS checks=", checks, " samples=", observations, " idle_frames=", IDLE_FRAMES * CATALOG.MAPS.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
