extends Node3D
## A scene-authored native particle pool for short capture and ability bursts.

const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")

var _next: int = 0
var _light_remaining: float = 0.0
var _next_hit := 0
var _deaths: Array[Dictionary] = []
var _skill_time := 0.0
var _skill_emission := 0.0
var _wind_offset := 0
var _mote_serial := 0
var map_definition := WarMapDefinition.new()
const EMIT_FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	$BlastCasualties.map_definition = definition
	WarSurfaceEffects.configure($RecruitRings.multimesh.mesh.material, definition)
	WarSurfaceEffects.configure($HasteFields.multimesh.mesh.material, definition)
	$Rabbit.configure_surface(definition)
	$Frog.configure_surface(definition)
	$Bear.configure_surface(definition)
	$Fox.configure_surface(definition)
	$PigEffects.configure_surface(definition)
	for fire: WarFireWave in $FireWaves.get_children():
		fire.configure_surface(definition)

func _ready() -> void:
	$Shield.multimesh.instance_count = 6
	$RecruitRings.multimesh.instance_count = 6
	$HasteFields.multimesh.instance_count = 6
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
	if not burning and impulse.y > 0.4:
		$BlastCasualties.soldier(at, heading, faction, impulse)
		return
	var push := Vector3(impulse.x, 0, impulse.z).normalized()
	_deaths.append({"at": at, "heading": heading, "faction": faction, "impulse": push, "age": 0.0})
	if not burning:
		hit(at + Vector3(0, 0.6, 0), impulse)

func garrison_blast(building: WarBuilding, loss: float, delay: float = 0.0) -> void:
	# A bounded sample communicates garrison losses without creating live troops
	# or publishing the building's hidden population to the other client.
	if floori(loss + 0.000001) <= 0: return
	# Even a capped exact sample leaks low enemy garrisons through percentage
	# skills. Owned buildings therefore use a fixed, illustrative visual burst.
	var count: int = $BlastCasualties.FACTION_BURST if building.faction >= 0 else mini($BlastCasualties.MAX_BURST, floori(loss + 0.000001))
	var at := building.global_position + Vector3.UP * (1.2 + building.level * 0.2)
	$BlastCasualties.burst(at, building.faction, count, delay)
	get_parent().presentation_event.emit("garrison_blast", {"at": [at.x, at.y, at.z], "faction": building.faction, "count": count, "delay": delay})

func start_fire(at: Vector3, radius: float, faction: int = 0) -> RefCounted:
	# Compatibility for existing skill fixtures; the match owns the rule state.
	return get_parent().start_fire(at, radius, faction)

func sync_fire_states(states: Array) -> void:
	# A reused visual slot must never erase an active hazard. Select its latest
	# stable effect id, while the independent rule array retains every fire.
	var slots: Dictionary[int, RefCounted] = {}
	for state: RefCounted in states:
		var slot: int = (int(state.effect_id) - 1) % $FireWaves.get_child_count()
		if not slots.has(slot) or int(slots[slot].effect_id) < int(state.effect_id):
			slots[slot] = state
	for slot: int in $FireWaves.get_child_count():
		var visual: WarFireWave = $FireWaves.get_child(slot)
		if slots.has(slot):
			visual.sync_state(slots[slot])
		else:
			visual.clear_visual()

func has_fire() -> bool:
	for fire: RefCounted in get_parent().fire_states:
		if fire.age < WarFireWave.BURN_TIME:
			return true
	return false

func fire_step_limit() -> float:
	var step := INF
	for fire: RefCounted in get_parent().fire_states:
		for boundary: float in [WarFireWave.EXPANSION_TIME, WarFireWave.EMISSION_TIME, WarFireWave.BURN_TIME]:
			if fire.age < boundary:
				step = minf(step, boundary - fire.age)
	return step

