extends SceneTree
## Offline import of only the cannon tower, with explicit authored team masks.
func _initialize() -> void:
	var folder := "res://assets/models/environment/cannon_tower/"
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(folder + "parts.json"))
	for entry: Dictionary in parts:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(folder + entry.part + ".glb", state) == OK)
		var scene := document.generate_scene(state)
		for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var family := String(instance.name)
			assert(family in entry.families)
			var material := ShaderMaterial.new()
			material.shader = load("res://assets/models/environment/building_surface.gdshader")
			material.set_shader_parameter("building_height", 5.2)
			material.set_shader_parameter("metalness", .55 if family == "Metal" else 0.0)
			material.set_shader_parameter("surface_roughness", .48 if family == "Metal" else .84)
			var mesh: ArrayMesh = instance.mesh
			for surface: int in mesh.get_surface_count(): mesh.surface_set_material(surface, material)
			assert(ResourceSaver.save(mesh, folder + entry.part + "_" + family.to_lower() + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		scene.free()
	print("Cannon tower native meshes baked")
	quit()
