extends SceneTree
## Offline glTF -> native mesh bake. No runtime architectural node generation.

func _initialize() -> void:
	var models: Array[String] = ["foundation", "bellows", "house", "tower", "smithy", "gun_mount", "gun_barrel",
			"house_2", "tower_2", "smithy_2", "gun_mount_2", "gun_barrel_2",
			"house_3", "tower_3", "smithy_3", "gun_mount_3", "gun_barrel_3", "house_4"]
	var requested := OS.get_cmdline_user_args()
	if not requested.is_empty():
		assert(requested.size() == 1 and requested[0] in models, "Pass one authored model name after --")
		models = [requested[0]]
	for model: String in models:
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