func fire_segments(delta: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fire: RefCounted in get_parent().fire_states:
		if fire.age < WarFireWave.BURN_TIME:
			result.append(fire.segment(delta))
	return result

func render_projectiles(projectiles: Array[Dictionary]) -> void:
	var mesh: MultiMesh = $Cannonballs.multimesh
	if projectiles.size() > mesh.instance_count:
		mesh.instance_count = maxi(projectiles.size(), mesh.instance_count * 2)
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
		var at := WarSurfaceEffects.offset_point(map_definition, death.at, death.impulse * 0.45 * fall + Vector3(0, 0.08, 0))
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
	$BlastCasualties.tick(delta)
	$Rabbit.tick(delta)
	$PigEffects.tick(delta)
	_light_remaining = maxf(0.0, _light_remaining - delta)
	$ImpactLight.light_energy = _light_remaining * 10.0
	for index: int in range(_deaths.size() - 1, -1, -1):
		_deaths[index].age += delta
		if _deaths[index].age >= 0.7:
			_deaths.remove_at(index)
	_render_deaths()
	sync_fire_states(get_parent().fire_states)

func update_skills(delta: float, states: Array, shields: Dictionary, by_id: Dictionary, marches: WarMarches) -> void:
	$PigEffects.update_units(delta, marches)
	$Fox.advance(delta)
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
		if building.disruption_remaining > 0.0:
			continue
		var color: Color = WarMarches.FACTION_COLORS[building.faction]
		rings.set_instance_transform(count, Transform3D(Basis.IDENTITY, building.global_position + Vector3(0, 0.07, 0)))
		rings.set_instance_custom_data(count, Color(color, state.durations[0] / SKILL_RULES.DURATIONS[0]))
		count += 1
		if emit:
			for mote: int in 4:
				_mote_serial += 1
				var angle := _mote_serial * 2.399963
				var radial := Vector3(cos(angle), 0, sin(angle))
				var at := WarSurfaceEffects.offset_point(map_definition, building.global_position, radial * (2.5 + 0.35 * sin(angle * 3.0)) + Vector3(0, 0.3, 0))
				var basis := Basis(Vector3.UP, angle) * Basis(Vector3.FORWARD, sin(angle) * 0.6)
				$RecruitMotes.emit_particle(Transform3D(basis, at), -radial * 0.22 + Vector3(0, 1.1 + sin(angle) * 0.3, 0), Color("b48b35").srgb_to_linear(), Color(), EMIT_FLAGS)
	rings.visible_instance_count = count
	count = 0
	for id: int in shields:
		var building: WarBuilding = by_id[id]
		var age := maxf(0.0, SKILL_RULES.DURATIONS[2] - float(shields[id]))
		walls.set_instance_transform(count, Transform3D(Basis.IDENTITY, building.global_position + Vector3(0, 1.0, 0)))
		# Each building's sweep follows its own simulation age, including pause.
		walls.set_instance_custom_data(count, Color(age, 0.0, 0.0, shields[id] / SKILL_RULES.DURATIONS[2]))
		count += 1
		if emit and age >= 0.34:
			for mote: int in 3:
				_mote_serial += 1
				var angle := _mote_serial * 2.399963
				var at := WarSurfaceEffects.offset_point(map_definition, building.global_position, Vector3(cos(angle) * 3.17, 0.15, sin(angle) * 3.17))
				$ShieldMotes.emit_particle(Transform3D(Basis.IDENTITY, at), Vector3(0, 1.4, 0), Color("a2c6b9").srgb_to_linear(), Color(), EMIT_FLAGS)
	walls.visible_instance_count = count
	var fields: MultiMesh = $HasteFields.multimesh
	fields.mesh.material.set_shader_parameter("visual_time", _skill_time)
	count = 0
	for faction: int in marches.haste_zones:
		var zone: Dictionary = marches.haste_zones[faction]
		if zone.style == SKILL_RULES.RABBIT:
			continue
		fields.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * zone.radius), zone.at + Vector3(0, 0.08, 0)))
		fields.set_instance_custom_data(count, Color(WarMarches.FACTION_COLORS[faction], zone.remaining / zone.duration))
		count += 1
		if emit:
			for mote: int in 3:
				_mote_serial += 1
				var angle := _mote_serial * 2.399963
				var radial := Vector3(cos(angle), 0, sin(angle))
				var at := WarSurfaceEffects.offset_point(map_definition, zone.at, radial * zone.radius * (0.35 + 0.55 * absf(sin(angle * 2.7))) + Vector3(0, 0.18, 0))
				var wind := Vector3(-radial.z, 0.14, radial.x)
				$HasteMotes.emit_particle(Transform3D(Basis(Vector3.UP, angle), at), wind * 0.8, Color("c0d8a4").srgb_to_linear(), Color(), EMIT_FLAGS)
	fields.visible_instance_count = count
	$Rabbit.update_rush(delta, marches)
	if emit and not marches.haste_zones.is_empty():
		var active: Array[WarMarches.MarchUnit] = []
		for unit: WarMarches.MarchUnit in marches._units:
			if unit.is_exposed() and not unit.cloaked and unit.rush_remaining <= 0.0 and marches.haste_zones.has(unit.order.faction) and marches.speed_multiplier(unit) > 1.0 and marches.haste_zones[unit.order.faction].style != SKILL_RULES.RABBIT:
				active.append(unit)
		if not active.is_empty():
			for index: int in mini(48, active.size()):
				var unit := active[(_wind_offset + index) % active.size()]
				var basis := Basis.looking_at(unit.heading)
				var at := WarSurfaceEffects.offset_point(map_definition, unit.position, Vector3(0, 0.13, 0) - unit.heading * 0.4)
				$HasteTrails.emit_particle(Transform3D(basis, at), -unit.heading * 1.4, Color("e0e8d1"), Color(), EMIT_FLAGS)
			_wind_offset = (_wind_offset + 48) % active.size()

func set_running(value: bool) -> void:
	$PigEffects.set_running(value)
	$Fox.set_running(value)
	$Frog.set_running(value)
	$Bear.set_running(value)
	$Rabbit.set_running(value)
	for particles: GPUParticles3D in [$RecruitMotes, $ShieldMotes, $HasteTrails, $HasteMotes]:
		particles.speed_scale = 1.0 if value else 0.0
	for particles: GPUParticles3D in $Bursts.get_children():
		particles.speed_scale = 1.0 if value else 0.0
	for effect: Node3D in $Hits.get_children():
		for particles: GPUParticles3D in effect.get_children():
			particles.speed_scale = 1.0 if value else 0.0
	for fire: WarFireWave in $FireWaves.get_children():
		fire.set_running(value)

func pig_ready(buildings: Array, ready: Dictionary) -> void:
	$PigEffects.update_ready(buildings, ready)

func pig_drop(id: int, faction: int, center: Vector3, age: float = 0.0) -> void:
	$PigEffects.start_drop(id, faction, center, age)

func sync_pig_drops(states: Array) -> void:
	$PigEffects.sync_drops(states)
