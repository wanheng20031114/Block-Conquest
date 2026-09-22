extends SceneTree
## Bake offline glTF geometry to native, scene-authored ArrayMesh resources.

func with_native_lods(mesh: ArrayMesh) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for surface: int in mesh.get_surface_count():
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(surface))
	importer.generate_lods(25.0, 60.0, [])
	var counts: Array[int] = []
	for surface: int in importer.get_surface_count():
		counts.append(importer.get_surface_lod_count(surface))
	print("  NATIVE_LODS ", counts)
	return importer.get_mesh()


func _initialize() -> void:
	for model: String in ["canopy_oak", "silver_birch", "wind_pine", "hazel_thicket", "moss_boulder", "fern_patch", "meadow_tuft", "reed_cluster", "daisies", "bluebells"]:
		var folder := "res://assets/models/block_war/nature/"
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(folder + model + ".glb", state) == OK)
		var imported := document.generate_scene(state)
		var combined := SurfaceTool.new()
		for part: MeshInstance3D in imported.find_children("*", "MeshInstance3D", true, false):
			var mesh: ArrayMesh = part.mesh
			for surface: int in mesh.get_surface_count():
				mesh.surface_set_material(surface, null)
				combined.append_from(mesh, surface, Transform3D.IDENTITY)
			assert(ResourceSaver.save(with_native_lods(mesh), folder + model + "_" + String(part.name).to_lower() + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
		if model in ["fern_patch", "meadow_tuft", "daisies", "bluebells"]:
			var merged := combined.commit()
			assert(ResourceSaver.save(with_native_lods(merged), folder + model + "_combined.res", ResourceSaver.FLAG_COMPRESS) == OK)
		imported.free()
		print("WAR_NATURE_BAKED ", model)
	quit()
