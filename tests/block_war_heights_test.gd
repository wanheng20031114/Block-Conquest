extends SceneTree
## Native-map integration: elevated ground, ramp topology, all routes and full formations.

const MAP_IDS: Array[String] = ["terraces", "switchback", "crown"]
const TOLERANCE := 0.002
const FOOTPRINT: Array[Vector3] = [Vector3(-0.842, 0, -0.55), Vector3(-0.842, 0, 0.383), Vector3(0.695, 0, -0.55), Vector3(0.695, 0, 0.383)]
var game: Node3D
var checks := 0
var failures: Array[String] = []
var scenario := "synthetic"
var terrain_faces := PackedVector3Array()
var terrain_buckets: Dictionary[Vector2i, Array] = {}
var terrain_steep_samples := PackedVector2Array()
var terrain_steep_faces := 0
var terrain_ramp_faces := 0
const MESH_BUCKET_SIZE := 4.0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		var message := scenario + ": " + label
		failures.append(message)
		printerr("FAIL ", message)

func _surface(columns: int, rows: int, values: Callable, at: Vector2 = Vector2.ZERO, spacing: float = 1.0) -> WarTerrainSurface:
	var terrain := WarTerrainSurface.new()
	terrain.origin = at
	terrain.cell_size = spacing
	terrain.width = columns
	terrain.depth = rows
	for z: int in rows:
		for x: int in columns:
			var height: float = values.call(at.x + x * spacing, at.y + z * spacing)
			terrain.heights.append(height)
			terrain.max_height = maxf(terrain.max_height, height)
	return terrain

