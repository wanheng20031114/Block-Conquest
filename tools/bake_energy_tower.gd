extends SceneTree
## Offline export: gameplay instances saved native meshes from the formal assets.

func _initialize() -> void:
	var folder := "res://assets/models/block_war/architecture/"
	for name: String in ["energy_tower", "energy_tower_core", "energy_tower_ring_a", "energy_tower_ring_b"]:
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
