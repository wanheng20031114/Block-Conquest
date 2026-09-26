extends SceneTree
## Offline authoring; no runtime nodes or navigation edits.
## Run: Godot.exe --headless --path . --script tools/bake_block_war_shores.gd
## Inputs: data/block_war/maps/{lake,rivers,ridges,islands,highland}.tres.
## Outputs, for each map with water:
## assets/block_war/environment/maps/<id>_{bank_grass,bank_stone,water}.res
## Grass uses the map's ground shader; stone uses its original vertex colors.
## Water is one non-overlapping ArrayMesh. COLOR.r is the shallow-shore weight;
## COLOR.g is the distance to the true waterline in metres, divided by 8.
## Native APIs: SurfaceTool generates normals/indexed meshes and ResourceSaver
## saves them. Geometry2D.get_closest_point_to_segment measures the actual shore.
## https://docs.godotengine.org/en/stable/classes/class_surfacetool.html
## https://docs.godotengine.org/en/stable/classes/class_geometry2d.html

const OUTPUT := "res://assets/block_war/environment/maps/"
const MAP_IDS := ["lake", "rivers", "ridges", "islands", "highland"]
const SHORE_STEP := 0.5
const WATER_STEP := 0.75
const WATER_HEIGHT := -1.18
const CORNER_RADIUS := 3.2


func _initialize() -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK)
	for map_id: String in MAP_IDS:
		var definition: WarMapDefinition = load("res://data/block_war/maps/%s.tres" % map_id)
		if definition.water_regions.is_empty():
			continue
		_bake_map(definition)
	print("Saved sculpted union shorelines and water meshes for four block-war maps")
	quit()


func _bake_map(definition: WarMapDefinition) -> void:
	var axes := _region_axes(definition.water_regions)
	var outlines := _union_outlines(axes[0], axes[1], definition.water_regions)
	var turf := _surface()
	var stone := _surface()
	var waterline_segments: Array[PackedVector2Array] = []
	var lake_region := definition.water_regions[0] if definition.map_id in ["lake", "highland"] else Rect2()
	for outline: PackedVector2Array in outlines:
		var rows := _shore_rows(outline, definition.bridges, lake_region)
		for station in rows.size():
			var next := (station + 1) % rows.size()
			var midpoint: Vector3 = (rows[station][3] + rows[next][3]) * 0.5
			for band in 5:
				var tint := Color.WHITE
				if band >= 3:
					tint = Color(0.49, 0.46, 0.32).lerp(Color(0.34, 0.39, 0.30), float(band - 3) * 0.6)
					tint = tint.lightened(0.055 * sin(midpoint.x * 0.31 + midpoint.z * 0.86))
				_quad(turf if band < 3 else stone, rows[station][band], rows[next][band], rows[next][band + 1], rows[station][band + 1], tint)
			# Water intersects the last rock band, not the rectangular nav boundary.
			waterline_segments.append(PackedVector2Array([
				_waterline_point(rows[station]), _waterline_point(rows[next]),
			]))
	_save(definition.map_id + "_bank_grass", _finish(turf))
	_save(definition.map_id + "_bank_stone", _finish(stone))
	_save(definition.map_id + "_water", _water_mesh(axes, definition.water_regions, waterline_segments))
	print("Baked %s: %d outer/hole contours, %d shore segments" % [definition.map_id, outlines.size(), waterline_segments.size()])


func _region_axes(regions: Array[Rect2]) -> Array[PackedFloat32Array]:
	var x_values: Array[float] = []
	var z_values: Array[float] = []
	for region in regions:
		for value: float in [region.position.x, region.end.x]:
			if not x_values.has(value):
				x_values.append(value)
		for value: float in [region.position.y, region.end.y]:
			if not z_values.has(value):
				z_values.append(value)
	x_values.sort()
	z_values.sort()
	return [PackedFloat32Array(x_values), PackedFloat32Array(z_values)]


func _inside_water(point: Vector2, regions: Array[Rect2]) -> bool:
	for region in regions:
		if region.has_point(point):
			return true
	return false