func _synthetic_ground() -> void:
	var flat := WarMapDefinition.new()
	check(not flat.has_elevation(), "legacy maps have an explicit flat ground")
	check(flat.ray_ground(Vector3(2, 10, 3), Vector3.DOWN).is_equal_approx(Vector3(2, 0, 3)), "old flat maps retain ground picking")
	check(not flat.ray_ground(Vector3(2, 10, 3), Vector3.UP).is_finite(), "a ray pointing away returns the explicit miss sentinel")
	check(not flat.ray_ground(Vector3(2, 10, 3), Vector3.RIGHT).is_finite(), "parallel rays cannot invent a ground target")
	var cell := _surface(2, 2, func(_x: float, _z: float): return 0.0, Vector2(-1, -1), 2.0)
	cell.heights = PackedFloat32Array([0, 2, 4, 10])
	cell.max_height = 10.0
	check(absf(cell.sample(Vector2(-0.5, -0.5)) - 1.5) < TOLERANCE, "lower triangle uses the three native mesh vertices")
	check(absf(cell.sample(Vector2(0.5, 0.5)) - 6.5) < TOLERANCE, "upper triangle uses the matching fixed diagonal")
	check(absf(cell.sample(Vector2.ZERO) - 3.0) < TOLERANCE, "the diagonal is planar interpolation, with no bilinear saddle")
	check(cell.gradient_at(Vector2(-0.5, -0.5)).is_equal_approx(Vector2(1, 2)), "lower triangle gradient uses world-space cell size")
	check(cell.gradient_at(Vector2(0.5, 0.5)).is_equal_approx(Vector2(3, 4)), "upper triangle gradient follows the opposite face")
	check(cell.sample(Vector2(1, 1)) == 10.0, "the final grid vertex remains sampleable")
	check(cell.sample(Vector2(1.01, 1)) == 0.0, "outside the finite field is the surrounding floor")
	var cuts := cell.breakpoints(Vector2(-0.8, -0.8), Vector2(0.8, 0.8))
	check(cuts.size() == 3 and absf(cuts[1] - 0.5) < TOLERANCE, "an internal diagonal crossing becomes an exact breakpoint")
	check(cell.ray_ground(Vector3(0.5, 20, 0.5), Vector3.DOWN).distance_to(Vector3(0.5, 6.5, 0.5)) < TOLERANCE, "vertical picking uses the same upper triangle")
	check(not cell.ray_ground(Vector3.ZERO, Vector3.ZERO).is_finite(), "a zero-direction ray is an explicit miss")
	var translated := _surface(4, 3, func(x: float, z: float): return x * 0.2 + z * 0.3 + 2.0, Vector2(-2.25, 3.75), 0.5)
	var at := Vector2(-1.61, 4.36)
	check(absf(translated.sample(at) - (at.x * 0.2 + at.y * 0.3 + 2.0)) < TOLERANCE, "non-integer origins and half-metre spacing retain the authored plane")
	check(translated.gradient_at(at).distance_to(Vector2(0.2, 0.3)) < TOLERANCE, "the gradient remains unchanged after translation and resampling")
	var cliff := _surface(9, 9, func(_x: float, z: float): return 6.0 if absf(z) <= 1.0 else 0.0, Vector2(-4, -4))
	check(not cliff.segment_walkable(Vector2(0, -3), Vector2(0, 3)), "equal-height endpoints cannot conceal an intervening ridge")
	check(not cliff.segment_walkable(Vector2(-2, 1.5), Vector2(2, 1.5)), "walking along a contour does not make a steep face traversable")
	check(cliff.segment_walkable(Vector2(-2, 0), Vector2(2, 0)), "the flat top of a ridge remains traversable")
	var hit := cliff.ray_ground(Vector3(0, 10, 7), Vector3(0, -1, -1).normalized())
	check(hit.distance_to(Vector3(0, 30.0 / 7.0, 9.0 / 7.0)) < TOLERANCE, "the nearest cliff face occludes low ground behind the ridge")
	check(cliff.ray_ground(Vector3(10, 10, 7), Vector3(0, -1, -1).normalized()).distance_to(Vector3(10, 0, -3)) < TOLERANCE, "a ray beside the field still reaches the surrounding floor")
	check(cliff.ray_ground(Vector3(0, 6, 4), Vector3.FORWARD).distance_to(Vector3(0, 6, 1)) < TOLERANCE, "horizontal rays can meet a raised surface at its crest")
	var slope := WarMapDefinition.new()
	slope.terrain = _surface(17, 9, func(x: float, _z: float): return smoothstep(-6.0, 6.0, x) * 4.0, Vector2(-8, -4))
	check(slope.has_elevation(), "height maps use the unified terrain resource")
	check(slope.surface_segment_walkable(Vector2(-7, 0), Vector2(7, 0)), "the eased ramp is traversable uphill")
	check(slope.surface_segment_walkable(Vector2(7, 0), Vector2(-7, 0)), "the eased ramp is traversable downhill")
	check(slope.terrain.gradient_at(Vector2(-6.5, 0)).is_zero_approx() and slope.terrain.gradient_at(Vector2(-5.5, 0)).length() < 0.08, "the ramp approaches its flat entrance gently")
	var seam := _surface(2, 2, func(_x: float, _z: float): return 4.0)
	check(not seam.segment_walkable(Vector2(-20, 0.5), Vector2(0.5, 0.5)), "a malformed elevated outer border cannot act as an invisible shortcut")
	var map := WarMap.new()
	map.definition = slope
	var route := map._surface_route(PackedVector3Array([Vector3(-7, 0, 0), Vector3(7, 4, 0)]))
	check(_route_error(route, slope).is_empty(), "route resampling follows each triangle of the curved height profile")
	check(Array(route).any(func(point: Vector3): return point.distance_to(Vector3(-6, 0, 0)) < TOLERANCE), "the ramp entrance remains an exact route vertex")
	check(Array(route).any(func(point: Vector3): return point.distance_to(Vector3(6, 4, 0)) < TOLERANCE), "the ramp crest remains an exact route vertex")
	map.definition = flat
	var original := PackedVector3Array([Vector3(-6, 0, 0), Vector3(6, 0, 0)])
	check(map._surface_route(original) == original, "flat maps retain their existing route samples verbatim")
	map.free()
	_synthetic_triangle_rays(cell)
	_synthetic_grid_geometry()

