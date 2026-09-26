extends SceneTree
## Offline input for nature placement. Read the saved bank geometry, not a
## second approximation of its rectangular navigation boundary.
## https://docs.godotengine.org/en/stable/classes/class_mesh.html#class-mesh-method-get-faces
## Run after either bank baker and before the Python map authors.

func _initialize() -> void:
	var output: Dictionary = {}
	for map_id: String in ["rift", "lake", "rivers", "islands", "highland"]:
		var path := "res://assets/block_war/environment/meadow_bank_grass.res" if map_id == "rift" else "res://assets/block_war/environment/maps/%s_bank_grass.res" % map_id
		var mesh: Mesh = load(path)
		var values: Array[float] = []
		for point: Vector3 in mesh.get_faces():
			values.append(snappedf(point.x, 0.00001))
			values.append(snappedf(point.y, 0.00001))
			values.append(snappedf(point.z, 0.00001))
		output[map_id] = {"mesh": path, "sha256": FileAccess.get_sha256(path), "faces": values}
	DirAccess.make_dir_recursive_absolute("res://.local")
	var file := FileAccess.open("res://.local/war_shore_support.json", FileAccess.WRITE)
	assert(file != null, "Cannot write offline shore support")
	file.store_string(JSON.stringify(output))
	file.close()
	print("WAR_SHORE_SUPPORT_EXPORTED ", output.keys())
	quit()
