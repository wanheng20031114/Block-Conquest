extends SceneTree
## Offline native mesh authoring. Run before tools/dress_war_map.py:
## Godot_console --headless --path . --script tools/bake_war_map_details.gd

const OUTPUT := "res://assets/block_war/environment/"


func _initialize() -> void:
	_save_round_box("bridge_plank", Vector3(0.91, 0.32, 6.56), 0.055)
	_save_round_box("bridge_beam", Vector3(9, 0.62, 0.38), 0.10)
	_save_round_box("bridge_rail", Vector3(9.03, 0.17, 0.17), 0.045)
	_save_round_box("bridge_low_rail", Vector3(9.03, 0.13, 0.14), 0.035)
	_save_round_box("bridge_post", Vector3(0.25, 1.62, 0.25), 0.055)
	_save_round_box("bridge_brace", Vector3(0.13, 0.13, 1.65), 0.025)
	_save_bank_lip()
	_save_bank_blocks()
	print("Saved eight native rounded bridge and riverbank resources")
	quit()


func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color = Color.WHITE) -> void:
	# Godot front faces are clockwise when viewed from outside.
	if (b - a).cross(c - a).dot(outward) > 0:
		var swap := b
		b = c
		c = swap
	for vertex: Vector3 in [a, b, c]:
		surface.set_color(color)
		surface.add_vertex(vertex)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color = Color.WHITE) -> void:
	_triangle(surface, a, b, c, outward, color)
	_triangle(surface, a, c, d, outward, color)


func _save_round_box(name: String, dimensions: Vector3, bevel: float) -> void:
	assert(ResourceSaver.save(_round_box(dimensions, bevel), OUTPUT + name + ".res") == OK)


func _round_box(dimensions: Vector3, bevel: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
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
	surface.generate_normals()
	surface.index()
	return surface.commit()


func _bank_jut(z: float, sign_value: float, river_x: float) -> float:
	var wave := 1.03 + sign_value * 0.76 * sin(z * 0.17 + river_x * 0.19) + 0.18 * cos(z * 0.49)
	var bridge := maxf(0.0, 1.0 - absf(absf(z) - 14.0) / 4.6)
	return wave * (1.0 - bridge * 0.94)


func _save_bank_lip() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var palette: Array[Color] = [Color(0.38, 0.51, 0.20), Color(0.49, 0.47, 0.32), Color(0.47, 0.44, 0.36), Color(0.37, 0.38, 0.33)]
	for river_x: float in [-12.0, 12.0]:
		for sign_value: float in [-1.0, 1.0]:
			var edge := river_x - sign_value * 3.0
			var rows: Array[PackedVector3Array] = []
			for index in 137:
				var z := -68.0 + index
				var jut := _bank_jut(z, sign_value, river_x)
				var bridge := smoothstep(3.6, 5.5, absf(absf(z) - 14.0))
				var swell := (0.22 + 0.12 * sin(z * 1.25 + river_x) + 0.07 * cos(z * 2.7)) * bridge
				rows.append(PackedVector3Array([
					Vector3(edge + sign_value * maxf(0.015, jut - 0.20), 0.018, z),
					Vector3(edge + sign_value * (jut + swell * 0.65), -0.045, z),
					Vector3(edge + sign_value * (jut + swell + 0.08), -0.28, z),
					Vector3(edge + sign_value * (jut + swell + 0.17), -1.2 - 0.11 * sin(z * 0.8), z),
					Vector3(edge + sign_value * (jut + swell + 0.37), -2.86, z),
				]))
			for index in rows.size() - 1:
				for band in 4:
					var variation := 0.96 + 0.04 * sin(index * 1.7 + river_x)
					var color: Color = palette[band] * Color(variation, variation, variation, 1)
					_quad(surface, rows[index][band], rows[index + 1][band], rows[index + 1][band + 1], rows[index][band + 1], Vector3(sign_value, 1, 0), color)
	surface.generate_normals()
	surface.index()
	assert(ResourceSaver.save(surface.commit(), OUTPUT + "bank_lip.res") == OK)


func _save_bank_blocks() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 922068
	var palette: Array[Color] = [Color(0.54, 0.515, 0.465), Color(0.46, 0.46, 0.43), Color(0.59, 0.555, 0.495)]
	for river_x: float in [-12.0, 12.0]:
		for sign_value: float in [-1.0, 1.0]:
			var edge := river_x - sign_value * 3.0
			var z := -66.0
			while z < 66.0:
				var length := rng.randf_range(2.3, 3.6)
				z += length * 0.88
				if absf(absf(z) - 14.0) < 5.2:
					continue
				var width := rng.randf_range(1.3, 2.0)
				var height := rng.randf_range(2.3, 2.85)
				# Put the broad rock caps entirely within the excluded riverbed.
				# Their visible shoulders rise through the grass lip, while the
				# original plateau and all bridge approaches remain untouched.
				var reach := maxf(_bank_jut(z, sign_value, river_x) - 0.05, width * 0.5 + 0.24)
				var center := Vector3(edge + sign_value * reach, -height * 0.5 + rng.randf_range(0.08, 0.28), z)
				var mesh := _rock_column(Vector3(width, height, length), rng)
				var arrays := mesh.surface_get_arrays(0)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var basis := Basis(Vector3.UP, rng.randf_range(-0.095, 0.095))
				var tint: Color = palette[rng.randi_range(0, palette.size() - 1)]
				for point in indices:
					surface.set_color(tint)
					surface.set_normal(basis * normals[point])
					surface.add_vertex(center + basis * vertices[point])
	surface.index()
	assert(ResourceSaver.save(surface.commit(), OUTPUT + "bank_blocks.res") == OK)


func _rock_column(dimensions: Vector3, rng: RandomNumberGenerator) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	var rings: Array[PackedVector3Array] = []
	var outline := PackedVector2Array()
	for point in 8:
		var angle := float(point) * TAU / 8.0 + 0.12
		outline.append(Vector2(cos(angle), sin(angle)) * rng.randf_range(0.84, 1.02))
	for level in 4:
		var ring := PackedVector3Array()
		var radius: float = [0.84, 1.0, 0.95, 0.68][level]
		var elevation: float = [-0.5, -0.28, 0.33, 0.5][level]
		var skew := Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.08, 0.08))
		for point in 8:
			var vertex := outline[point] * radius + skew
			ring.append(Vector3(vertex.x * dimensions.x * 0.5, elevation * dimensions.y, vertex.y * dimensions.z * 0.5))
		rings.append(ring)
	for level in 3:
		for point in 8:
			var next := (point + 1) % 8
			_quad(surface, rings[level][point], rings[level][next], rings[level + 1][next], rings[level + 1][point], (rings[level][point] + rings[level][next]) * Vector3(1, 0, 1))
	for level in [0, 3]:
		for point in 8:
			_triangle(surface, Vector3(0, rings[level][point].y, 0), rings[level][point], rings[level][(point + 1) % 8], Vector3.DOWN if level == 0 else Vector3.UP)
	surface.generate_normals()
	surface.index()
	return surface.commit()