func _synthetic_triangle_rays(terrain: WarTerrainSurface) -> void:
	# Native triangle intersections are an independent oracle for the field ray.
	var a := Vector3(-1, 0, -1)
	var b := Vector3(1, 2, -1)
	var c := Vector3(-1, 4, 1)
	var d := Vector3(1, 10, 1)
	for index: int in 30:
		var target := Vector3(-0.7 + (index % 6) * 0.24, 0, -0.7 + (index / 6) * 0.3)
		var start := target + Vector3(0.7, 20, 0.4)
		var direction := Vector3(-0.035, -1, -0.02).normalized()
		var expected := Vector3.INF
		for triangle: Array in [[a, b, c], [b, d, c]]:
			var candidate: Variant = Geometry3D.ray_intersects_triangle(start, direction, triangle[0], triangle[1], triangle[2])
			if candidate != null and (not expected.is_finite() or start.distance_squared_to(candidate) < start.distance_squared_to(expected)):
				expected = candidate
		var actual := terrain.ray_ground(start, direction)
		check(expected.is_finite() and actual.distance_to(expected) < TOLERANCE, "DDA ray matches native triangle geometry for interior, diagonal and border crossings")

func _synthetic_grid_geometry() -> void:
	var terrain := _surface(9, 9, func(x: float, z: float): return (1.0 - absf(x) / 2.0) * (1.0 - absf(z) / 2.0) * (1.2 + 0.4 * sin(x * 3.2) + 0.3 * cos(z * 2.3)), Vector2(-2, -2), 0.5)
	var faces := PackedVector3Array()
	for z: int in range(terrain.depth - 1):
		for x: int in range(terrain.width - 1):
			var points := PackedVector3Array()
			for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var column := x + offset.x
				var row := z + offset.y
				points.append(Vector3(terrain.origin.x + column * terrain.cell_size, terrain.heights[row * terrain.width + column], terrain.origin.y + row * terrain.cell_size))
			for index: int in [0, 2, 1, 1, 2, 3]:
				faces.append(points[index])
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7412
	var first_ray_error := ""
	var first_segment_error := ""
	for trial: int in 384:
		var start := Vector3(rng.randf_range(-6, 6), rng.randf_range(0.3, 8.0), rng.randf_range(-6, 6))
		var target := Vector3(rng.randf_range(-1.9, 1.9), 0, rng.randf_range(-1.9, 1.9))
		var direction := (target - start).normalized()
		match trial % 6:
			0:
				start.x = target.x
				start.z = target.z
				direction = Vector3.DOWN
			2:
				start = Vector3(-5, rng.randf_range(0.3, 1.6), rng.randf_range(-1.5, 1.5))
				direction = Vector3(1, rng.randf_range(-0.12, 0.12), rng.randf_range(-0.2, 0.2)).normalized()
			3:
				start.y = -2.0
				direction = (target - start).normalized()
			4:
				start.x = 4.0
				direction = Vector3.DOWN
			5:
				direction = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var expected := Vector3.INF
		for index: int in range(0, faces.size(), 3):
			var candidate: Variant = Geometry3D.ray_intersects_triangle(start, direction, faces[index], faces[index + 1], faces[index + 2])
			if candidate != null and (not expected.is_finite() or start.distance_squared_to(candidate) < start.distance_squared_to(expected)):
				expected = candidate
		var base: Variant = Plane(Vector3.UP, 0).intersects_ray(start, direction)
		if base != null and (absf(base.x) > 2.0 or absf(base.z) > 2.0) and (not expected.is_finite() or start.distance_squared_to(base) < start.distance_squared_to(expected)):
			expected = base
		var actual := terrain.ray_ground(start, direction)
		if actual.is_finite() != expected.is_finite() or (actual.is_finite() and actual.distance_to(expected) > TOLERANCE):
			if first_ray_error.is_empty():
				first_ray_error = "trial %d start=%s direction=%s actual=%s expected=%s" % [trial, start, direction, actual, expected]
		var from := Vector2(rng.randf_range(-1.99, 1.99), rng.randf_range(-1.99, 1.99))
		var to := Vector2(rng.randf_range(-1.99, 1.99), rng.randf_range(-1.99, 1.99))
		if terrain.segment_walkable(from, to) != terrain.segment_walkable(to, from) and first_segment_error.is_empty():
			first_segment_error = "opposite directions disagree at %s -> %s" % [from, to]
		var cuts := terrain.breakpoints(from, to)
		for index: int in range(1, cuts.size()):
			var a := from.lerp(to, cuts[index - 1])
			var b := from.lerp(to, cuts[index])
			for ratio: float in [0.2, 0.5, 0.8]:
				if absf(terrain.sample(a.lerp(b, ratio)) - lerpf(terrain.sample(a), terrain.sample(b), ratio)) > TOLERANCE and first_segment_error.is_empty():
					first_segment_error = "a breakpoint interval contains more than one plane: %s -> %s" % [a, b]
	check(first_ray_error.is_empty(), "384 multicell rays agree with brute-force native geometry: " + first_ray_error)
	check(first_segment_error.is_empty(), "384 segment walks are symmetric and split into single planes: " + first_segment_error)

