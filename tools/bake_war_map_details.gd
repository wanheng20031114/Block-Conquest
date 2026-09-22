extends SceneTree
## Offline authoring only. MeshInstance3D nodes in map.tscn use these saved meshes.
## Godot_console --headless --path . --script tools/bake_war_map_details.gd

const OUTPUT := "res://assets/block_war/environment/"


func _initialize() -> void:
	_save("fieldstone_block", _round_box(Vector3.ONE, 0.12))
	_save("stone_bridge_deck", _round_box(Vector3(8.8, 0.28, 6.4), 0.09))
	_save("stone_bridge_coping", _round_box(Vector3(8.8, 0.3, 0.42), 0.1))
	_save("stone_bridge_pier", _round_box(Vector3(1.1, 2.0, 0.82), 0.14))
	_save("stone_bridge_arch", _bridge_arch())
	_save("stone_bridge_paving", _bridge_paving())
	_save_banks()
	print("Saved eight sculpted meadow, riverbank and stone bridge meshes")
	quit()


func _save(asset_name: String, mesh: ArrayMesh) -> void:
	assert(ResourceSaver.save(mesh, OUTPUT + asset_name + ".res") == OK)


func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface


func _finish(surface: SurfaceTool) -> ArrayMesh:
	surface.generate_normals()
	surface.index()
	return surface.commit()


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, tint: Color = Color.WHITE) -> void:
	if (b - a).cross(c - a).dot(outward) > 0:
		var swap := b
		b = c
		c = swap
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(tint)
		surface.add_vertex(vertex)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, tint: Color = Color.WHITE) -> void:
	_triangle(surface, a, b, c, outward, tint)
	_triangle(surface, a, c, d, outward, tint)


func _round_box(dimensions: Vector3, bevel: float) -> ArrayMesh:
	var surface := _surface()
	surface.set_smooth_group(-1)
	var rings: Array[PackedVector3Array] = []
	for level in 4:
		var inset := bevel if level == 0 or level == 3 else 0.0
		var y: float = [-dimensions.y * 0.5, -dimensions.y * 0.5 + bevel, dimensions.y * 0.5 - bevel, dimensions.y * 0.5][level]
		var half_x := dimensions.x * 0.5 - inset
		var half_z := dimensions.z * 0.5 - inset
		var corner := minf(bevel * 1.5, minf(half_x, half_z) * 0.65)
		var ring := PackedVector3Array()
		for quadrant in 4:
			var sx := 1.0 if quadrant == 0 or quadrant == 3 else -1.0
			var sz := 1.0 if quadrant < 2 else -1.0
			for step in 4:
				var angle := (float(quadrant) + float(step) / 3.0) * PI * 0.5
				ring.append(Vector3(sx * (half_x - corner) + cos(angle) * corner, y, sz * (half_z - corner) + sin(angle) * corner))
		rings.append(ring)
	for level in 3:
		for point in rings[level].size():
			var next := (point + 1) % rings[level].size()
			var outward := (rings[level][point] + rings[level + 1][next]) * Vector3(1, 0, 1)
			_quad(surface, rings[level][point], rings[level][next], rings[level + 1][next], rings[level + 1][point], outward)
	for level in [0, 3]:
		var normal := Vector3.DOWN if level == 0 else Vector3.UP
		for point in rings[level].size():
			_triangle(surface, Vector3(0, rings[level][point].y, 0), rings[level][point], rings[level][(point + 1) % rings[level].size()], normal)
	return _finish(surface)


