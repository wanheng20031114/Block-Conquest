extends SceneTree
## Deterministic rendered pose review; exits after saving two PNGs.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var review = load("res://tests/block_war_marches_review.tscn").instantiate()
	root.add_child(review)
	current_scene = review
	var marches = review.get_node("Marches")
	var route := PackedVector3Array([Vector3(-12, 0, 9), Vector3(-7, 0, 9), Vector3(-7, 0, 1), Vector3(7, 0, 1), Vector3(7, 0, -8), Vector3(13, 0, -8)])
	var reverse := route.duplicate()
	reverse.reverse()
	marches.send(0, 1, 0, 120, route)
	marches.send(1, 0, 1, 120, reverse)
	for frame: int in 210:
		marches.tick(1.0 / 30.0)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/block_war_marches_stream.png")
	marches.clear()
	var line := PackedVector3Array([Vector3(-8, 0, 0), Vector3(8, 0, 0)])
	marches.send(0, 1, 0, 42, line)
	marches.tick(2.0)
	var camera: Camera3D = review.get_node("Camera")
	camera.position = Vector3(-3.3, 7, 7)
	camera.rotation_degrees = Vector3(-45, 0, 0)
	camera.size = 7.0
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/block_war_marches_close.png")
	print("BLOCK_WAR_MARCHES_VISUAL saved stream and close views")
	quit()
