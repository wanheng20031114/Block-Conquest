extends Node3D
## A scene-authored native particle pool for short capture and ability bursts.

var _next: int = 0
var _light_remaining: float = 0.0
var _next_hit := 0
var _next_fire := 0
var _deaths: Array[Dictionary] = []
var _skill_time := 0.0
var _skill_emission := 0.0
var _wind_offset := 0
var _mote_serial := 0
const EMIT_FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR

func _ready() -> void:
	$Shield.multimesh.instance_count = 6
	$RecruitRings.multimesh.instance_count = 6
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

func start_fire(at: Vector3, radius: float, faction: int = 0) -> void:
	var fire: WarFireWave = $FireWaves.get_child(_next_fire)
	_next_fire = (_next_fire + 1) % $FireWaves.get_child_count()
	fire.start(at, radius, faction)

func has_fire() -> bool:
	for fire: WarFireWave in $FireWaves.get_children():
		if fire.age < WarFireWave.BURN_TIME:
			return true
	return false

func fire_step_limit() -> float:
	var step := INF
	for fire: WarFireWave in $FireWaves.get_children():
		for boundary: float in [0.0, WarFireWave.EXPANSION_TIME, WarFireWave.EMISSION_TIME, WarFireWave.BURN_TIME]:
			if fire.age < boundary:
				step = minf(step, boundary - fire.age)
	return step

func fire_segments(delta: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fire: WarFireWave in $FireWaves.get_children():
		if fire.age >= 0.0 and fire.age < WarFireWave.BURN_TIME:
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

func tick(delta: float) -> void:
	_light_remaining = maxf(0.0, _light_remaining - delta)
	$ImpactLight.light_energy = _light_remaining * 10.0
	for index: int in range(_deaths.size() - 1, -1, -1):
		_deaths[index].age += delta
		if _deaths[index].age >= 0.7:
			_deaths.remove_at(index)
	_render_deaths()
	for fire: WarFireWave in $FireWaves.get_children():
		fire.tick(delta)

func update_skills(delta: float, states: Array, shields: Dictionary, by_id: Dictionary, marches: WarMarches) -> void:
	_skill_time += delta
	_skill_emission += delta
	var emit := _skill_emission >= 0.12
	if emit:
		_skill_emission = fmod(_skill_emission, 0.12)
	var rings: MultiMesh = $RecruitRings.multimesh
	var walls: MultiMesh = $Shield.multimesh
	rings.mesh.material.set_shader_parameter("visual_time", _skill_time)
	walls.mesh.material.set_shader_parameter("visual_time", _skill_time)
	var count := 0
	for state: RefCounted in states:
		if state.recruit_target_id < 0:
			continue
		var building: WarBuilding = by_id[state.recruit_target_id]
		var color: Color = WarMarches.FACTION_COLORS[building.faction]
		rings.set_instance_transform(count, Transform3D(Basis.IDENTITY, building.global_position + Vector3(0, 0.07, 0)))
		rings.set_instance_custom_data(count, Color(color, state.durations[0] / 6.0))
		count += 1
		if emit:
			for mote: int in 4:
				_mote_serial += 1
				var angle := _mote_serial * 2.399963
				var radial := Vector3(cos(angle), 0, sin(angle))
				var at := building.global_position + radial * (2.5 + 0.35 * sin(angle * 3.0)) + Vector3(0, 0.3, 0)
				var basis := Basis(Vector3.UP, angle) * Basis(Vector3.FORWARD, sin(angle) * 0.6)
				$RecruitMotes.emit_particle(Transform3D(basis, at), -radial * 0.22 + Vector3(0, 1.1 + sin(angle) * 0.3, 0), Color("b48b35").srgb_to_linear(), Color(), EMIT_FLAGS)
	rings.visible_instance_count = count
	count = 0
	for id: int in shields:
		var building: WarBuilding = by_id[id]
		var color: Color = WarMarches.FACTION_COLORS[building.faction]
		walls.set_instance_transform(count, Transform3D(Basis.IDENTITY, building.global_position + Vector3(0, 1.3, 0)))
		walls.set_instance_custom_data(count, Color(color, shields[id] / 10.0))
		count += 1
		if emit:
			for mote: int in 3:
				_mote_serial += 1
				var angle := _mote_serial * 2.399963
				var at := building.global_position + Vector3(cos(angle) * 3.17, 0.15, sin(angle) * 3.17)
				$ShieldMotes.emit_particle(Transform3D(Basis.IDENTITY, at), Vector3(0, 1.4, 0), Color("a2c6b9").srgb_to_linear(), Color(), EMIT_FLAGS)
	walls.visible_instance_count = count
	if emit:
		var active: Array[WarMarches.MarchUnit] = []
		for unit: WarMarches.MarchUnit in marches._units:
			if unit.distance >= 0.0 and states[unit.order.faction].durations[1] > 0.0:
				active.append(unit)
		if not active.is_empty():
			for index: int in mini(48, active.size()):
				var unit := active[(_wind_offset + index) % active.size()]
				var basis := Basis.looking_at(unit.heading)
				var at := unit.position + Vector3(0, 0.13, 0) - unit.heading * 0.4
				$HasteTrails.emit_particle(Transform3D(basis, at), -unit.heading * 1.4, Color("e0e8d1"), Color(), EMIT_FLAGS)
			_wind_offset = (_wind_offset + 48) % active.size()

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in [$RecruitMotes, $ShieldMotes, $HasteTrails]:
		particles.speed_scale = 1.0 if value else 0.0
	for particles: GPUParticles3D in $Bursts.get_children():
		particles.speed_scale = 1.0 if value else 0.0
	for effect: Node3D in $Hits.get_children():
		for particles: GPUParticles3D in effect.get_children():
			particles.speed_scale = 1.0 if value else 0.0
	for fire: WarFireWave in $FireWaves.get_children():
		fire.set_running(value)