func _union_outlines(xs: PackedFloat32Array, zs: PackedFloat32Array, regions: Array[Rect2]) -> Array[PackedVector2Array]:
	# Rectangle endpoints partition the union exactly. Only wet/dry interfaces
	# survive; touching and overlapping rectangles never create internal banks.
	var wet_cells: Dictionary = {}
	for x in xs.size() - 1:
		for z in zs.size() - 1:
			if _inside_water(Vector2((xs[x] + xs[x + 1]) * 0.5, (zs[z] + zs[z + 1]) * 0.5), regions):
				wet_cells[Vector2i(x, z)] = true
	var edges: Dictionary = {}
	for cell: Vector2i in wet_cells:
		var x := cell.x
		var z := cell.y
		# Directed edges keep water to their left, including island/hole contours.
		if not wet_cells.has(cell + Vector2i(0, -1)):
			_add_edge(edges, Vector2(xs[x], zs[z]), Vector2(xs[x + 1], zs[z]))
		if not wet_cells.has(cell + Vector2i(1, 0)):
			_add_edge(edges, Vector2(xs[x + 1], zs[z]), Vector2(xs[x + 1], zs[z + 1]))
		if not wet_cells.has(cell + Vector2i(0, 1)):
			_add_edge(edges, Vector2(xs[x + 1], zs[z + 1]), Vector2(xs[x], zs[z + 1]))
		if not wet_cells.has(cell + Vector2i(-1, 0)):
			_add_edge(edges, Vector2(xs[x], zs[z + 1]), Vector2(xs[x], zs[z]))
	var outlines: Array[PackedVector2Array] = []
	while not edges.is_empty():
		var start: Vector2 = edges.keys()[0]
		var current := start
		var outline := PackedVector2Array()
		while true:
			outline.append(current)
			assert(edges.has(current), "Water union must have closed shore contours")
			var next: Vector2 = edges[current]
			edges.erase(current)
			current = next
			if current == start:
				break
		outlines.append(_without_collinear_points(outline))
	return outlines


func _add_edge(edges: Dictionary, start: Vector2, end: Vector2) -> void:
	assert(not edges.has(start), "Water regions must not touch only at a diagonal corner")
	edges[start] = end


func _without_collinear_points(outline: PackedVector2Array) -> PackedVector2Array:
	var simplified := PackedVector2Array()
	for i in outline.size():
		var incoming := outline[i] - outline[posmod(i - 1, outline.size())]
		var outgoing := outline[(i + 1) % outline.size()] - outline[i]
		if absf(incoming.cross(outgoing)) > 0.001:
			simplified.append(outline[i])
	return simplified


func _shore_rows(outline: PackedVector2Array, bridges: Array[Rect2], lake_region: Rect2) -> Array[PackedVector3Array]:
	var radii := PackedFloat32Array()
	for i in outline.size():
		var previous := outline[posmod(i - 1, outline.size())]
		var next := outline[(i + 1) % outline.size()]
		var incoming := outline[i] - previous
		var outgoing := next - outline[i]
		# Convex water corners fill inward with a curved turf lip. The first ring
		# still follows the exact rectangular land edge, so no crack can open.
		var radius := minf(CORNER_RADIUS, minf(incoming.length(), outgoing.length()) * 0.38) if incoming.cross(outgoing) > 0.0 else 0.0
		if lake_region.has_area() and radius > 0.0:
			# Broad lakes need differently sized coves, not four identical fillets.
			var variation := 0.33 + 0.075 * sin(outline[i].x * 0.11 + outline[i].y * 0.17 + 0.7)
			radius = minf(minf(incoming.length(), outgoing.length()) * 0.44, minf(lake_region.size.x, lake_region.size.y) * variation)
		radii.append(radius)
	var rows: Array[PackedVector3Array] = []
	for i in outline.size():
		var corner := outline[i]
		var previous := outline[posmod(i - 1, outline.size())]
		var next := outline[(i + 1) % outline.size()]
		var incoming := (corner - previous).normalized()
		var outgoing := (next - corner).normalized()
		var inward := Vector2(-outgoing.y, outgoing.x)
		var radius := radii[i]
		if radius > 0.0:
			# Include ratio 0.5 exactly: the outer ring must retain the original
			# rectangle corner instead of cutting a tiny diagonal across the land.
			var corner_steps := maxi(2, ceili(radius / SHORE_STEP) * 2)
			for step in corner_steps:
				rows.append(_convex_corner_row(corner, incoming, outgoing, radius, float(step) / corner_steps, bridges, lake_region))
		else:
			# Around a projecting land corner the offset rows form a quarter arc.
			var incoming_normal := Vector2(-incoming.y, incoming.x)
			for step in 6:
				rows.append(_straight_row(corner, incoming_normal.rotated(-PI * 0.5 * float(step) / 6.0), bridges, lake_region))
		var straight_start := corner + outgoing * radius
		var straight_end := next - outgoing * radii[(i + 1) % outline.size()]
		var steps := maxi(1, ceili(straight_start.distance_to(straight_end) / SHORE_STEP))
		for step in steps:
			rows.append(_straight_row(straight_start.lerp(straight_end, float(step) / steps), inward, bridges, lake_region))
	return rows