func _bridge_arch() -> ArrayMesh:
	var surface := _surface()
	# Broad native masonry voussoirs form a real open arch, not a solid box.
	for section in 18:
		var x0 := -4.4 + float(section) * 8.8 / 18.0
		var x1 := -4.4 + float(section + 1) * 8.8 / 18.0
		var bottom0 := -2.05 + 1.50 * pow(maxf(0, 1.0 - pow(x0 / 4.4, 2)), 0.7)
		var bottom1 := -2.05 + 1.50 * pow(maxf(0, 1.0 - pow(x1 / 4.4, 2)), 0.7)
		var tint := Color(0.61, 0.58, 0.46).lerp(Color(0.77, 0.74, 0.61), float((section * 7) % 11) / 18.0)
		for side: float in [-1.0, 1.0]:
			var z := side * 0.36
			_quad(surface, Vector3(x0, bottom0, z), Vector3(x1, bottom1, z), Vector3(x1, -0.08, z), Vector3(x0, -0.08, z), Vector3(0, 0, side), tint)
		_quad(surface, Vector3(x0, bottom0, -0.36), Vector3(x1, bottom1, -0.36), Vector3(x1, bottom1, 0.36), Vector3(x0, bottom0, 0.36), Vector3.DOWN, tint.darkened(0.09))
		_quad(surface, Vector3(x0, -0.08, -0.36), Vector3(x1, -0.08, -0.36), Vector3(x1, -0.08, 0.36), Vector3(x0, -0.08, 0.36), Vector3.UP, tint)
	for side: float in [-1.0, 1.0]:
		_quad(surface, Vector3(side * 4.4, -2.05, -0.36), Vector3(side * 4.4, -2.05, 0.36), Vector3(side * 4.4, -0.08, 0.36), Vector3(side * 4.4, -0.08, -0.36), Vector3(side, 0, 0))
	return _finish(surface)


func _append_colored(surface: SurfaceTool, mesh: ArrayMesh, offset: Vector3, tint: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		surface.set_color(tint)
		surface.set_normal(normals[index])
		surface.add_vertex(vertices[index] + offset)


func _bridge_paving() -> ArrayMesh:
	var surface := _surface()
	surface.set_smooth_group(-1)
	for row in 5:
		for column in 6:
			var x0 := maxf(-4.29, -4.29 + column * 1.716 - float(row % 2) * 0.858)
			var x1 := minf(4.29, -4.29 + (column + 1) * 1.716 - float(row % 2) * 0.858)
			if x1 - x0 < 0.1:
				continue
			var tint := Color(0.73, 0.70, 0.58).lightened(float((row * 3 + column * 7) % 5) * 0.008)
			_append_colored(surface, _round_box(Vector3(x1 - x0 - 0.036, 0.05, 1.194), 0.012), Vector3((x0 + x1) * 0.5, -0.004, -2.46 + row * 1.23), tint)
	return _finish(surface)


func _bank_reach(z: float, side: float, river_x: float) -> float:
	var waves := 0.67 + 0.38 * sin(z * 0.25 + river_x * 0.42) + side * 0.26 * cos(z * 0.64)
	var approach := smoothstep(3.7, 5.4, absf(absf(z) - 14.0))
	return 0.08 + waves * approach


func _save_banks() -> void:
	var turf := _surface()
	var stone := _surface()
	for river_x: float in [-12.0, 12.0]:
		for side: float in [-1.0, 1.0]:
			var edge := river_x - side * 3.0
			var rows: Array[PackedVector3Array] = []
			for sample in 273:
				var z := -68.0 + float(sample) * 0.5
				var reach := _bank_reach(z, side, river_x)
				var ripple := 0.035 * sin(z * 3.2) + 0.022 * cos(z * 5.4)
				rows.append(PackedVector3Array([
					Vector3(edge - side * 0.18, 0.009, z),
					Vector3(edge + side * reach * 0.45, 0.025 + ripple, z),
					Vector3(edge + side * reach * 0.75, -0.16 + ripple, z),
					Vector3(edge + side * (reach + 0.03), -0.49 + ripple, z),
					Vector3(edge + side * (reach + 0.40), -0.96, z),
					Vector3(edge + side * (reach + 0.69), -1.65, z),
				]))
			for sample in rows.size() - 1:
				for band in 5:
					var tint := Color.WHITE
					if band >= 3:
						tint = Color(0.49, 0.46, 0.32).lerp(Color(0.34, 0.39, 0.30), float(band - 3) * 0.6)
						tint = tint.lightened(0.055 * sin(float(sample) * 0.43 + river_x))
					_quad(turf if band < 3 else stone, rows[sample][band], rows[sample + 1][band], rows[sample + 1][band + 1], rows[sample][band + 1], Vector3(side, 1, 0), tint)
	_save("meadow_bank_grass", _finish(turf))
	_save("meadow_bank_stone", _finish(stone))