func _route_error(route: PackedVector3Array, definition: WarMapDefinition) -> String:
	if route.size() < 2:
		return "missing route"
	if route.size() > 2048:
		return "route exceeds the multiplayer snapshot point limit"
	for index: int in route.size():
		var point := route[index]
		if not point.is_finite() or absf(point.y - definition.surface_height(Vector2(point.x, point.z))) > TOLERANCE:
			return "route vertex is off the terrain at %s" % point
		if index == 0:
			continue
		var before := route[index - 1]
		var span := point - before
		if span.length() > 0.251:
			return "surface samples are too far apart: %.4f" % span.length()
		if absf(span.y) > Vector2(span.x, span.z).length() * 0.501 + TOLERANCE:
			return "route climbs a cliff between %s and %s" % [before, point]
		var middle := (point + before) * 0.5
		if absf(middle.y - definition.surface_height(Vector2(middle.x, middle.z))) > TOLERANCE:
			return "route interpolation cuts below or above terrain at %s" % middle
	return ""

func _index_surface_mesh(mesh: MeshInstance3D) -> void:
	terrain_faces = mesh.mesh.get_faces()
	terrain_buckets.clear()
	terrain_steep_samples.clear()
	terrain_steep_faces = 0
	terrain_ramp_faces = 0
	for index: int in terrain_faces.size():
		terrain_faces[index] = mesh.to_global(terrain_faces[index])
	for index: int in range(0, terrain_faces.size(), 3):
		var a := terrain_faces[index]
		var b := terrain_faces[index + 1]
		var c := terrain_faces[index + 2]
		var normal := (b - a).cross(c - a)
		var gradient := Vector2(normal.x, normal.z).length() / absf(normal.y)
		if gradient > 0.501:
			terrain_steep_faces += 1
			if terrain_steep_samples.size() < 16:
				terrain_steep_samples.append(Vector2((a.x + b.x + c.x) / 3.0, (a.z + b.z + c.z) / 3.0))
		elif gradient > 0.03:
			terrain_ramp_faces += 1
		var low := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z))) / MESH_BUCKET_SIZE
		var high := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z))) / MESH_BUCKET_SIZE
		for x: int in range(floori(low.x), floori(high.x) + 1):
			for z: int in range(floori(low.y), floori(high.y) + 1):
				var bucket := Vector2i(x, z)
				if not terrain_buckets.has(bucket):
					terrain_buckets[bucket] = []
				terrain_buckets[bucket].append(index)

func _mesh_height(point: Vector2) -> float:
	var height := -INF
	var bucket := Vector2i(floori(point.x / MESH_BUCKET_SIZE), floori(point.y / MESH_BUCKET_SIZE))
	for index: int in terrain_buckets.get(bucket, []):
		var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(point.x, 100, point.y), Vector3.DOWN, terrain_faces[index], terrain_faces[index + 1], terrain_faces[index + 2])
		if hit != null:
			height = maxf(height, hit.y)
	return height

func _check_ground_point(definition: WarMapDefinition, point: Vector2, label: String) -> void:
	var height := definition.surface_height(point)
	check(absf(_mesh_height(point) - height) < TOLERANCE, label + " rendered triangles match the simulation surface")
	var hit := definition.ray_ground(Vector3(point.x, 100, point.y), Vector3.DOWN)
	check(hit.is_finite() and hit.distance_to(Vector3(point.x, height, point.y)) < TOLERANCE, label + " picking matches the rendered surface")