func _bank_reach(point: Vector2, bridges: Array[Rect2]) -> float:
	var waves := 0.72 + 0.33 * sin(point.y * 0.25 + point.x * 0.19) + 0.22 * cos(point.y * 0.64 - point.x * 0.37)
	var approach := 1.0
	for bridge in bridges:
		var closest := Vector2(clampf(point.x, bridge.position.x, bridge.end.x), clampf(point.y, bridge.position.y, bridge.end.y))
		approach = minf(approach, smoothstep(0.4, 2.6, point.distance_to(closest)))
	return 0.08 + waves * approach


func _lake_shelf(point: Vector2, region: Rect2, bridges: Array[Rect2]) -> float:
	if not region.has_area():
		return 0.0
	# Asymmetric broad grass promontories make sheltered bays between them.
	# This continuous field also joins the rounded corners without a seam.
	var uv := (point - region.get_center()) / (region.size * 0.5)
	var lobes := 0.10
	lobes += 1.15 * _shelf_lobe(uv, Vector2(-1.0, -0.27), Vector2(0.34, 0.42))
	lobes += 0.86 * _shelf_lobe(uv, Vector2(1.0, 0.34), Vector2(0.38, 0.35))
	lobes += 0.60 * _shelf_lobe(uv, Vector2(0.22, -1.0), Vector2(0.42, 0.31))
	lobes += 0.90 * _shelf_lobe(uv, Vector2(-0.35, 1.0), Vector2(0.45, 0.33))
	var approach := 1.0
	for bridge in bridges:
		var closest := Vector2(clampf(point.x, bridge.position.x, bridge.end.x), clampf(point.y, bridge.position.y, bridge.end.y))
		approach = minf(approach, smoothstep(0.9, 6.5, point.distance_to(closest)))
	return minf(5.5, minf(region.size.x, region.size.y) * 0.14) * lobes * approach


func _shelf_lobe(point: Vector2, center: Vector2, width: Vector2) -> float:
	var offset := (point - center) / width
	return exp(-offset.length_squared())


func _profile(point: Vector2, bridges: Array[Rect2], lake_region: Rect2) -> PackedVector2Array:
	# Same six grass/stone levels and colors as bake_war_map_details.gd.
	var reach := _bank_reach(point, bridges)
	var shelf := _lake_shelf(point, lake_region, bridges)
	var ripple := 0.035 * sin(point.y * 3.2 + point.x * 1.7) + 0.022 * cos(point.y * 5.4 - point.x * 2.1)
	return PackedVector2Array([
		Vector2(0.0, 0.009),
		Vector2(shelf + reach * 0.45, 0.025 + ripple),
		Vector2(shelf + reach * 0.75, -0.16 + ripple),
		Vector2(shelf + reach + 0.03, -0.49 + ripple),
		Vector2(shelf + reach + 0.40, -0.96),
		Vector2(shelf + reach + 0.69, -1.65),
	])


