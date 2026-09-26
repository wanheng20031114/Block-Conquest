extends Node3D
## Expanding whistle waves show the entire ground recall area, across all factions.
const DURATION := 1.8
var age := DURATION + 1.0
var running := true

func start(at: Vector3, radius: float, faction: int) -> void:
	position = at
	age = 0.0
	$Waves.scale = Vector3(radius, 1.0, radius)
	$Waves.material_override.set_shader_parameter("wave_color", WarMarches.FACTION_COLORS[faction])
	$Marker.show()
	$Waves.show()
	$Breath.restart()
	$Breath.emitting = true
	tick(0.0)

func tick(delta: float) -> void:
	if not running or age > DURATION:
		return
	age += delta
	var reveal := smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(1.2, 1.7, age))
	$Marker.scale = Vector3.ONE * (1.15 + sin(age * 17.0) * exp(-age * 5.0) * 0.15) * reveal
	$Marker.rotation.z = sin(age * 14.0) * exp(-age * 3.5) * 0.16
	$Marker/Flag.material.set_shader_parameter("visual_time", age)
	$Waves.material_override.set_shader_parameter("visual_time", age)
	$Marker.visible = age < 1.7
	$Waves.visible = age < DURATION

func reset() -> void:
	age = DURATION + 1.0
	$Marker.hide()
	$Waves.hide()
	$Breath.restart()
	$Breath.emitting = false

func set_running(value: bool) -> void:
	running = value
	$Breath.speed_scale = 1.0 if value else 0.0
