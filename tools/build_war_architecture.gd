extends SceneTree
## Offline glTF -> native mesh bake. No runtime architectural node generation.

func _initialize() -> void:
	for model: String in ["foundation", "house", "tower", "smithy", "bellows", "gun_mount", "gun_barrel"]:
		var folder := "res://assets/models/block_war/architecture/"
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(folder + model + ".glb", state) == OK)
		var imported := document.generate_scene(state)
		for part: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
			var mesh: ArrayMesh = part.mesh
			for surface: int in mesh.get_surface_count():
				mesh.surface_set_material(surface, null)
			assert(ResourceSaver.save(mesh, folder + model + "_" + String(part.name).to_lower() + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		imported.free()
		print("WAR_ARCHITECTURE_BAKED ", model)
	quit()
