extends Node3D
## Bounded authored meshes/particles; animation follows the match clock.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var time := 0.0
var tool_ages: Array[float] = [2, 2, 2, 2, 2, 2]
var emission_clock := 0.0
var serial := 0
var map_definition := WarMapDefinition.new()

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	WarSurfaceEffects.configure($Ground.multimesh.mesh.material, definition)

func _ready() -> void:
	for path: String in ["Ground", "Wards", "Orbs", "OrbBands"]:
		get_node(path).multimesh.instance_count = 6
	$Chains.multimesh.instance_count = 384
	$Bolts.multimesh.instance_count = 64

func toolbox(faction: int, at: Vector3) -> void:
	tool_ages[faction] = 0.0
	var tool: Node3D = $Tools.get_child(faction)
	tool.position = WarSurfaceEffects.offset_point(map_definition, at, Vector3(2.2, 0.18, 0.65))
	tool.show()
	for i: int in 15:
		var a := i * 2.399963
		var origin := WarSurfaceEffects.offset_point(map_definition, at, Vector3(cos(a), 0.2, sin(a)) * 2.3)
		$Dust.emit_particle(Transform3D(Basis.IDENTITY, origin), Vector3(cos(a) * 0.6, 1.3, sin(a) * 0.6), Color("c99c60"), Color(), EMIT)

func stomp(_faction: int, at: Vector3) -> void:
	for i: int in 48:
		var a := i * 2.399963
		var r := 1.0 + 3.2 * sqrt(float(i) / 48.0)
		var radial := Vector3(cos(a), 0, sin(a))
		var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * r + Vector3.UP * 0.12)
		var basis := Basis.from_euler(Vector3(a * 0.7, a, a * 0.3)).scaled(Vector3.ONE * (1.1 + float(i % 3) * 0.25))
		$Dust.emit_particle(Transform3D(basis, origin), radial * 1.6 + Vector3.UP * (1.4 + float(i % 3) * 0.5), Color("bdaa76"), Color(), EMIT)

func spark(at: Vector3) -> void:
	for i: int in 8:
		var a := i * TAU / 8.0
		$Motes.emit_particle(Transform3D(Basis.IDENTITY, at), Vector3(cos(a), 1.0, sin(a)) * 1.3, Color("ffdc80"), Color(), EMIT)

