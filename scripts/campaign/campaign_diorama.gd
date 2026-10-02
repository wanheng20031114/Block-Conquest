extends SubViewportContainer
## All scenery is authored in PackedScenes; UI is projected from real landmarks.

@onready var camera: Camera3D = $World/Stage/CameraRig/Camera3D
@onready var landscape: Node3D = $World/Stage/Landscape
@onready var anchors: Array[Node] = $World/Stage/Landscape/StageAnchors.get_children()
@onready var world_route: Path3D = $World/Stage/Landscape/Journey

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
