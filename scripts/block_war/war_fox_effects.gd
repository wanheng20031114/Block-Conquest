extends Node3D
## Shared particle emitters and twelve authored model slots, never runtime nodes.
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY
var next_slot := 0
var trail_clock := 0.0
var map_definition := WarMapDefinition.new()

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	for slot: Node3D in $Casts.get_children():
		WarSurfaceEffects.configure(slot.get_node("Wave").mesh.material, definition)

func release(index: int, faction: int, at: Vector3, target_id: int = -1) -> void:
	var roof := 0.0
	if index != 2:
		var building: WarBuilding = get_parent().get_parent().by_id[target_id]
		# Native mesh bounds include each authored level and the current selection
		# pose, so a bomb lands on the model rather than disappearing into its roof.
		for mesh: MeshInstance3D in building.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree():
				continue
			var bounds := mesh.get_aabb()
			for corner: int in 8:
				roof = maxf(roof, mesh.to_global(bounds.get_endpoint(corner)).y - at.y)
	var receiver := at + Vector3(-4, 0, 3)
	if index == 1:
		var distance := INF
		for building: WarBuilding in get_parent().get_parent().buildings:
			if building.faction == faction and building.global_position.distance_squared_to(at) < distance:
				distance = building.global_position.distance_squared_to(at)
				receiver = building.global_position
	var slot: Node3D = $Casts.get_child(next_slot)
	next_slot = (next_slot + 1) % $Casts.get_child_count()
	slot.begin(index, at, receiver, FACTIONS.COLORS[faction], roof)
	if index == 0:
		_mote(at + Vector3(0.3, roof + 6.2, 0), Vector3(0.2, 0.3, 0), 0.65)
	elif index == 1:
		for i: int in 9:
			var a := i * TAU / 9.0
			_mote(at + Vector3(cos(a) * 0.6, roof + 1.1, sin(a) * 0.6), Vector3(cos(a), 0.9, sin(a)) * 0.4, 0.7)
	else:
		# A few paper-like pennants follow the sweep; they never obscure troops.
		for i: int in 22:
			var a := i * 2.399963
			var radial := Vector3(cos(a), 0, sin(a))
			var point := WarSurfaceEffects.offset_point(map_definition, at, radial * (0.8 + (i % 4) * 0.45) + Vector3.UP * 0.25)
			var basis := Basis.from_euler(Vector3(a, a * 0.6, 0.7))
			$Pennants.emit_particle(Transform3D(basis, point), radial * (3.0 if index == 3 else 0.4) + Vector3.UP * 1.4, Color(), Color(), EMIT)

func advance(delta: float) -> void:
	trail_clock += delta
	var emit := trail_clock >= 0.035
	if emit:
		trail_clock = fmod(trail_clock, 0.035)
	for slot: Node3D in $Casts.get_children():
		if not slot.active:
			continue
		slot.advance(delta)
		if slot.kind == 0 and slot.age >= 0.18 and not slot.impacted:
			slot.impacted = true
			impact(slot.position + Vector3.UP * (slot.roof_height + 0.6))
		elif emit and slot.kind == 0 and slot.age < 0.18:
			_mote(slot.get_node("Bomb/Spark").global_position, Vector3(0.2, 0.55, 0), 0.55)
		elif emit and slot.kind == 1 and slot.age < slot.star_arrival:
			_mote(slot.get_node("Star").global_position, Vector3.UP * 0.1, 0.65)

func impact(at: Vector3) -> void:
	for i: int in 28:
		var a := i * 2.399963
		var radial := Vector3(cos(a), 0.35 + (i % 3) * 0.18, sin(a))
		_mote(at + radial * 0.28, radial * (3.8 + (i % 4)), 1.0)
	for i: int in 14:
		var a := i * TAU / 14.0
		var radial := Vector3(cos(a), 0.1, sin(a))
		$Smoke.emit_particle(Transform3D(Basis.IDENTITY, at + radial * 0.55), radial * 2.8 + Vector3.UP * (0.6 + float(i % 3) * 0.45), Color(), Color(), EMIT)
	for i: int in 10:
		var a := i * 2.399963
		var radial := Vector3(cos(a), 0, sin(a))
		var basis := Basis.from_euler(Vector3(a * 0.3, a, a * 0.7))
		$Fragments.emit_particle(Transform3D(basis, at + radial * 0.3), radial * (2.6 + float(i % 3) * 0.8) + Vector3.UP * (2.2 + float(i % 4) * 0.5), Color(), Color(), EMIT)

func _mote(at: Vector3, velocity: Vector3, size: float) -> void:
	$Sparks.emit_particle(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), at), velocity, Color(), Color(), EMIT)

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in [$Sparks, $Smoke, $Pennants, $Fragments]:
		particles.speed_scale = 1.0 if value else 0.0
