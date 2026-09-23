extends Node3D
## A scene-authored native particle pool for short capture and ability bursts.

var _next: int = 0
var _light_remaining: float = 0.0
var _next_hit := 0
var _next_fire := 0
var _deaths: Array[Dictionary] = []

func _ready() -> void:
	$Casualties.multimesh.instance_count = 512
	$Casualties.multimesh.visible_instance_count = 0
	$Cannonballs.multimesh.instance_count = 64
	$Cannonballs.multimesh.visible_instance_count = 0

func hit(at: Vector3, direction: Vector3, muzzle: bool = false) -> void:
	var effect: Node3D = $Hits.get_child(_next_hit)
	_next_hit = (_next_hit + 1) % $Hits.get_child_count()
	effect.position = at
	effect.scale = Vector3.ONE * (0.55 if muzzle else 1.0)
	effect.get_node("Sparks").process_material.direction = direction
	effect.get_node("Sparks").restart()
	effect.get_node("Dust").restart()

func casualty(at: Vector3, heading: Vector3, faction: int, impulse: Vector3, burning: bool) -> void:
	var push := Vector3(impulse.x, 0, impulse.z).normalized()
	_deaths.append({"at": at, "heading": heading, "faction": faction, "impulse": push, "age": 0.0})
	if not burning:
		hit(at + Vector3(0, 0.6, 0), impulse)

func start_fire(at: Vector3, radius: float) -> void:
	var fire: WarFireWave = $FireWaves.get_child(_next_fire)
	_next_fire = (_next_fire + 1) % $FireWaves.get_child_count()
	fire.start(at, radius)

func has_fire() -> bool:
	for fire: WarFireWave in $FireWaves.get_children():
		if fire.age < WarFireWave.BURN_TIME:
			return true
	return false

func fire_step_limit() -> float:
	var step := INF
	for fire: WarFireWave in $FireWaves.get_children():
		for boundary: float in [WarFireWave.EXPANSION_TIME, WarFireWave.EMISSION_TIME, WarFireWave.BURN_TIME]:
			if fire.age < boundary:
				step = minf(step, boundary - fire.age)
	return step

func fire_segments(delta: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fire: WarFireWave in $FireWaves.get_children():
		if fire.age < WarFireWave.BURN_TIME:
			result.append(fire.segment(delta))
	return result

func render_projectiles(projectiles: Array[Dictionary]) -> void:
	var mesh: MultiMesh = $Cannonballs.multimesh
	for index: int in projectiles.size():
		mesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, projectiles[index].position))
	mesh.visible_instance_count = projectiles.size()

func _render_deaths() -> void:
	var mesh: MultiMesh = $Casualties.multimesh
	if _deaths.size() > mesh.instance_count:
		mesh.instance_count = maxi(_deaths.size(), mesh.instance_count * 2)
	for index: int in _deaths.size():
		var death := _deaths[index]
		var progress: float = death.age / 0.7
		var fall := smoothstep(0.0, 0.55, progress)
		var heading: Vector3 = death.heading
		var basis := Basis(Vector3.UP, atan2(-heading.x, -heading.z)) * Basis(Vector3.RIGHT, -fall * PI * 0.48)
		basis = basis.scaled(Vector3.ONE * WarMarches.MODEL_SCALE * (1.0 - 0.35 * progress))
		var at: Vector3 = death.at + death.impulse * 0.45 * fall + Vector3(0, 0.08, 0)
		mesh.set_instance_transform(index, Transform3D(basis, at))
		var color := WarMarches.FACTION_COLORS[death.faction].srgb_to_linear()
		color.a = progress
		mesh.set_instance_custom_data(index, color)
	mesh.visible_instance_count = _deaths.size()

func burst(at: Vector3, color: Color, impact: bool = false) -> void:
	var particles: GPUParticles3D = $Bursts.get_child(_next)
	_next = (_next + 1) % $Bursts.get_child_count()
	particles.position = at + Vector3(0, 0.5, 0)
	var material: ParticleProcessMaterial = particles.process_material
	material.color = color
	material.initial_velocity_min = 3.0 if impact else 1.1
	material.initial_velocity_max = 6.0 if impact else 2.8
	particles.restart()
	particles.emitting = true
	if impact:
		$ImpactLight.position = at + Vector3(0, 2.0, 0)
		$ImpactLight.light_energy = 3.5
		_light_remaining = 0.35

func shield(at: Vector3) -> void:
	$Shield.position = at + Vector3(0, 1.0, 0)
	$Shield.show()

func tick(delta: float, shield_active: bool) -> void:
	_light_remaining = maxf(0.0, _light_remaining - delta)
	$ImpactLight.light_energy = _light_remaining * 10.0
	$Shield.visible = shield_active
	for index: int in range(_deaths.size() - 1, -1, -1):
		_deaths[index].age += delta
		if _deaths[index].age >= 0.7:
			_deaths.remove_at(index)
	_render_deaths()
	for fire: WarFireWave in $FireWaves.get_children():
		fire.tick(delta)

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in $Bursts.get_children():
		particles.speed_scale = 1.0 if value else 0.0
	for effect: Node3D in $Hits.get_children():
		for particles: GPUParticles3D in effect.get_children():
			particles.speed_scale = 1.0 if value else 0.0
	for fire: WarFireWave in $FireWaves.get_children():
		fire.set_running(value)
