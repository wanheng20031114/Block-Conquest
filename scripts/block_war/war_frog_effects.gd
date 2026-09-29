extends Node3D
## Authored particle and mesh pools. Their clock follows simulation and pause.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var time := 0.0
var dust_clock := 0.0
var serial := 0
var cuts: Array[Dictionary] = []
var blooms: Array[Dictionary] = []
var map_definition := WarMapDefinition.new()

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	WarSurfaceEffects.configure($Mist.multimesh.mesh.material, definition)
	WarSurfaceEffects.configure($CastBlooms.multimesh.mesh.material, definition)

func _ready() -> void:
	$Mist.multimesh.instance_count = 18
	$Bubbles.multimesh.instance_count = 512
	$Cuts.multimesh.instance_count = 6
	$CastBlooms.multimesh.instance_count = 18

func release(index: int, _faction: int, at: Vector3) -> void:
	if index == 3:
		cuts.append({"at": at, "age": 0.0})
		_strike_impact(at)
	else:
		blooms.append({"at": at, "age": 0.0, "skill": index})
	var count: int = [28, 24, 18, 16][index]
	for i: int in count:
		var a := float(i) * 2.399963
		var radial := Vector3(cos(a), 0.0, sin(a))
		if index == 0:
			var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * (0.4 + 2.5 * sqrt(float(i) / count)) + Vector3.UP * 0.35)
			$Puffs.emit_particle(Transform3D(Basis.IDENTITY, origin), radial * 0.16 + Vector3.UP * 0.18, Color("b5c4a7"), Color(), EMIT)
		else:
			var fraction := (float(i) + 0.5) / count
			var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * RULES.FROG_RADII[index] * sqrt(fraction) * 0.82 + Vector3.UP * 0.22)
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
	_render_blooms()

func _strike_impact(at: Vector3) -> void:
	# Stone-colored dust masks the instantaneous model downgrade. The rules and
	# shared real-soldier casualties remain owned by the paid skill cast.
	for i: int in 42:
		var angle := i * 2.399963
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var height := 0.35 + float(i % 7) * 0.47
		var origin := at + radial * (0.9 + float(i % 3) * 0.22) + Vector3.UP * height
		var velocity := radial * (1.2 + float(i % 5) * 0.37) + Vector3.UP * (0.25 + float(i % 3) * 0.18)
		$StrikeDust.emit_particle(Transform3D(Basis.IDENTITY, origin), velocity, Color("b8b29a"), Color(), EMIT)
	for i: int in 32:
		var angle := i * 2.399963 + 0.6
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var origin := at + radial * 0.9 + Vector3.UP * (1.1 + float(i % 5) * 0.48)
		var velocity := radial * (2.0 + float(i % 4) * 0.55) + Vector3.UP * (2.2 + float(i % 3) * 0.6)
		var basis := Basis.from_euler(Vector3(angle * 0.7, angle, angle * 0.3))
		var tint := Color("cbc1a3") if i % 3 != 0 else Color("79674d")
		$Rubble.emit_particle(Transform3D(basis, origin), velocity, tint, Color(), EMIT)
	for i: int in 20:
		var angle := i * TAU / 20.0
		var radial := Vector3(cos(angle), 0.0, sin(angle))
		var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * 1.6 + Vector3.UP * 0.22)
		$StrikeDust.emit_particle(Transform3D(Basis.IDENTITY, origin), radial * 3.2 + Vector3.UP * 0.15, Color("aeb49a"), Color(), EMIT)

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
				var p := WarSurfaceEffects.offset_point(map_definition, zone.at, Vector3(cos(a), 0.2, sin(a)) * zone.radius * 0.6)
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
		if unit.cloaked:
			continue
		bubbles.set_instance_transform(slot, Transform3D(Basis.IDENTITY, unit.position + Vector3.UP * 0.64))
		bubbles.set_instance_custom_data(slot, Color(0, 0, 0, unit.levitation_remaining / RULES.FROG_DURATIONS[1]))
		slot += 1
	bubbles.visible_instance_count = slot
	for i: int in range(cuts.size() - 1, -1, -1):
		cuts[i].age += delta
		if cuts[i].age >= 0.75:
			cuts.remove_at(i)
	for i: int in range(blooms.size() - 1, -1, -1):
		blooms[i].age += delta
		if blooms[i].age >= 0.85:
			blooms.remove_at(i)
	_render_cuts()
	_render_blooms()

func _render_cuts() -> void:
	var mesh: MultiMesh = $Cuts.multimesh
	if cuts.size() * 2 > mesh.instance_count:
		mesh.instance_count = cuts.size() * 2
	for i: int in cuts.size():
		for blade: int in 2:
			var basis := Basis.from_euler(Vector3(-0.72, -0.36 + blade * 1.28, 0.28 - blade * 0.48)).scaled(Vector3.ONE * (4.2 if blade == 0 else 3.9))
			mesh.set_instance_transform(i * 2 + blade, Transform3D(basis, cuts[i].at + Vector3.UP * (2.75 + blade * 0.2)))
			mesh.set_instance_custom_data(i * 2 + blade, Color(blade, 0, 0, cuts[i].age))
	mesh.visible_instance_count = cuts.size() * 2

func _render_blooms() -> void:
	var mesh: MultiMesh = $CastBlooms.multimesh
	if blooms.size() > mesh.instance_count:
		mesh.instance_count = blooms.size()
	for i: int in blooms.size():
		var bloom: Dictionary = blooms[i]
		var radius: float = RULES.FROG_RADII[int(bloom.skill)]
		mesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), bloom.at))
		mesh.set_instance_custom_data(i, Color(bloom.skill, 0, 0, bloom.age))
	mesh.visible_instance_count = blooms.size()

func set_running(value: bool) -> void:
	$Puffs.speed_scale = 1.0 if value else 0.0
	$Flecks.speed_scale = 1.0 if value else 0.0
	$StrikeDust.speed_scale = 1.0 if value else 0.0
	$Rubble.speed_scale = 1.0 if value else 0.0
