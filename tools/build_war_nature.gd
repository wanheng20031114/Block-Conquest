extends SceneTree
## Bake offline glTF geometry to native, scene-authored ArrayMesh resources.

func save_native(mesh: ArrayMesh, path: String) -> bool:
	# Publish complete files atomically while editor previews may hold old meshes.
	var temporary := path.trim_suffix(".res") + ".building.res"
	var error := ResourceSaver.save(mesh, temporary, ResourceSaver.FLAG_COMPRESS)
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		push_error("Cannot publish native nature mesh: %s (%s)" % [path, error_string(error)])
		quit(1)
		return false
	return true

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
	var models := OS.get_cmdline_user_args()
	if models.is_empty():
		models = PackedStringArray(["canopy_oak", "silver_birch", "wind_pine", "weeping_willow", "hazel_thicket", "moss_boulder", "fern_patch", "meadow_tuft", "reed_cluster", "daisies", "bluebells"])
	for model: String in models:
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
			if not save_native(with_native_lods(mesh), folder + model + "_" + String(part.name).to_lower() + ".res"):
				imported.free()
				return
		if model in ["fern_patch", "meadow_tuft", "daisies", "bluebells"]:
			var merged := combined.commit()
			if not save_native(with_native_lods(merged), folder + model + "_combined.res"):
				imported.free()
				return
		imported.free()
		print("WAR_NATURE_BAKED ", model)
	quit()
