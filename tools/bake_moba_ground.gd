extends SceneTree
func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://.local/moba-test1/ground.json"))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	for i: int in range(0, source.vertices.size(), 3):
		vertices.append(Vector3(source.vertices[i], source.vertices[i+1], source.vertices[i+2]))
		normals.append(Vector3(source.normals[i], source.normals[i+1], source.normals[i+2]))
	for i: int in range(0, source.colors.size(), 4): colors.append(Color(source.colors[i], source.colors[i+1], source.colors[i+2], 1))
	for i: int in range(0, source.uv.size(), 2): uv.append(Vector2(source.uv[i], source.uv[i+1]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load("res://assets/models/environment/rogue_forest/ground_paint.tres"))
	var result := ResourceSaver.save(mesh, "res://assets/models/environment/moba/ground.res")
	print("MOBA_GROUND result=", result, " vertices=", vertices.size())
	quit(0 if result == OK else 1)
