extends Node3D
## Authored particle and mesh pools. Their clock follows simulation and pause.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var time := 0.0
var dust_clock := 0.0
var serial := 0
var cuts: Array[Dictionary] = []

func _ready() -> void:
	$Mist.multimesh.instance_count = 18
	$Bubbles.multimesh.instance_count = 512
	$Cuts.multimesh.instance_count = 6

func release(index: int, _faction: int, at: Vector3) -> void:
	if index == 3:
		cuts.append({"at": at, "age": 0.0})
	var count: int = [28, 24, 18, 16][index]
	for i: int in count:
		var a := float(i) * 2.399963
		var radial := Vector3(cos(a), 0.0, sin(a))
		if index == 0:
			$Puffs.emit_particle(Transform3D(Basis.IDENTITY, at + radial * (0.4 + 2.5 * sqrt(float(i) / count)) + Vector3.UP * 0.35), radial * 0.16 + Vector3.UP * 0.18, Color("b5c4a7"), Color(), EMIT)
		else:
			var fraction := (float(i) + 0.5) / count
			var origin := at + radial * RULES.FROG_RADII[index] * sqrt(fraction) * 0.82
			origin.y += 0.22
			var velocity := radial * 0.20 + Vector3.UP * (0.95 if index == 1 else 0.25)
			if index == 3:
				# Fragments follow the cut through the house instead of forming a
				# generic ring. The initial mark and population change are immediate.
				origin = at + Vector3(lerpf(-1.6, 1.6, fraction), 1.6 + sin(a) * 0.6, lerpf(1.0, -1.0, fraction))
				velocity = Vector3(2.2, 0.3, -1.4) + radial * 0.45
			elif index == 2:
				velocity += Vector3(0.5, 0.0, -0.3)
			var basis := Basis.from_euler(Vector3(0.3 + sin(a) * 0.7, a, cos(a) * 0.6))
			$Flecks.emit_particle(Transform3D(basis, origin), velocity, Color("cfe1a8") if index != 3 else Color("a6bf73"), Color(), EMIT)
	_render_cuts()

func sync(marches: WarMarches, delta: float) -> void:
	time += delta
	dust_clock += delta
	var emit := dust_clock >= 0.20
	if emit:
		dust_clock = fmod(dust_clock, 0.20)
	$Mist.multimesh.mesh.material.set_shader_parameter("visual_time", time)
	var slot := 0
	for faction: int in marches.weak_zones:
		var zone: Dictionary = marches.weak_zones[faction]
		for layer: int in 3:
			var basis := Basis(Vector3.UP, float(layer) * 0.9).scaled(Vector3.ONE * zone.radius)
			$Mist.multimesh.set_instance_transform(slot, Transform3D(basis, zone.at + Vector3.UP * (0.22 + layer * 0.46)))
			$Mist.multimesh.set_instance_custom_data(slot, Color(layer, 0, 0, zone.remaining / RULES.FROG_DURATIONS[0]))
			slot += 1
		if emit:
			for i: int in 3:
				serial += 1
				var a := serial * 2.399963
				var p: Vector3 = zone.at + Vector3(cos(a), 0.2, sin(a)) * zone.radius * 0.6
				$Puffs.emit_particle(Transform3D(Basis.IDENTITY, p), Vector3(0.12, 0.14, 0.03), Color("b5c4a7"), Color(), EMIT)
	$Mist.multimesh.visible_instance_count = slot
	var bubbles: MultiMesh = $Bubbles.multimesh
	if marches._units.size() > bubbles.instance_count:
		bubbles.instance_count = maxi(marches._units.size(), bubbles.instance_count * 2)
	slot = 0
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.levitation_remaining <= 0.0 or not unit.is_exposed():
			continue
		# A cloaked soldier must not be revealed by a bright membrane around it.
		if unit.cloak_remaining > 0.0:
			continue
		bubbles.set_instance_transform(slot, Transform3D(Basis.IDENTITY, unit.position + Vector3.UP * 0.64))
		bubbles.set_instance_custom_data(slot, Color(0, 0, 0, unit.levitation_remaining / RULES.FROG_DURATIONS[1]))
		slot += 1
	bubbles.visible_instance_count = slot
	for i: int in range(cuts.size() - 1, -1, -1):
		cuts[i].age += delta
		if cuts[i].age >= 0.55:
			cuts.remove_at(i)
	_render_cuts()

func _render_cuts() -> void:
	var mesh: MultiMesh = $Cuts.multimesh
	if cuts.size() > mesh.instance_count:
		mesh.instance_count = cuts.size()
	for i: int in cuts.size():
		var basis := Basis(Vector3.RIGHT, -0.62).scaled(Vector3(3.6, 3.6, 3.6))
		mesh.set_instance_transform(i, Transform3D(basis, cuts[i].at + Vector3.UP * 2.0))
		mesh.set_instance_custom_data(i, Color(0, 0, 0, cuts[i].age))
	mesh.visible_instance_count = cuts.size()

func set_running(value: bool) -> void:
	$Puffs.speed_scale = 1.0 if value else 0.0
	$Flecks.speed_scale = 1.0 if value else 0.0
