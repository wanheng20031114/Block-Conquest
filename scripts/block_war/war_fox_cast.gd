extends Node3D
## One scene-authored effect slot. Simulation time drives motion and pause.
var age := 10.0
var kind := 0
var impacted := false
var receiver := Vector3.ZERO
var active := false
var color := Color.WHITE
var roof_height := 0.0
var star_arrival := 0.8

func begin(index: int, at: Vector3, destination: Vector3, tint: Color, roof: float) -> void:
	kind = index
	age = 0.0
	impacted = false
	active = true
	position = at
	receiver = destination - at
	star_arrival = clampf(0.7 + receiver.length() * 0.018, 0.8, 1.65)
	color = tint
	roof_height = roof
	visible = true
	$Wave.mesh.material.set_shader_parameter("kind", kind)
	$Wave.mesh.material.set_shader_parameter("tint", Color("edb879") if kind != 3 else Color("e89a67"))
	$Flag/Cloth.mesh.material.set_shader_parameter("tint", tint)
	$Wave.scale = Vector3.ONE * (3.0 if index == 2 else 3.6)
	pose()

func advance(delta: float) -> void:
	if not active:
		return
	age += delta
	if age >= (star_arrival + 0.18 if kind == 1 else 1.1):
		active = false
		visible = false
		return
	pose()

func pose() -> void:
	var blast := maxf(0.0, age - 0.18)
	$Bomb.visible = kind == 0 and age < 0.18
	$Impact.visible = kind == 0 and age >= 0.18 and age < 0.46
	$Impact.position.y = roof_height + 0.5
	$Impact.scale = Vector3.ONE * lerpf(0.45, 2.15, 1.0 - pow(1.0 - clampf(blast / 0.28, 0.0, 1.0), 3.0))
	$Impact.mesh.material.set_shader_parameter("progress", clampf(blast / 0.28, 0.0, 1.0))
	# A contact-height pressure ring remains readable when the ground lies below a roof.
	$ImpactRing.visible = kind == 0 and age >= 0.18 and blast < 0.48
	$ImpactRing.position.y = roof_height + 0.32 + blast * 0.3
	var pressure := lerpf(0.65, 3.5, 1.0 - pow(1.0 - clampf(blast / 0.48, 0.0, 1.0), 2.0))
	$ImpactRing.scale = Vector3(pressure, 0.65, pressure)
	$ImpactRing.material_override.albedo_color.a = (1.0 - smoothstep(0.08, 0.48, blast)) * 0.75
	$Star.visible = kind == 1 and age < star_arrival + 0.12
	$Flag.visible = kind == 2 and age < 0.68
	$Alarm.visible = kind == 3 and age < 0.70
	$Wave.visible = kind != 1 and (kind != 0 or age >= 0.18)
	$Wave.mesh.material.set_shader_parameter("age", maxf(0.0, age - (0.18 if kind == 0 else 0.0)))
	$Flag/Cloth.mesh.material.set_shader_parameter("age", age)
	var rise := minf(1.0, age / 0.10)
	var fade := 1.0 - smoothstep(0.46, 0.70, age)
	if kind == 0:
		var drop := clampf(age / 0.18, 0.0, 1.0)
		$Bomb.position = Vector3(0, roof_height + lerpf(5.0, 0.65, drop * drop), 0)
		$Bomb.rotation = Vector3(-0.20, age * 1.8, -0.22 + drop * 0.42)
	elif kind == 1:
		# Give the stolen star a readable lift before its distance-scaled return arc.
		var travel := smoothstep(0.22, star_arrival, age)
		$Star.position = Vector3(0, roof_height + 1.1, 0).lerp(receiver + Vector3.UP * 5.0, travel) + Vector3.UP * sin(travel * PI) * 2.2
		$Star.rotation = Vector3(-0.4, sin(age * 8.0) * 0.45, age * 1.3)
		$Star.scale = Vector3.ONE * (0.65 + rise * 0.4) * (1.0 - smoothstep(star_arrival - 0.10, star_arrival + 0.12, age))
	elif kind == 2:
		$Flag.position.y = 0.3 + rise * 0.3
		$Flag.scale = Vector3.ONE * (0.75 + rise * 0.25) * maxf(0.001, fade)
	else:
		$Alarm.position.y = roof_height + 0.3 + rise * 0.8 + age * 0.6
		$Alarm.scale = Vector3.ONE * (0.8 + rise * 0.2) * maxf(0.001, fade)
		$Alarm.rotation.z = sin(age * 19.0) * 0.06 * fade
