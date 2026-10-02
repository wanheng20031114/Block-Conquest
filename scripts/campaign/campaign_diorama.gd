extends SubViewportContainer
## Reference-scale scenery and a native perspective camera for exploring it.

signal intro_finished
signal view_changed

const STATION_DISTANCE := 70.0
const OVERVIEW_DISTANCE := 202.0
const MIN_DISTANCE := 30.0
const MAX_DISTANCE := 220.0
const PITCH := 1.0

@onready var camera: Camera3D = $World/Stage/CameraRig/Camera3D
@onready var camera_rig: Node3D = $World/Stage/CameraRig
@onready var landscape: Node3D = $World/Stage/Landscape
@onready var anchors: Array[Node] = $World/Stage/Landscape/StageAnchors.get_children()
@onready var parking_anchors: Array[Node] = $World/Stage/Landscape/ParkAnchors.get_children()
@onready var world_route: Path3D = $World/Stage/Landscape/Journey
@onready var entrance: AnimationPlayer = $World/Stage/Landscape/Entrance
@onready var camera_motion: AnimationPlayer = $CameraMotion
@onready var train: PathFollow3D = $World/Stage/Landscape/Journey/Train
@onready var tender: PathFollow3D = $World/Stage/Landscape/Journey/Tender
@onready var coach: PathFollow3D = $World/Stage/Landscape/Journey/Coach
var intro_running := true
var overview := false
var _started := false
var _active := true
var _view_tween: Tween

func _ready() -> void:
	var current: int = get_node("/root/Session").campaign_current_stage()
	park_train(current)
	focus_station(current, false)
	for player: AnimationPlayer in [entrance, camera_motion]:
		player.play(&"unfold")
		player.advance(0.0)
		player.pause()
	entrance.animation_finished.connect(_finish_intro)
	_begin_after_transition.call_deferred()

func _process(_delta: float) -> void:
	if _active and (intro_running or (_view_tween and _view_tween.is_running())):
		view_changed.emit()

func _begin_after_transition() -> void:
	var transition: UITransition = get_node("/root/Session/Transition")
	if transition.busy:
		transition.completed.connect(_start_intro, CONNECT_ONE_SHOT)
	else:
		_start_intro()

func _start_intro() -> void:
	if not intro_running:
		return
	_started = true
	entrance.play()
	camera_motion.play()

func skip_intro() -> void:
	if not intro_running:
		return
	for player: AnimationPlayer in [entrance, camera_motion]:
		player.seek(player.get_animation(&"unfold").length, true)
		player.pause()
	_finish_intro(&"unfold")

func _finish_intro(_animation: StringName) -> void:
	if not intro_running:
		return
	camera_motion.seek(camera_motion.get_animation(&"unfold").length, true)
	camera_motion.pause()
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
	var offset := world_route.curve.get_closest_offset(world_route.to_local(parking_anchors[index].global_position))
	for carriage: PathFollow3D in world_route.get_children():
		carriage.progress = maxf(0.0, offset - float(carriage.get_meta(&"rail_offset")))

func focus_station(index: int, animated: bool = true) -> void:
	var station: Vector3 = anchors[index].position
	overview = false
	_set_view(Vector3(clampf(station.x - 2.0, -14.0, 112.0), station.y + 3.0, clampf(station.z, 12.0, 30.0)), STATION_DISTANCE, animated)

func show_overview(animated: bool = true) -> void:
	overview = true
	_set_view(Vector3(44.0, 10.0, 21.0), OVERVIEW_DISTANCE, animated)

func pan_view(delta_pixels: Vector2) -> void:
	_stop_view_tween()
	overview = false
	var units_per_pixel := 2.0 * camera.position.z * tan(deg_to_rad(camera.fov * 0.5)) / 900.0
	camera_rig.position.x = clampf(camera_rig.position.x - delta_pixels.x * units_per_pixel, -32.0, 120.0)
	camera_rig.position.z = clampf(camera_rig.position.z - delta_pixels.y * units_per_pixel / sin(PITCH), 4.0, 38.0)
	view_changed.emit()

func zoom_view(wheel_steps: float) -> void:
	_stop_view_tween()
	overview = false
	camera.position.z = clampf(camera.position.z * exp(wheel_steps * 0.12), MIN_DISTANCE, MAX_DISTANCE)
	view_changed.emit()

func _set_view(target: Vector3, distance: float, animated: bool) -> void:
	_stop_view_tween()
	if not animated:
		camera_rig.position = target
		camera.position.z = distance
		view_changed.emit()
		return
	_view_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_view_tween.tween_property(camera_rig, "position", target, 0.65)
	_view_tween.tween_property(camera, "position:z", distance, 0.65)
	_view_tween.chain().tween_callback(func(): view_changed.emit())

func _stop_view_tween() -> void:
	if _view_tween and _view_tween.is_valid():
		_view_tween.kill()

func set_ambient(active: bool) -> void:
	_active = active
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
	if intro_running and _started:
		for player: AnimationPlayer in [entrance, camera_motion]:
			if active:
				player.play()
			else:
				player.pause()
