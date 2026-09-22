extends SceneTree
## Development-only mesh bake. Reuses the project's spearman parts unchanged.
## Run: Godot --headless --path . --script tools/build_war_militia.gd

func _initialize() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		["Body", Vector3(0, 1.05, 0), 0.0],
		["Head", Vector3(0, 1.57, 0), 0.0],
		["ArmLeft", Vector3(-0.34, 1.28, 0), 3.0],
		["ArmRight", Vector3(0.34, 1.28, 0), 0.0],
		["LegLeft", Vector3(-0.155, 0.75, 0), 1.0],
		["LegRight", Vector3(0.155, 0.75, 0), 2.0],
		# Deliberately omit the original spear's -0.30 rad tilt.
		["Spear", Vector3(0.59, 0.835, -0.45), 0.0],
	]
	for part: Array in parts:
		var mesh: ArrayMesh = load("res://assets/models/units/spearman/%s.res" % part[0])
		for index: int in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for vertex_index: int in indices:
				surface.set_normal(normals[vertex_index])
				surface.set_color(colors[vertex_index])
				surface.set_uv2(Vector2(part[2], 0.0))
				surface.add_vertex(vertices[vertex_index] + Vector3(part[1]))
	surface.index()
	var combined := surface.commit()
	var error := ResourceSaver.save(combined, "res://assets/models/block_war/militia.res", ResourceSaver.FLAG_COMPRESS)
	assert(error == OK)
	print("WAR_MILITIA_BAKED vertices=", combined.surface_get_array_len(0), " aabb=", combined.get_aabb())
	var combined_colors: PackedColorArray = combined.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var painted_vertices := 0
	for color: Color in combined_colors:
		if color.a > 0.75:
			painted_vertices += 1
	print("WAR_MILITIA_PAINT vertices=", painted_vertices, " first=", combined_colors[0])
	quit()
