extends SceneTree
## A plain native receiver distinguishes genuine light leaks from meadow color.
## Every sample follows the sun ray through a closed cloud's solid core.

const FIXTURE := "res://tests/block_war_cloud_projection.tscn"
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const MIN_CORE_OCCLUSION := 0.72
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _copy_scene_properties(path: NodePath, target: Node) -> void:
	var state := BATTLE.get_state()
	var copied := 0
	for node_index: int in state.get_node_count():
		if state.get_node_path(node_index) != path:
			continue
		for property_index: int in state.get_node_property_count(node_index):
			target.set(state.get_node_property_name(node_index, property_index),
				state.get_node_property_value(node_index, property_index))
			copied += 1
	_check(copied > 0, "Fixture inherits authored battle properties for " + str(path))

func _capture(path: String) -> Image:
	for frame: int in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(path) == OK, "Projection screenshot saves")
	return image

func _brightness(image: Image, point: Vector2i) -> float:
	var sum := 0.0
	for y: int in range(point.y - 2, point.y + 3):
		for x: int in range(point.x - 2, point.x + 3):
			var color := image.get_pixel(x, y)
			sum += (color.r + color.g + color.b) / 3.0
	return sum / 25.0

func _projected_cores(clouds: Node3D, sun: DirectionalLight3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var direction := -sun.global_basis.z
	for cloud: Node3D in clouds.get_node("Drift").get_children():
		var center: Vector3 = cloud.get_node("Core").global_position
		result.append(center + direction * (-center.y / direction.y))
	return result

func _nearest_projected_core(clouds: Node3D, sun: DirectionalLight3D, focus: Vector3) -> Vector3:
	# Turning sunlight moves high cloud shadows. Anchor close-up pans to a
	# real core using geometry alone, never the measured shadow brightness.
	var closest := Vector3.INF
	var distance := INF
	for projected: Vector3 in _projected_cores(clouds, sun):
		var candidate := projected.distance_squared_to(focus)
		if candidate < distance:
			distance = candidate
			closest = projected
	_check(closest.is_finite(), "A real cloud core anchors each close-up pan")
	_check(signf(closest.x) == signf(focus.x), "Close-up pans stay on opposite sides")
	_check(absf(closest.x) < 140.0 and absf(closest.z) < 140.0, "Close-up pans fit inside the receiver")
	return closest

func _core_pixels(clouds: Node3D, sun: DirectionalLight3D, camera: Camera3D) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var frame := Rect2(Vector2(12, 12), Vector2(root.size) - Vector2(24, 24))
	for projected: Vector3 in _projected_cores(clouds, sun):
		# Canvas stretch keeps the camera's logical coordinates at the project
		# viewport size even when the captured window image uses fewer pixels.
		var screen := camera.unproject_position(projected) * Vector2(root.size) / root.get_visible_rect().size
		if not camera.is_position_behind(projected) and frame.has_point(screen):
			result.append(Vector2i(screen))
	return result

func _measure(clear: Image, hard: Image, soft: Image, centers: Array[Vector2i]) -> Dictionary:
	var minimum := 1.0
	var holes := 0
	for center: Vector2i in centers:
		var lit := _brightness(clear, center)
		var contrast := lit - _brightness(hard, center)
		_check(contrast > 0.06, "The analytically projected cloud core is covered in the hard-shadow control")
		var occlusion := (lit - _brightness(soft, center)) / contrast
		minimum = minf(minimum, occlusion)
		if occlusion < MIN_CORE_OCCLUSION:
			holes += 1
	return {"minimum_core_occlusion": minimum, "hollow_cores": holes, "samples": centers.size()}

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	var output := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var ignore := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	change_scene_to_file(FIXTURE)
	await scene_changed
	var fixture := current_scene
	var sun: DirectionalLight3D = fixture.get_node("Sun")
	var camera: Camera3D = fixture.get_node("Camera3D")
	var clouds: Node3D = fixture.get_node("CloudShadows")
	_copy_scene_properties(NodePath("./Sun"), sun)
	_copy_scene_properties(NodePath("./CameraRig/Camera3D"), camera)
	if failures:
		quit(1)
		return
	var original_camera_position := camera.position
	var production_angle := sun.light_angular_distance
	var production_pancake := sun.directional_shadow_pancake_size
	_check(production_angle > 0.0, "The regression exercises the production PCSS path")
	var animation: AnimationPlayer = clouds.get_node("AnimationPlayer")
	animation.speed_scale = 0.0
	animation.seek(0.0, true)
	var cases := [
		{"name": "near", "zoom": 24.0, "focus": Vector3.ZERO},
		{"name": "normal", "zoom": 67.0, "focus": Vector3.ZERO},
		{"name": "far", "zoom": 95.0, "focus": Vector3.ZERO},
		{"name": "near-left", "zoom": 24.0, "focus": _nearest_projected_core(clouds, sun, Vector3(-40, 0, -8))},
		{"name": "near-right", "zoom": 24.0, "focus": _nearest_projected_core(clouds, sun, Vector3(40, 0, 16))},
	]
	if failures:
		quit(1)
		return
	var legacy_hollow_cores := 0
	for view: Dictionary in cases:
		camera.size = view.zoom
		camera.position = original_camera_position + view.focus
		sun.directional_shadow_pancake_size = production_pancake
		sun.light_angular_distance = production_angle
		clouds.hide()
		var clear := await _capture(output.path_join(view.name + "-clear.png"))
		clouds.show()
		sun.light_angular_distance = 0.0
		var hard := await _capture(output.path_join(view.name + "-hard.png"))
		sun.light_angular_distance = production_angle
		var soft := await _capture(output.path_join(view.name + "-production.png"))
		var centers := _core_pixels(clouds, sun, camera)
		_check(not centers.is_empty(), "Each zoom/pan includes a projected solid cloud core")
		var production := _measure(clear, hard, soft, centers)
		_check(production.hollow_cores == 0, "Production cloud cores remain filled at " + view.name)
		sun.directional_shadow_pancake_size = 20.0
		var legacy := await _capture(output.path_join(view.name + "-legacy20.png"))
		var legacy_metrics := _measure(clear, hard, legacy, centers)
		legacy_hollow_cores += legacy_metrics.hollow_cores
		print("CLOUD_PROJECTION_METRICS ", view.name, " production=", production, " legacy20=", legacy_metrics)
	_check(legacy_hollow_cores > 0, "The former pancake depth reproduces the actual hollow-cloud regression")
	print("CLOUD_PROJECTION_COMPLETE checks=", checks, " failures=", failures, " legacy_hollow_cores=", legacy_hollow_cores)
	quit(1 if failures else 0)
