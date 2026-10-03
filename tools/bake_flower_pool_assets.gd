extends SceneTree
## Offline ArrayMesh authoring; the match only loads saved resources.
## https://docs.godotengine.org/en/stable/classes/class_arraymesh.html

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var directory := "res://assets/block_war/flower_pool/"
	DirAccess.make_dir_recursive_absolute(directory)
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/flower-pool-authoring/meshes.json"))
	for key: String in payload:
		var data: Dictionary = payload[key]
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colors := PackedColorArray()
		for v: Array in data.vertices:
			vertices.append(Vector3(v[0], v[1], v[2]))
		for v: Array in data.normals:
			normals.append(Vector3(v[0], v[1], v[2]))
		for v: Array in data.colors:
			colors.append(Color(v[0], v[1], v[2], 1.0))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		assert(ResourceSaver.save(mesh, directory + key + ".res", ResourceSaver.FLAG_COMPRESS) == OK)
	if OS.get_cmdline_user_args().has("--terrain-only"):
		print("FLOWER_POOL_TERRAIN_BAKED ", payload.keys())
		quit()
		return
	var garden: Node3D = load("res://assets/campaign/reference_railway/native/hydrangeas.scn").instantiate()
	var variants := {}
	for shrub: Node3D in garden.find_children("Hydrangea_*", "Node3D", true, false):
		var palette := String(shrub.name).split("_")[1]
		if not variants.has(palette):
			variants[palette] = 0
		if variants[palette] >= 3:
			continue
		var copy: Node3D = shrub.duplicate()
		copy.transform = Transform3D.IDENTITY
		copy.name = "Hydrangea"
		# Orthographic battle zoom changes projected size, not camera distance.
		# Native mesh LOD preserves the fine petals at close zoom automatically.
		# https://docs.godotengine.org/en/stable/classes/class_importermesh.html
		var detail: MeshInstance3D = copy.find_children("DetailedFlowers*", "MeshInstance3D", false, false)[0]
		var source: ArrayMesh = detail.mesh
		var importer := ImporterMesh.new()
		for surface: int in source.get_surface_count():
			importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface), [], {}, source.surface_get_material(surface))
		importer.generate_lods(60.0, 25.0, [])
		detail.mesh = importer.get_mesh()
		detail.visibility_range_end = 0.0
		detail.lod_bias = 8.0
		var distant: MeshInstance3D = copy.find_children("DistantFlowers*", "MeshInstance3D", false, false)[0]
		copy.remove_child(distant)
		distant.free()
		for child: Node in copy.find_children("*", "", true, false):
			child.owner = copy
		var packed := PackedScene.new()
		assert(packed.pack(copy) == OK)
		var path := directory + "hydrangea_%s_%d.scn" % [palette, variants[palette]]
		assert(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK)
		print("FLOWER_VARIANT_SAVED ", path)
		variants[palette] += 1
		copy.free()
	garden.free()
	print("FLOWER_POOL_ASSETS_BAKED ", payload.keys(), " shrubs=", variants)
	quit()