func sync(bear: RefCounted, marches: WarMarches, by_id: Dictionary, delta: float) -> void:
	time += delta
	emission_clock += delta
	var emit := emission_clock >= 0.16
	if emit:
		emission_clock = fmod(emission_clock, 0.16)
	for path: String in ["Ground", "Wards", "Orbs"]:
		get_node(path).multimesh.mesh.material.set_shader_parameter("visual_time", time)
	for faction: int in 6:
		var previous_age := tool_ages[faction]
		tool_ages[faction] += delta
		var tool: Node3D = $Tools.get_child(faction)
		var age := tool_ages[faction]
		tool.visible = age < 1.0
		if tool.visible:
			var pop := minf(1.0, age / 0.07) * (1.0 - smoothstep(0.75, 1.0, age))
			tool.scale = Vector3.ONE * pop
			var strike := smoothstep(0.09, 0.19, age)
			var rebound := sin(maxf(0.0, age - 0.19) * 21.0) * exp(-maxf(0.0, age - 0.19) * 9.0)
			tool.get_node("Hammer").rotation.z = lerpf(-0.9, 0.65, strike) - rebound * 0.20
			tool.get_node("Hammer").position.y = 1.1 - strike * 0.18 + rebound * 0.06
			if previous_age < 0.19 and age >= 0.19:
				spark(tool.global_position + Vector3(0.7, 1.0, 0))
	var fields: MultiMesh = $Ground.multimesh
	var count := 0
	for faction: int in marches.slow_zones:
		var zone: Dictionary = marches.slow_zones[faction]
		fields.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * zone.radius), zone.at + Vector3.UP * 0.095))
		fields.set_instance_custom_data(count, Color(0, 0, 0, zone.remaining / zone.duration))
		count += 1
		if emit:
			serial += 1
			var angle := serial * 2.399963
			var p := WarSurfaceEffects.offset_point(map_definition, zone.at, Vector3(cos(angle), 0.03, sin(angle)) * zone.radius * 0.92)
			$Dust.emit_particle(Transform3D(Basis.IDENTITY, p), Vector3.UP * 0.2, Color("b9a679"), Color(), EMIT)
	fields.visible_instance_count = count
	var chains: MultiMesh = $Chains.multimesh
	count = 0
	for link: Dictionary in bear.links.values():
		var a: Vector3 = by_id[link.target].global_position
		var b: Vector3 = by_id[link.support].global_position
		var heading := (b - a).normalized()
		a += heading * 2.2 + Vector3.UP * 1.4
		b -= heading * 2.2 - Vector3.UP * 1.4
		var pieces := maxi(2, ceili(a.distance_to(b) / 0.32))
		for i: int in pieces:
			var t := float(i) / float(pieces - 1)
			var at := a.lerp(b, t) - Vector3.UP * sin(t * PI) * 0.45
			if map_definition.has_elevation():
				at.y = maxf(at.y, map_definition.surface_height(Vector2(at.x, at.z)) + 0.45)
			var basis := Basis.looking_at(heading) * Basis(Vector3.FORWARD, PI * 0.5 if i % 2 == 0 else 0.0)
			chains.set_instance_transform(count, Transform3D(basis, at))
			var glint := exp(-pow((t - (1.0 - float(link.pulse)) * 1.5) * 8.0, 2.0)) if link.pulse > 0.0 else 0.0
			chains.set_instance_color(count, Color("95846a").lerp(Color("ffe6a0"), glint))
			count += 1
	chains.visible_instance_count = count
	var walls: MultiMesh = $Wards.multimesh
	var orbs: MultiMesh = $Orbs.multimesh
	var rings: MultiMesh = $OrbBands.multimesh
	count = 0
	for id: int in bear.wards:
		var ward: Dictionary = bear.wards[id]
		var at: Vector3 = by_id[id].global_position
		walls.set_instance_transform(count, Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.1))
		walls.set_instance_custom_data(count, Color(0, 0, 0, ward.remaining / RULES.BEAR_DURATIONS[3]))
		var orb_at := at + Vector3(0, 6.1 + sin(time * 2.0) * 0.10, 0)
		var scale_factor: float = (1.0 - ward.pulse * 0.13) * smoothstep(0.0, 0.22, ward.remaining)
		orbs.set_instance_transform(count, Transform3D(Basis(Vector3.UP, time * 0.45).scaled(Vector3.ONE * scale_factor), orb_at))
		orbs.set_instance_custom_data(count, Color(ward.pulse, 0, 0, ward.remaining / 5.0))
		rings.set_instance_transform(count, Transform3D((Basis(Vector3.FORWARD, 0.55) * Basis(Vector3.RIGHT, time * 0.75)).scaled(Vector3.ONE * scale_factor), orb_at))
		count += 1
		if emit:
			serial += 1
			var a := serial * 2.399963
			$Motes.emit_particle(Transform3D(Basis.IDENTITY, orb_at + Vector3(cos(a), sin(a * 2.0) * 0.3, sin(a)) * 0.65), Vector3.UP * 0.3, Color("eac77e"), Color(), EMIT)
	walls.visible_instance_count = count
	orbs.visible_instance_count = count
	rings.visible_instance_count = count
	var bolts: MultiMesh = $Bolts.multimesh
	count = 0
	for shot: Dictionary in bear.shots:
		var direction: Vector3 = (shot.to - shot.origin).normalized()
		bolts.set_instance_transform(count, Transform3D(Basis.looking_at(direction), shot.position))
		count += 1
	bolts.visible_instance_count = count

func set_running(value: bool) -> void:
	$Motes.speed_scale = 1.0 if value else 0.0
	$Dust.speed_scale = 1.0 if value else 0.0
