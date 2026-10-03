extends SubViewportContainer
## A perspective railway whose visible ground always stays inside the landscape.

signal intro_finished
signal view_changed
signal train_arrived(index: int)

# The imported heightfield is solid down to the river bed, including the tunnels.
# Reference: tools/railway_reference/src/config.js and world.js.
const MAP_BOUNDS := Rect2(-40.0, 0.0, 168.0, 40.0)
const GROUND_HEIGHT := 5.0
const GROUND_PLANE := Plane(Vector3.UP, GROUND_HEIGHT)
const EDGE_INSET := 0.25
# Keeps the camera above the highest terrain (34) even when fully zoomed in.
const MIN_DISTANCE := 37.0
const TRAIN_TRAVEL_SPEED := 8.0

@onready var camera: Camera3D = $World/Stage/CameraRig/Camera3D
@onready var camera_rig: Node3D = $World/Stage/CameraRig
@onready var landscape: Node3D = $World/Stage/Landscape
@onready var anchors: Array[Node] = $World/Stage/Landscape/StageAnchors.get_children()
@onready var parking_anchors: Array[Node] = $World/Stage/Landscape/ParkAnchors.get_children()
@onready var world_route: Path3D = $World/Stage/Landscape/Journey
@onready var train: PathFollow3D = $World/Stage/Landscape/Journey/Train
@onready var tender: PathFollow3D = $World/Stage/Landscape/Journey/Tender
@onready var coach: PathFollow3D = $World/Stage/Landscape/Journey/Coach
var intro_running := true
var overview := true
var _view_tween: Tween
var train_moving := false
var parked_station := -1
var _train_tween: Tween

func _ready() -> void:
	# A moving ground plane would expose the world edges during entry. The screen
	# transition provides the entrance, with the complete landscape already in place.
	var entrance: AnimationPlayer = $World/Stage/Landscape/Entrance
	entrance.play(&"unfold")
	entrance.seek(entrance.get_animation(&"unfold").length, true)
	entrance.pause()
	$World.size_changed.connect(_viewport_resized)
	_begin_after_transition.call_deferred()

func _begin_after_transition() -> void:
	var transition: UITransition = get_node("/root/Session/Transition")
	if transition.busy:
		transition.completed.connect(skip_intro, CONNECT_ONE_SHOT)
	else:
		skip_intro()

func skip_intro() -> void:
	if not intro_running:
		return
	intro_running = false
	view_changed.emit()
	intro_finished.emit()

func stage_position(index: int) -> Vector2:
	return camera.unproject_position(anchors[index].global_position)

func projected_route() -> Curve2D:
	var result := Curve2D.new()
	result.bake_interval = 1.0
	for index: int in world_route.curve.point_count:
		var point := world_route.to_global(world_route.curve.get_point_position(index))
		result.add_point(camera.unproject_position(point))
	return result

func park_train(index: int) -> void:
	if _train_tween and _train_tween.is_valid():
		_train_tween.kill()
	train_moving = false
	parked_station = index
	_set_train_progress(_station_progress(index))

func _station_progress(index: int) -> float:
	return world_route.curve.get_closest_offset(world_route.to_local(parking_anchors[index].global_position))

func _set_train_progress(offset: float) -> void:
	for carriage: PathFollow3D in world_route.get_children():
		carriage.progress = maxf(0.0, offset - float(carriage.get_meta(&"rail_offset")))

func travel_to_station(index: int) -> void:
	_stop_view_tween()
	var departure := train.progress
	var destination := _station_progress(index)
	# Follow the actual curved railway, preserving the station framing at both
	# ends instead of jumping the camera to the destination ahead of the train.
	var stage: Node3D = camera_rig.get_parent_node_3d()
	var from_offset := camera_rig.position - stage.to_local(train.global_position)
	var to_offset := stage.to_local(anchors[index].global_position) - stage.to_local(parking_anchors[index].global_position)
	train_moving = true
	parked_station = -1
	_train_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_train_tween.tween_method(func(weight: float):
		_set_train_progress(lerpf(departure, destination, weight))
		camera_rig.position = stage.to_local(train.global_position) + from_offset.lerp(to_offset, weight)
		_constrain_view()
		view_changed.emit()
	, 0.0, 1.0, maxf((destination - departure) / TRAIN_TRAVEL_SPEED, 3.0))
	_train_tween.tween_callback(func():
		train_moving = false
		parked_station = index
		train_arrived.emit(index)
	)

