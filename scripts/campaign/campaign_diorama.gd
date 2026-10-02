extends SubViewportContainer
## All scenery is authored in PackedScenes; UI is projected from real landmarks.

signal intro_finished

@onready var camera: Camera3D = $World/Stage/CameraRig/Camera3D
@onready var landscape: Node3D = $World/Stage/Landscape
@onready var anchors: Array[Node] = $World/Stage/Landscape/StageAnchors.get_children()
@onready var world_route: Path3D = $World/Stage/Landscape/Journey
@onready var entrance: AnimationPlayer = $World/Stage/Landscape/Entrance
@onready var camera_motion: AnimationPlayer = $CameraMotion
var intro_running := true
var _started := false

func _ready() -> void:
	# Apply the authored flat pose before the first render, then wait until the
	# shared scene curtain has uncovered the map. No runtime model construction.
	for player: AnimationPlayer in [entrance, camera_motion]:
		player.play(&"unfold")
		player.advance(0.0)
		player.pause()
	entrance.animation_finished.connect(_finish_intro)
	_begin_after_transition.call_deferred()

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
	# Set the final camera pose before callers reproject the stage markers.
	camera_motion.seek(camera_motion.get_animation(&"unfold").length, true)
	camera_motion.pause()
	intro_running = false
	intro_finished.emit()

func stage_position(index: int) -> Vector2:
	return camera.unproject_position(anchors[index].global_position)

func projected_route() -> Curve2D:
	var result := Curve2D.new()
	result.bake_interval = 1.0
	# Preserve authored vertices, including the exact six anchors on the trail.
	for index: int in world_route.curve.point_count:
		var point := world_route.to_global(world_route.curve.get_point_position(index))
		result.add_point(camera.unproject_position(point))
	return result

func set_ambient(active: bool) -> void:
	# Freezing the viewport also freezes shader-driven flags, leaves and water.
	$World.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if active else SubViewport.UPDATE_DISABLED
	if intro_running and _started:
		for player: AnimationPlayer in [entrance, camera_motion]:
			if active:
				player.play()
			else:
				player.pause()
