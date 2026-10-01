extends Node3D
## Bounded authored meshes/particles; animation follows the match clock.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
var time := 0.0
var tool_ages: Array[float] = [2, 2, 2, 2, 2, 2]
var tool_targets: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var emission_clock := 0.0
var serial := 0
var map_definition := WarMapDefinition.new()
var _link_meshes: Dictionary[Mesh, TriangleMesh] = {}
var _link_mounts: Dictionary[int, Dictionary] = {}
const LINK_BODY_PATHS := ["House/Stone", "Tower/Stone", "Smithy/Stone", "EnergyTower/Stone"]
# Interior points in the authored meshes; the actual wall is found by a native
# BVH ray query. The open smithy attaches to its furnace, not to empty canopy air.
const LINK_BODY_CENTERS: Array[Vector3] = [Vector3(0, 1.0, -0.066), Vector3(0, 0.9, 0), Vector3(-0.69, 0.8, -0.21), Vector3(0, 0.82, 0)]

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	WarSurfaceEffects.configure($LockGrounds.multimesh.mesh.material, definition)
	WarSurfaceEffects.configure($HostileGrounds.multimesh.mesh.material, definition)
	WarSurfaceEffects.configure($LinkGrounds.multimesh.mesh.material, definition)

func _ready() -> void:
	for path: String in ["LockGrounds", "LockSeals", "LockShackles", "HostileGrounds", "Fractures", "UpgradeSweeps", "Wards", "Orbs", "OrbBands"]:
		get_node(path).multimesh.instance_count = 6
	$LockChains.multimesh.instance_count = 288
	$Chains.multimesh.instance_count = 512
	for path: String in ["LinkAnchors", "LinkPlates", "LinkGrounds"]:
		get_node(path).multimesh.instance_count = 12
	$Bolts.multimesh.instance_count = 64

func toolbox(faction: int, at: Vector3) -> void:
	tool_ages[faction] = 0.0
	tool_targets[faction] = at
	var tool: Node3D = $Tools.get_child(faction)
	tool.position = WarSurfaceEffects.offset_point(map_definition, at, Vector3(2.2, 0.18, 0.65))
	tool.show()
	for i: int in 15:
		var a := i * 2.399963
		var origin := WarSurfaceEffects.offset_point(map_definition, at, Vector3(cos(a), 0.2, sin(a)) * 2.3)
		$Dust.emit_particle(Transform3D(Basis.IDENTITY, origin), Vector3(cos(a) * 0.6, 1.3, sin(a) * 0.6), Color("c99c60"), Color(), EMIT)

func lock(_faction: int, at: Vector3) -> void:
	for i: int in 24:
		var a := i * 2.399963
		var radial := Vector3(cos(a), 0, sin(a))
		var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * 2.75 + Vector3.UP * 0.12)
		$Dust.emit_particle(Transform3D(Basis.IDENTITY, origin), -radial * 0.5 + Vector3.UP * 1.2, Color("8b7561"), Color(), EMIT)

func spark(at: Vector3) -> void:
	for i: int in 8:
		var a := i * TAU / 8.0
		$Motes.emit_particle(Transform3D(Basis.IDENTITY, at), Vector3(cos(a), 1.0, sin(a)) * 1.3, Color("ffdc80"), Color(), EMIT)

