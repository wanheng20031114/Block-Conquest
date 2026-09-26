extends Node3D
var age := 100.0

func start(at: Vector3) -> void:
	position = at + Vector3(2.3, 0, 2.1)
	age = 0.0
	$Marker.show()
	$Breath.restart()
	tick(0.0)

func tick(delta: float) -> void:
	if age > 1.6:
		return
	age += delta
	var reveal := lerpf(0.88, 1.0, smoothstep(0.0, 0.09, age)) * (1.0 - smoothstep(1.0, 1.5, age))
	$Marker.scale = Vector3.ONE * reveal
	$Marker.rotation.z = sin(age * 12.0) * exp(-age * 3.5) * 0.1
	$Marker/Flag.material.set_shader_parameter("visual_time", age)
	$Marker.visible = age < 1.5

func set_running(value: bool) -> void:
	$Breath.speed_scale = 1.0 if value else 0.0