func _authored_ground(definition: WarMapDefinition) -> void:
	var terrain := definition.terrain
	var upland: MeshInstance3D = game.map.get_node("Terrain/Upland")
	check(upland.mesh != null and upland.mesh.get_faces().size() > 0, "native scene contains the baked terrain mesh")
	_index_surface_mesh(upland)
	check(terrain.width >= 2 and terrain.depth >= 2 and terrain.heights.size() == terrain.width * terrain.depth, "height dimensions match the resource's sample count")
	check(terrain.cell_size <= 0.5 and terrain.cell_size > 0.0, "the natural terrain retains at least half-metre sampling")
	check(terrain.bounds().position.is_equal_approx(definition.camera_bounds.position) and terrain.bounds().end.is_equal_approx(definition.camera_bounds.end), "the height field covers the camera's entire rendered ground")
	check(terrain.height_texture != null and terrain.preview_texture != null, "GPU effects and the picker use baked terrain textures")
	var image := terrain.height_texture.get_image()
	check(image.get_format() == Image.FORMAT_RF and image.get_width() == terrain.width and image.get_height() == terrain.depth, "GPU heights use full-precision RF data with matching dimensions")
	var texture_error := ""
	var measured_max := -INF
	for height: float in terrain.heights:
		measured_max = maxf(measured_max, height)
	for index: int in range(0, terrain.heights.size(), maxi(1, terrain.heights.size() / 127)):
		var x := index % terrain.width
		var z: int = index / terrain.width
		if absf(image.get_pixel(x, z).r - terrain.heights[index]) > 0.00001:
			texture_error = "RF pixel (%d, %d) disagrees with CPU data" % [x, z]
	check(texture_error.is_empty(), texture_error if not texture_error.is_empty() else "CPU and GPU consume identical stored heights")
	check(absf(measured_max - terrain.max_height) < TOLERANCE, "the stored maximum encloses every rendered height")
	check(terrain.label_positions.size() > 0 and terrain.ramp_guides.size() > 0, "the map has authored high ground and access ramps")
	for point: Vector3 in terrain.label_positions:
		check(absf(definition.surface_height(Vector2(point.x, point.z)) - point.y) < TOLERANCE, "high-ground labels carry the actual terrain elevation")
		_check_ground_point(definition, Vector2(point.x, point.z), "high ground")
	for guide: Vector4 in terrain.ramp_guides:
		var start := Vector2(guide.x, guide.y)
		var finish := Vector2(guide.z, guide.w)
		check(terrain.segment_walkable(start, finish) and terrain.segment_walkable(finish, start), "authored ramp centerlines remain walkable in both directions")
		var clearance_error := ""
		var steps := maxi(1, ceili(start.distance_to(finish) / 0.25))
		for step: int in range(steps + 1):
			var point := start.lerp(finish, float(step) / steps)
			var center := Vector3(point.x, terrain.sample(point), point.y)
			if not game.map._has_clearance(center) and clearance_error.is_empty():
				clearance_error = "formation blocked at %s" % point
		check(clearance_error.is_empty(), "ramp tread and neighboring yard transitions preserve full formation clearance: " + clearance_error)
		for ratio: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
			_check_ground_point(definition, start.lerp(finish, ratio), "ramp")
	# Sample the actual baked faces rather than only testing author metadata.
	var stride := maxi(1, terrain_faces.size() / (3 * 101)) * 3
	for index: int in range(0, terrain_faces.size(), stride):
		var point := (terrain_faces[index] + terrain_faces[index + 1] + terrain_faces[index + 2]) / 3.0
		var xz := Vector2(point.x, point.z)
		check(absf(terrain.sample(xz) - point.y) < TOLERANCE, "native triangle centroids agree with the CPU interpolation convention")
		var normal := (terrain_faces[index + 1] - terrain_faces[index]).cross(terrain_faces[index + 2] - terrain_faces[index])
		var mesh_gradient := -Vector2(normal.x, normal.z) / normal.y
		check(terrain.gradient_at(xz).distance_to(mesh_gradient) < TOLERANCE, "walkability uses the native triangle's actual slope")
	for point: Vector2 in terrain_steep_samples:
		check(not definition.is_walkable(point), "steep rock faces cannot become marching shortcuts")
	check(terrain_steep_faces > 0, "the natural relief includes real non-walkable cliff faces")
	check(terrain_ramp_faces > 0, "the natural relief includes gradual non-flat ground")