func sync(bear: RefCounted, _marches: WarMarches, by_id: Dictionary, delta: float) -> void:
	time += delta
	emission_clock += delta
	var emit := emission_clock >= 0.16
	if emit:
		emission_clock = fmod(emission_clock, 0.16)
	for path: String in ["LockGrounds", "HostileGrounds", "Fractures", "UpgradeSweeps", "Wards", "Orbs", "LinkGrounds"]:
		get_node(path).multimesh.mesh.material.set_shader_parameter("visual_time", time)
	var upgrades: MultiMesh = $UpgradeSweeps.multimesh
	var upgrade_count := 0
	for faction: int in 6:
		var previous_age := tool_ages[faction]
		tool_ages[faction] += delta
		var tool: Node3D = $Tools.get_child(faction)
		var age := tool_ages[faction]
		if age < 1.1:
			upgrades.set_instance_transform(upgrade_count, Transform3D(Basis.IDENTITY, tool_targets[faction] + Vector3.UP * 2.25))
			upgrades.set_instance_custom_data(upgrade_count, Color(age / 1.1, 0, 0, 1))
			upgrade_count += 1
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
	upgrades.visible_instance_count = upgrade_count
	_sync_locks(bear.locks, by_id)
	_sync_links(bear.links, by_id)
	var walls: MultiMesh = $Wards.multimesh
	var hostile_grounds: MultiMesh = $HostileGrounds.multimesh
	var fractures: MultiMesh = $Fractures.multimesh
	var orbs: MultiMesh = $Orbs.multimesh
	var rings: MultiMesh = $OrbBands.multimesh
	var count := 0
	var friendly_count := 0
	var hostile_count := 0
	for id: int in bear.wards:
		var ward: Dictionary = bear.wards[id]
		if ward.remaining <= 0.0: continue
		var at: Vector3 = by_id[id].global_position
		var hostile: bool = ward.hostile
		var custom := Color(float(hostile), ward.pulse, RULES.BEAR_DURATIONS[3] - ward.remaining, ward.remaining / RULES.BEAR_DURATIONS[3])
		if hostile:
			hostile_grounds.set_instance_transform(hostile_count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3.4), at + Vector3.UP * 0.095))
			hostile_grounds.set_instance_custom_data(hostile_count, custom)
			fractures.set_instance_transform(hostile_count, Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.5))
			fractures.set_instance_custom_data(hostile_count, custom)
			hostile_count += 1
		else:
			walls.set_instance_transform(friendly_count, Transform3D(Basis.IDENTITY, at + Vector3.UP * 1.1))
			walls.set_instance_custom_data(friendly_count, custom)
			friendly_count += 1
		var orb_at := at + Vector3(0, 6.1 + sin(time * 2.0) * 0.10, 0)
		var scale_factor: float = (1.0 - ward.pulse * 0.13) * smoothstep(0.0, 0.22, ward.remaining)
		var spin := 1.8 if hostile else 0.75
		orbs.set_instance_transform(count, Transform3D(Basis(Vector3.UP, time * spin).scaled(Vector3.ONE * scale_factor), orb_at))
		orbs.set_instance_custom_data(count, Color(ward.pulse, float(hostile), 0, ward.remaining / RULES.BEAR_DURATIONS[3]))
		rings.set_instance_transform(count, Transform3D((Basis(Vector3.FORWARD, 0.55) * Basis(Vector3.RIGHT, time * spin)).scaled(Vector3.ONE * scale_factor), orb_at))
		rings.set_instance_color(count, Color("ce6031") if hostile else Color.WHITE)
		count += 1
		if emit:
			serial += 1
			var a := serial * 2.399963
			$Motes.emit_particle(Transform3D(Basis.IDENTITY, orb_at + Vector3(cos(a), sin(a * 2.0) * 0.3, sin(a)) * 0.65), Vector3.UP * (0.65 if hostile else 0.3), Color("ff7735") if hostile else Color("eac77e"), Color(), EMIT)
	walls.visible_instance_count = friendly_count
	hostile_grounds.visible_instance_count = hostile_count
	fractures.visible_instance_count = hostile_count
	orbs.visible_instance_count = count
	rings.visible_instance_count = count
	var bolts: MultiMesh = $Bolts.multimesh
	count = 0
	for shot: Dictionary in bear.shots:
		var direction: Vector3 = (shot.to - shot.origin).normalized()
		bolts.set_instance_transform(count, Transform3D(Basis.looking_at(direction), shot.position))
		count += 1
	bolts.visible_instance_count = count

