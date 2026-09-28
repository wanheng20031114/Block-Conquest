extends SceneTree
## Offline bake only: the preview instances saved native meshes and scenes.

func _initialize() -> void:
	var folder := "res://tests/energy_towers/models/"
	for name: String in ["a_crystal", "b_armillary", "c_coil", "d_lantern"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(folder + name + ".glb", state) == OK)
		var imported := document.generate_scene(state)
		for part: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
			var mesh: ArrayMesh = part.mesh
			for surface: int in mesh.get_surface_count():
				mesh.surface_set_material(surface, null)
			assert(ResourceSaver.save(mesh, folder + name + "_" + String(part.name).to_lower() + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		imported.free()
		print("ENERGY_TOWER_BAKED ", name)
	quit()
