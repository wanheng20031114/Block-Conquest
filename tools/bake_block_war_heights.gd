extends SceneTree
## Offline native meshes: flat building seats, planar earth ramps and layered cliff faces.
## The exact same authored zones supply navigation, input picking and surface effects.
## https://docs.godotengine.org/en/stable/classes/class_surfacetool.html

const OUTPUT := "res://assets/block_war/environment/maps/"

func _initialize() -> void:
	for map_id: String in ["terraces", "switchback", "crown"]:
		if not OS.get_cmdline_user_args().is_empty() and map_id not in OS.get_cmdline_user_args():
			continue
		var definition: WarMapDefinition = load("res://data/block_war/maps/%s.tres" % map_id)
		_bake(definition)
	quit()

func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	if normal.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for point: Vector3 in [a, b, c]:
		surface.set_color(tint)
		surface.add_vertex(point)

func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, tint: Color) -> void:
	_triangle(surface, a, b, c, normal, tint)
	_triangle(surface, a, c, d, normal, tint)

func _finish(surface: SurfaceTool, path: String) -> void:
	surface.generate_normals()
	surface.index()
	assert(ResourceSaver.save(surface.commit(), path, ResourceSaver.FLAG_COMPRESS) == OK)

func _height(zone: WarHeightZone, point: Vector2) -> float:
	var t := (point.x - zone.region.position.x) / zone.region.size.x if zone.axis == 0 else (point.y - zone.region.position.y) / zone.region.size.y
	return lerpf(zone.start_height, zone.end_height, clampf(t, 0.0, 1.0))

func _vertex(zone: WarHeightZone, point: Vector2) -> Vector3:
	return Vector3(point.x, _height(zone, point), point.y)

func _bake(definition: WarMapDefinition) -> void:
	var top := _surface()
	var cliffs := _surface()
	for zone: WarHeightZone in definition.height_zones:
		var rect := zone.region
		var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		_quad(top, _vertex(zone, corners[0]), _vertex(zone, corners[1]), _vertex(zone, corners[2]), _vertex(zone, corners[3]), Vector3.UP, Color.WHITE)
		for edge: int in 4:
			var start := corners[edge]
			var end := corners[(edge + 1) % 4]
			var direction := end - start
			var length := direction.length()
			var outward := Vector2(direction.y, -direction.x).normalized()
			var cuts: Array[float] = [0.0, 1.0]
			for index: int in range(1, ceili(length)):
				cuts.append(float(index) / ceili(length))
			# Adjacent ramps can occupy only part of a cliff: split exactly at mouths.
			for neighbor: WarHeightZone in definition.height_zones:
				for point: Vector2 in [neighbor.region.position, neighbor.region.end]:
					var t := (point.x - start.x) / direction.x if absf(direction.x) > 0.01 else (point.y - start.y) / direction.y
					if t > 0.0 and t < 1.0 and not cuts.has(t):
						cuts.append(t)
			cuts.sort()
			for index: int in range(1, cuts.size()):
				var a := start.lerp(end, cuts[index - 1])
				var b := start.lerp(end, cuts[index])
				var middle := (a + b) * 0.5
				var adjacent := definition.surface_height(middle + outward * 0.01)
				if _height(zone, middle) - adjacent < 0.01:
					continue
				var low_a := definition.surface_height(a.lerp(middle, 0.001) + outward * 0.01)
				var low_b := definition.surface_height(b.lerp(middle, 0.001) + outward * 0.01)
				_cliff_strip(cliffs, a, b, low_a, low_b, _height(zone, a), _height(zone, b), outward, cuts[index - 1], cuts[index])
	_finish(top, OUTPUT + definition.map_id + "_upland.res")
	_finish(cliffs, OUTPUT + definition.map_id + "_cliffs.res")
	print("HEIGHTS_BAKED ", definition.map_id, " zones=", definition.height_zones.size())

func _cliff_strip(surface: SurfaceTool, a: Vector2, b: Vector2, low_a: float, low_b: float, high_a: float, high_b: float, outward: Vector2, ta: float, tb: float) -> void:
	var levels: Array[float] = [0.0, 0.15, 0.39, 0.68, 0.94, 1.0]
	var relief: Array[float] = [0.04, 0.17, 0.08, 0.13, 0.06, 0.0]
	var colors: Array[Color] = [Color("686c50"), Color("878163"), Color("79795b"), Color("99906b"), Color("657b42")]
	var normal := Vector3(outward.x, 0, outward.y)
	for band: int in range(levels.size() - 1):
		var vertices: Array[Vector3] = []
		for pair: Vector2i in [Vector2i(0, band), Vector2i(1, band), Vector2i(1, band + 1), Vector2i(0, band + 1)]:
			var point := a if pair.x == 0 else b
			var t := ta if pair.x == 0 else tb
			var h := lerpf(low_a if pair.x == 0 else low_b, high_a if pair.x == 0 else high_b, levels[pair.y])
			# Uneven sediment bands share seam vertices, without moving the actual
			# walkable top or the foot. This avoids a stack-of-boxes cliff face.
			var depth := (high_a - low_a) if pair.x == 0 else (high_b - low_b)
			h += sin(point.x * 0.87 + point.y * 0.53 + pair.y * 1.1) * 0.13 * minf(1.0, depth / 2.0) * sin(PI * levels[pair.y])
			# Taper relief at corners. Every neighboring strip shares identical seams.
			var offset := relief[pair.y] * sin(PI * t) * (0.85 + 0.15 * sin(point.x * 0.73 + point.y * 0.61))
			point += outward * offset
			vertices.append(Vector3(point.x, h, point.y))
		var tint := colors[band].lightened(0.045 * sin((a.x + b.x) * 0.31 + (a.y + b.y) * 0.19))
		_quad(surface, vertices[0], vertices[1], vertices[2], vertices[3], normal, tint)