func _building_sites(definition: WarMapDefinition) -> void:
	check(game.buildings.size() == definition.building_positions.size(), "native scene and map preview have the same building count")
	var starters := PackedInt32Array()
	starters.resize(definition.team_size * 2)
	for building: WarBuilding in game.buildings:
		var point := building.global_position
		check(point.is_equal_approx(definition.building_positions[building.building_id]), "the native building uses the authored position")
		check(absf(point.y - definition.surface_height(Vector2(point.x, point.z))) < TOLERANCE, "the building's feet are on the ground")
		var level_seat := true
		# Leave room for the walkability probe inside the open six-metre safety disk.
		for radius: float in [2.5, 4.0, 5.95]:
			for step: int in 64:
				var sample := Vector2(point.x, point.z) + Vector2.from_angle(step * TAU / 64.0) * radius
				if absf(definition.surface_height(sample) - point.y) > TOLERANCE or not definition.is_walkable(sample):
					level_seat = false
		check(level_seat, "building %d has a flat six-metre safety footprint" % building.building_id)
		if building.faction >= 0:
			starters[building.faction] += 1
			check(building.kind == 0 and building.level == 1 and building.population == 60.0, "all commanders start with equal homes and garrisons")
	for count: int in starters:
		check(count == 1, "each participating commander has exactly one home")
	check(game.team_total_for(0) == game.team_total_for(1), "both sides have the same initial unit total")

func _mirrored_id(point: Vector3) -> int:
	var mirrored := Vector3(-point.x, point.y, point.z)
	for building: WarBuilding in game.buildings:
		if building.global_position.distance_to(mirrored) < TOLERANCE:
			return building.building_id
	return -1

func _fairness(definition: WarMapDefinition) -> void:
	var geometry_equal := true
	for x: int in range(0, int(definition.half_size.x), 2):
		for z: int in range(-int(definition.half_size.y), int(definition.half_size.y), 2):
			var left := Vector2(-x, z)
			var right := Vector2(x, z)
			if absf(definition.surface_height(left) - definition.surface_height(right)) > TOLERANCE:
				geometry_equal = false
	check(geometry_equal, "both teams receive mirrored authored height samples")
	for source: WarBuilding in game.buildings:
		var mirrored_source := _mirrored_id(source.global_position)
		check(mirrored_source >= 0, "every building has a geometrically mirrored counterpart")
		if mirrored_source < 0:
			continue
		var opposite: WarBuilding = game.buildings[mirrored_source]
		check(source.kind == opposite.kind and source.level == opposite.level and source.population == opposite.population, "mirrored buildings have matching economic and defensive value")
		if source.faction < 0 or source.faction % 2 != 0:
			continue
		for target: WarBuilding in game.buildings:
			if target == source:
				continue
			var mirrored_target := _mirrored_id(target.global_position)
			if mirrored_target < 0:
				continue
			var distance: float = game.map.get_building_distance(source, target)
			var opposing_distance: float = game.map.get_building_distance(opposite, game.buildings[mirrored_target])
			check(absf(distance - opposing_distance) <= maxf(2.0, distance * 0.08), "mirrored starts have comparable travel cost to building %d" % target.building_id)