func _straight_row(point: Vector2, inward: Vector2, bridges: Array[Rect2], lake_region: Rect2) -> PackedVector3Array:
	var row := PackedVector3Array()
	for level: Vector2 in _profile(point, bridges, lake_region):
		var position := point + inward * level.x
		row.append(Vector3(position.x, level.y, position.y))
	return row


func _convex_corner_row(corner: Vector2, incoming: Vector2, outgoing: Vector2, radius: float, ratio: float, bridges: Array[Rect2], lake_region: Rect2) -> PackedVector3Array:
	var incoming_normal := Vector2(-incoming.y, incoming.x)
	var outgoing_normal := Vector2(-outgoing.y, outgoing.x)
	var center := corner + (incoming_normal + outgoing_normal) * radius
	var radial := (-incoming_normal).rotated(PI * 0.5 * ratio)
	var curve_point := center + radial * radius
	var edge_point := corner - incoming * radius * (1.0 - 2.0 * ratio) if ratio <= 0.5 else corner + outgoing * radius * (2.0 * ratio - 1.0)
	var row := PackedVector3Array([Vector3(edge_point.x, 0.009, edge_point.y)])
	var profile := _profile(curve_point, bridges, lake_region)
	for band in range(1, 6):
		assert(profile[band].x < radius, "Corner radius must exceed the submerged rock profile")
		var point := center + radial * (radius - profile[band].x)
		row.append(Vector3(point.x, profile[band].y, point.y))
	return row


func _waterline_point(row: PackedVector3Array) -> Vector2:
	var point := row[4].lerp(row[5], (WATER_HEIGHT - row[4].y) / (row[5].y - row[4].y))
	return Vector2(point.x, point.z)


func _subdivide_axis(values: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in values.size() - 1:
		var steps := ceili((values[i + 1] - values[i]) / WATER_STEP)
		for step in steps:
			result.append(lerpf(values[i], values[i + 1], float(step) / steps))
	result.append(values[values.size() - 1])
	return result


func _water_mesh(axes: Array[PackedFloat32Array], regions: Array[Rect2], shore: Array[PackedVector2Array]) -> ArrayMesh:
	var xs := _subdivide_axis(axes[0])
	var zs := _subdivide_axis(axes[1])
	var surface := _surface()
	var color_cache: Dictionary = {}
	for x in xs.size() - 1:
		for z in zs.size() - 1:
			if not _inside_water(Vector2((xs[x] + xs[x + 1]) * 0.5, (zs[z] + zs[z + 1]) * 0.5), regions):
				continue
			var corners := PackedVector2Array([
				Vector2(xs[x], zs[z]), Vector2(xs[x + 1], zs[z]),
				Vector2(xs[x + 1], zs[z + 1]), Vector2(xs[x], zs[z + 1]),
			])
			# Every union cell is emitted once, even at T junctions/overlaps.
			for corner_index in [0, 1, 2, 0, 2, 3]:
				var point := corners[corner_index]
				if not color_cache.has(point):
					color_cache[point] = _shore_color(point, shore)
				surface.set_color(color_cache[point])
				surface.add_vertex(Vector3(point.x, WATER_HEIGHT, point.y))
	return _finish(surface)


func _shore_color(point: Vector2, shore: Array[PackedVector2Array]) -> Color:
	var distance_squared := INF
	for segment in shore:
		var closest := Geometry2D.get_closest_point_to_segment(point, segment[0], segment[1])
		distance_squared = minf(distance_squared, point.distance_squared_to(closest))
	var distance := sqrt(distance_squared)
	return Color(1.0 - smoothstep(0.15, 2.7, distance), minf(distance / 8.0, 1.0), 0.0, 1.0)


func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	surface.index()
	return surface.commit()


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.00000001:
		return
	if normal.dot(Vector3.UP) > 0.0:
		var swap := b
		b = c
		c = swap
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(tint)
		surface.add_vertex(vertex)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, tint: Color) -> void:
	_triangle(surface, a, b, c, tint)
	_triangle(surface, a, c, d, tint)


func _save(asset_name: String, mesh: ArrayMesh) -> void:
	assert(ResourceSaver.save(mesh, OUTPUT + asset_name + ".res") == OK)