func _sync_locks(locks: Dictionary, by_id: Dictionary) -> void:
	var grounds: MultiMesh = $LockGrounds.multimesh
	var chains: MultiMesh = $LockChains.multimesh
	var seals: MultiMesh = $LockSeals.multimesh
	var shackles: MultiMesh = $LockShackles.multimesh
	var count := 0
	var pieces := 0
	for id: int in locks:
		var state: Dictionary = locks[id]
		if state.remaining <= 0.0: continue
		var at: Vector3 = by_id[id].global_position
		var age: float = RULES.BEAR_DURATIONS[1] - state.remaining
		var settle := smoothstep(0.0, 0.22, age)
		var fade := smoothstep(0.0, 0.28, state.remaining)
		grounds.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 3.15), at + Vector3.UP * 0.095))
		grounds.set_instance_custom_data(count, Color(0, 0, age, state.remaining / RULES.BEAR_DURATIONS[1]))
		# A low belt around the doors leaves roofs, population and production readable.
		for index: int in 48:
			var angle := TAU * float(index) / 48.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			var origin := WarSurfaceEffects.offset_point(map_definition, at, radial * lerpf(3.15, 2.65, settle) + Vector3.UP * (0.55 + sin(angle * 4.0) * 0.12))
			var basis := Basis.looking_at(Vector3(-sin(angle), 0, cos(angle))) * Basis(Vector3.FORWARD, PI * (0.25 + 0.5 * float(index % 2)))
			basis *= Basis.from_scale(Vector3(0.82, 0.82, 1.1) * fade)
			chains.set_instance_transform(pieces, Transform3D(basis, origin))
			chains.set_instance_custom_data(pieces, Color((1.0 - settle) * 0.55, 0, 0, 1))
			pieces += 1
		var seal_at := WarSurfaceEffects.offset_point(map_definition, at, Vector3(0, 0.88, 2.65))
		seals.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * fade * settle), seal_at))
		seals.set_instance_custom_data(count, Color((1.0 - settle) * 0.55, 0, 0, 1))
		shackles.set_instance_transform(count, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3.ONE * 1.25 * fade * settle), seal_at + Vector3.UP * 0.35))
		shackles.set_instance_custom_data(count, Color((1.0 - settle) * 0.55, 0, 0, 1))
		count += 1
	grounds.visible_instance_count = count
	seals.visible_instance_count = count
	shackles.visible_instance_count = count
	chains.visible_instance_count = pieces

func _link_mount(building: WarBuilding, toward: Vector3) -> Dictionary:
	var body: MeshInstance3D = building.get_node("Visual/" + LINK_BODY_PATHS[building.kind])
	var direction: Vector3 = body.to_local(toward) - LINK_BODY_CENTERS[building.kind]
	direction.y = 0.0
	direction = direction.normalized()
	var id := building.building_id
	if not _link_mounts.has(id) or _link_mounts[id].mesh != body.mesh or not _link_mounts[id].direction.is_equal_approx(direction):
		if not _link_meshes.has(body.mesh):
			_link_meshes[body.mesh] = body.mesh.generate_triangle_mesh()
		var start: Vector3 = LINK_BODY_CENTERS[building.kind] + direction * (body.mesh.get_aabb().size.length() + 1.0)
		var hit: Dictionary = _link_meshes[body.mesh].intersect_ray(start, -direction)
		assert(not hit.is_empty(), "Authored building must have a solid link attachment surface.")
		_link_mounts[id] = {"mesh": body.mesh, "direction": direction, "at": hit.position, "normal": hit.normal}
	var mount := _link_mounts[id]
	var normal: Vector3 = (body.global_basis.inverse().transposed() * mount.normal).normalized()
	return {"at": body.to_global(mount.at) + normal * 0.075, "normal": normal}