func _formation_error(order: WarMarches.MarchOrder, definition: WarMapDefinition) -> String:
	for step: int in range(ceili(order.length * 2.0) + 1):
		for unit: WarMarches.MarchUnit in game.marches._units:
			unit.distance = minf(order.length, step * 0.5)
			game.marches._update_pose(unit)
			var point := unit.position
			if absf(point.y - definition.surface_height(Vector2(point.x, point.z))) > TOLERANCE:
				return "lane %.2f floats or sinks at %s" % [unit.lane, point]
			if not game.map.is_walkable(point):
				return "lane %.2f enters blocked ground at %s" % [unit.lane, point]
			var basis := Basis(Vector3.UP, atan2(-unit.heading.x, -unit.heading.z)).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
			for corner: Vector3 in FOOTPRINT:
				var edge := point + basis * corner
				if not game.map.is_walkable(edge):
					return "a soldier footprint leaves traversable land at %s" % edge
				# Independent height-rise bound catches a body straddling a cliff.
				var height: float = definition.surface_height(Vector2(edge.x, edge.z))
				if absf(height - point.y) > Vector2(edge.x - point.x, edge.z - point.z).length() * 0.501 + TOLERANCE:
					return "a soldier straddles a cliff at %s" % edge
	return ""

func _routes(definition: WarMapDefinition) -> void:
	var pairs := 0
	var elevated := 0
	for source: WarBuilding in game.buildings:
		for target: WarBuilding in game.buildings:
			if source.building_id >= target.building_id:
				continue
			pairs += 1
			var route: PackedVector3Array = game.map.get_building_route(source, target)
			var label := "%d -> %d" % [source.building_id, target.building_id]
			var route_error := _route_error(route, definition)
			check(route_error.is_empty(), label + " surface route: " + route_error)
			if route.size() < 2:
				continue
			var reverse: PackedVector3Array = game.map.get_building_route(target, source)
			reverse.reverse()
			check(route == reverse, label + " uses the same corridor in both directions")
			var length := 0.0
			var flat_length := 0.0
			for index: int in range(1, route.size()):
				length += route[index].distance_to(route[index - 1])
				flat_length += Vector2(route[index].x, route[index].z).distance_to(Vector2(route[index - 1].x, route[index - 1].z))
			if length > flat_length + 0.1:
				elevated += 1
			check(absf(game.map.get_building_distance(source, target) - length) < 0.02, label + " AI distance measures actual three-dimensional travel")
			game.marches.clear()
			game.marches.send(source.building_id, target.building_id, 0, 6, route)
			var order: WarMarches.MarchOrder = game.marches._units[0].order
			check(absf(order.length - length) < 0.04, label + " rendered marching curve agrees with the saved route length")
			var formation_error := _formation_error(order, definition)
			check(formation_error.is_empty(), label + " six-column formation: " + formation_error)
			# A returning outer file must rejoin the same surface guide safely.
			if source.faction >= 0 and target.global_position.y > 0:
				var unit: WarMarches.MarchUnit = game.marches._units[0]
				unit.distance = order.length * 0.6
				game.marches._update_pose(unit)
				var returning: PackedVector3Array = game.map.get_return_route(unit.position, source, target)
				var return_error := _route_error(returning, definition)
				check(return_error.is_empty(), label + " recall across levels: " + return_error)
				if returning.size() >= 2:
					check(returning[0].distance_to(unit.position) < TOLERANCE and returning[-1].distance_to(route[0]) < TOLERANCE, label + " recall begins at the soldier and ends at its original doorway")
	game.marches.clear()
	check(elevated > 0, "real routes use the ramps and include their added travel distance")
	print("WAR_HEIGHTS ", definition.map_id, " pairs=", pairs, " elevated=", elevated)

func _run() -> void:
	create_timer(240.0, true, false, true).timeout.connect(func(): quit(3))
	_synthetic_ground()
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	var arguments := OS.get_cmdline_user_args()
	var selected_maps: Array[String] = []
	for argument: String in arguments:
		if argument in MAP_IDS:
			selected_maps.append(argument)
	for map_id: String in MAP_IDS:
		if "synthetic" in arguments or (not selected_maps.is_empty() and map_id not in selected_maps):
			continue
		scenario = map_id
		session.block_war_map_id = map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		var definition: WarMapDefinition = game.map.definition
		check(definition.map_id == map_id and definition.has_elevation(), "the selected height map loads through the real match")
		check(game.marches.map_definition == definition, "all formation lanes use this match's terrain")
		_authored_ground(definition)
		_building_sites(definition)
		if "geometry" not in arguments:
			_fairness(definition)
			_routes(definition)
		await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("BLOCK_WAR_HEIGHTS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