func ground_footprint(distance: float = -1.0) -> Rect2:
	# Native projection includes the live SubViewport aspect ratio. With the rig
	# on the ground plane, this footprint scales linearly with camera distance.
	camera.force_update_transform()
	var viewport_size := Vector2($World.size)
	var offset := Vector3.ZERO
	if distance >= 0.0:
		offset = camera.global_basis.z * (distance - camera.position.z)
	var bounds := Rect2()
	var first := true
	for screen_point: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var origin := camera.project_ray_origin(screen_point) + offset
		var intersection: Vector3 = GROUND_PLANE.intersects_ray(origin, camera.project_ray_normal(screen_point))
		var point := Vector2(intersection.x, intersection.z)
		if first:
			bounds = Rect2(point, Vector2.ZERO)
			first = false
		else:
			bounds = bounds.expand(point)
	return bounds

func maximum_distance() -> float:
	var unit_footprint := ground_footprint(1.0).size
	var available := MAP_BOUNDS.grow(-EDGE_INSET).size
	return minf(available.x / unit_footprint.x, available.y / unit_footprint.y)

func _constrain_view() -> void:
	# Keep the projection plane invariant, including after large floating-point
	# pointer deltas or callers supplying a focus point above the ground.
	camera_rig.position.y = GROUND_HEIGHT
	var limit := maximum_distance()
	camera.position.z = clampf(camera.position.z, minf(MIN_DISTANCE, limit), limit)
	var footprint := ground_footprint()
	var available := MAP_BOUNDS.grow(-EDGE_INSET)
	var center := Vector2(camera_rig.position.x, camera_rig.position.z)
	var low := available.position - (footprint.position - center)
	var high := available.end - (footprint.end - center)
	# Roundoff can invert an interval by a few microunits at the exact zoom limit.
	center.x = clampf(center.x, low.x, maxf(low.x, high.x))
	center.y = clampf(center.y, low.y, maxf(low.y, high.y))
	camera_rig.position = Vector3(center.x, GROUND_HEIGHT, center.y)
	camera.force_update_transform()

func focus_station(index: int, animated: bool = true) -> void:
	overview = true
	var station: Vector3 = anchors[index].position
	_set_view(Vector3(station.x, GROUND_HEIGHT, station.z), maximum_distance(), animated)

func show_overview(animated: bool = true) -> void:
	overview = true
	_set_view(camera_rig.position, maximum_distance(), animated)

func pan_view(delta_pixels: Vector2) -> void:
	_stop_view_tween()
	# Measure the two screen axes on the native ground plane. The finite one-pixel
	# rays also keep large drag events from reaching beyond the camera's horizon.
	var middle := Vector2($World.size) * 0.5
	var from: Vector3 = GROUND_PLANE.intersects_ray(camera.project_ray_origin(middle), camera.project_ray_normal(middle))
	var right: Vector3 = GROUND_PLANE.intersects_ray(camera.project_ray_origin(middle + Vector2.RIGHT), camera.project_ray_normal(middle + Vector2.RIGHT))
	var down: Vector3 = GROUND_PLANE.intersects_ray(camera.project_ray_origin(middle + Vector2.DOWN), camera.project_ray_normal(middle + Vector2.DOWN))
	camera_rig.position += (from - right) * delta_pixels.x + (from - down) * delta_pixels.y
	_constrain_view()
	view_changed.emit()

func zoom_view(wheel_steps: float) -> void:
	_stop_view_tween()
	var limit := maximum_distance()
	camera.position.z = clampf(camera.position.z * exp(clampf(wheel_steps, -100.0, 100.0) * 0.12), minf(MIN_DISTANCE, limit), limit)
	_constrain_view()
	overview = is_equal_approx(camera.position.z, maximum_distance())
	view_changed.emit()

func _set_view(target: Vector3, distance: float, animated: bool) -> void:
	_stop_view_tween()
	target.y = GROUND_HEIGHT
	if not animated:
		camera_rig.position = target
		camera.position.z = distance
		_constrain_view()
		view_changed.emit()
		return
	var start := camera_rig.position
	var start_distance := camera.position.z
	_view_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_view_tween.tween_method(func(weight: float):
		camera_rig.position = start.lerp(target, weight)
		camera.position.z = lerpf(start_distance, distance, weight)
		_constrain_view()
		view_changed.emit()
	, 0.0, 1.0, 0.65)

func _viewport_resized() -> void:
	_stop_view_tween()
	if overview:
		camera.position.z = maximum_distance()
	_constrain_view()
	view_changed.emit()

func _stop_view_tween() -> void:
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()

func set_ambient(active: bool) -> void:
	$World.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED
	$World/Stage/Landscape/Journey/Train/Model/Steam.emitting = active
	if active:
		$World/Stage/Landscape/Ambient.play()
	else:
		$World/Stage/Landscape/Ambient.pause()
	if _view_tween and _view_tween.is_valid():
		if active:
			_view_tween.play()
		else:
			_view_tween.pause()
	if _train_tween and _train_tween.is_valid():
		if active:
			_train_tween.play()
		else:
			_train_tween.pause()