func _link_point(a: Vector3, b: Vector3, t: float) -> Vector3:
	var at := a.lerp(b, t)
	at.y -= sin(t * PI) * minf(0.55, a.distance_to(b) * 0.045)
	if map_definition.has_elevation():
		var lift := maxf(0.0, map_definition.surface_height(Vector2(at.x, at.z)) + 0.24 - at.y)
		at.y += lift * smoothstep(0.0, 0.07, t) * smoothstep(0.0, 0.07, 1.0 - t)
	return at

func _link_glint(t: float, pulse: float) -> float:
	return exp(-pow((t - (1.0 - pulse) * 1.5) * 7.0, 2.0)) if pulse > 0.0 else 0.0

func _sync_links(links: Dictionary, by_id: Dictionary) -> void:
	var chains: MultiMesh = $Chains.multimesh
	var anchors: MultiMesh = $LinkAnchors.multimesh
	var plates: MultiMesh = $LinkPlates.multimesh
	var grounds: MultiMesh = $LinkGrounds.multimesh
	var count := 0
	var ends := 0
	var active: Array[int] = []
	for link: Dictionary in links.values():
		# A replica can still have an expired row awaiting reliable deletion.
		if link.remaining <= 0.0: continue
		var source: WarBuilding = by_id[link.target]
		var support: WarBuilding = by_id[link.support]
		var mounts: Array[Dictionary] = [_link_mount(source, support.global_position), _link_mount(support, source.global_position)]
		var a: Vector3 = mounts[0].at + mounts[0].normal * 0.12
		var b: Vector3 = mounts[1].at + mounts[1].normal * 0.12
		for endpoint: int in 2:
			var building: WarBuilding = source if endpoint == 0 else support
			active.append(building.building_id)
			var mount := mounts[endpoint]
			var normal: Vector3 = mount.normal
			var side := Vector3.UP.cross(normal).normalized()
			var basis := Basis(side, normal, side.cross(normal)).orthonormalized()
			var custom := Color(_link_glint(float(endpoint), link.pulse), 0, 0, 1)
			plates.set_instance_transform(ends, Transform3D(basis, mount.at - normal * 0.035))
			plates.set_instance_custom_data(ends, custom)
			anchors.set_instance_transform(ends, Transform3D(basis, mount.at + normal * 0.08))
			anchors.set_instance_custom_data(ends, custom)
			var heading := (support.global_position - source.global_position) * (1.0 if endpoint == 0 else -1.0)
			heading.y = 0.0
			grounds.set_instance_transform(ends, Transform3D(Basis.looking_at(heading).scaled(Vector3.ONE * 2.8), building.global_position + Vector3.UP * 0.115))
			grounds.set_instance_custom_data(ends, Color(link.pulse, endpoint, link.remaining / RULES.BEAR_DURATIONS[2], 1))
			ends += 1
		var pieces := maxi(2, ceili(a.distance_to(b) / 0.42))
		for index: int in pieces:
			var t := float(index) / float(pieces - 1)
			var at := _link_point(a, b, t)
			var tangent := (_link_point(a, b, minf(1.0, t + 0.012)) - _link_point(a, b, maxf(0.0, t - 0.012))).normalized()
			var basis := Basis.looking_at(tangent) * Basis(Vector3.FORWARD, PI * (0.25 + 0.5 * float(index % 2)))
			basis *= Basis.from_scale(Vector3(0.76, 1.0, 1.40))
			chains.set_instance_transform(count, Transform3D(basis, at))
			chains.set_instance_custom_data(count, Color(_link_glint(t, link.pulse), 0, 0, 1))
			count += 1
	chains.visible_instance_count = count
	anchors.visible_instance_count = ends
	plates.visible_instance_count = ends
	grounds.visible_instance_count = ends
	for id: int in _link_mounts.keys():
		if not active.has(id): _link_mounts.erase(id)

func set_running(value: bool) -> void:
	$Motes.speed_scale = 1.0 if value else 0.0
	$Dust.speed_scale = 1.0 if value else 0.0
