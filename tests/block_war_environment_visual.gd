extends SceneTree
## Native geometry gallery: full trees, trunk/branch details and the rock understorey.

func _initialize() -> void:
	_run.call_deferred()


func _capture(name: String) -> void:
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://artifacts/block_war_environment_%s.png" % name
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("WAR_ENVIRONMENT_CAPTURE ", path)


func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://tests/block_war_environment_review.tscn")
	await scene_changed
	var gallery: Node3D = current_scene
	var camera: Camera3D = gallery.get_node("Camera")
	camera.look_at(Vector3(0, 2, 1))
	await create_timer(0.4).timeout
	await _capture("all")
	var specimens: Array[String] = ["Oak", "Birch", "Pine", "Willow"]
	for specimen: String in specimens:
		for other: String in specimens:
			gallery.get_node(other).visible = other == specimen
		var tree: Node3D = gallery.get_node(specimen)
		camera.position = tree.position + Vector3(6.5, 7.5, 11)
		camera.look_at(tree.position + Vector3(0, 2.8, 0))
		camera.size = 9.0
		await _capture(specimen.to_lower())
	for specimen: String in specimens:
		gallery.get_node(specimen).hide()
	camera.position = Vector3(-0.5, 8.8, 15)
	camera.look_at(Vector3(0, 0.5, 5.2))
	camera.size = 13.0
	await _capture("understorey")
	var rock: Node3D = gallery.get_node("Rock")
	camera.position = rock.position + Vector3(5, 4, 7)
	camera.look_at(rock.position + Vector3(0, 0.6, 0))
	camera.size = 4.6
	await _capture("rock")
	gallery.queue_free()
	await process_frame
	quit()
