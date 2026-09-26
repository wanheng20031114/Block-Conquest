extends Node3D
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var age := 0.0
var emission := 0.0
var serial := 0
var soldier_offset := 0

func _ready() -> void:
	$Fields.multimesh.instance_count = 6
	$Fields.multimesh.visible_instance_count = 0

func start_tunnel(faction: int, entrance: Vector3, exit: Vector3, direction: Vector3, count: int) -> void:
	var duration := RULES.BURROW_WARNING + floorf(float(count - 1) / WarMarches.COLUMNS) * RULES.BURROW_BATCH_INTERVAL + 0.3
	$Tunnels.get_child(faction * 2).start(entrance, direction, 1.35)
	$Tunnels.get_child(faction * 2 + 1).start(exit, direction, duration)

func start_rally(faction: int, at: Vector3) -> void:
	$Rallies.get_child(faction).start(at)

func return_dust(at: Vector3, direction: Vector3) -> void:
	for i: int in 3:
		$FootDust.emit_particle(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.12), -direction.normalized() * 0.3 + Vector3.UP * 0.28, Color("d3c5a6"), Color(), FLAGS)

func tick(delta: float) -> void:
	age += delta
	for effect: Node3D in $Tunnels.get_children():
		effect.tick(delta)
	for effect: Node3D in $Rallies.get_children():
		effect.tick(delta)

func update_haste(delta: float, marches: WarMarches) -> void:
	emission += delta
	var emit := emission >= 0.12
	if emit:
		emission = fmod(emission, 0.12)
	var mesh: MultiMesh = $Fields.multimesh
	mesh.mesh.material.set_shader_parameter("visual_time", age)
	var count := 0
	for faction: int in marches.haste_zones:
		var zone: Dictionary = marches.haste_zones[faction]
		if zone.style != RULES.RABBIT:
			continue
		mesh.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * zone.radius), zone.at + Vector3.UP * 0.085))
		mesh.set_instance_custom_data(count, Color(WarMarches.FACTION_COLORS[faction], zone.remaining / zone.duration))
		count += 1
		if emit:
			for i: int in 3:
				serial += 1
				var angle := serial * 2.399963
				var radial := Vector3(cos(angle), 0, sin(angle))
				var at: Vector3 = zone.at + radial * zone.radius * (0.3 + 0.6 * absf(sin(angle * 1.7))) + Vector3.UP * 0.1
				$Leaves.emit_particle(Transform3D(Basis(Vector3.UP, angle), at), Vector3(0.5, 0.4, 0.3), Color("b4c78a"), Color(), FLAGS)
	mesh.visible_instance_count = count
	if not emit:
		return
	var runners: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.is_exposed() and marches.haste_zones.has(unit.order.faction) and marches.haste_zones[unit.order.faction].style == RULES.RABBIT and marches.speed_multiplier(unit) > 1.0:
			runners.append(unit)
	if runners.is_empty():
		return
	for i: int in mini(24, runners.size()):
		var unit := runners[(soldier_offset + i) % runners.size()]
		$FootDust.emit_particle(Transform3D(Basis.IDENTITY, unit.position - unit.heading * 0.35 + Vector3.UP * 0.09), -unit.heading * 0.6 + Vector3.UP * 0.3, Color("e1d6bc"), Color(), FLAGS)
	soldier_offset = (soldier_offset + 24) % runners.size()

func set_running(value: bool) -> void:
	for particles: GPUParticles3D in [$FootDust, $Leaves]:
		particles.speed_scale = 1.0 if value else 0.0
	for effect: Node3D in $Tunnels.get_children():
		effect.set_running(value)
	for effect: Node3D in $Rallies.get_children():
		effect.set_running(value)
