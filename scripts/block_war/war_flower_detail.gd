extends Node3D
## Adapt native mesh LOD to an orthographic battle camera's zoom.
## Close views retain the tiny florets; overview views avoid drawing invisible grains.

var _flowers: Array[Node] = []
var _last_bias := -1.0

func _ready() -> void:
	_flowers = find_children("DetailedFlowers*", "MeshInstance3D", true, false)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return # Offline route authoring loads this same scene without a camera.
	var closeness := clampf((58.0 - camera.size) / 34.0, 0.0, 1.0) if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else 1.0
	var bias := snappedf(lerpf(1.0, 8.0, closeness * closeness), 0.25)
	if is_equal_approx(bias, _last_bias):
		return
	_last_bias = bias
	for flower: MeshInstance3D in _flowers:
		flower.lod_bias = bias
