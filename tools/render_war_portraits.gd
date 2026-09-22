extends SceneTree
## Render the actual militia model, keeping the game's own shapes and materials.

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var studio: Node = load("res://scenes/block_war/portrait_studio.tscn").instantiate()
	root.add_child(studio)
	var colors: Array[Color] = [Color(0.91, 0.49, 0.12), Color(0.12, 0.62, 0.48)]
	var names: Array[String] = ["amber", "jade"]
	DirAccess.make_dir_recursive_absolute("res://assets/ui/block_war")
	for index: int in 2:
		var viewport: SubViewport = studio.get_node("Portrait%d" % index)
		var mesh: MultiMesh = viewport.get_node("Militia").multimesh
		mesh.set_instance_transform(0, Transform3D(Basis(Vector3.UP, -0.32 if index == 0 else 0.32), Vector3.ZERO))
		var color: Color = colors[index].srgb_to_linear()
		color.a = 0.0
		mesh.set_instance_custom_data(0, color)
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	for index: int in 2:
		var viewport: SubViewport = studio.get_node("Portrait%d" % index)
		var path := "res://assets/ui/block_war/commander_%s.png" % names[index]
		viewport.get_texture().get_image().save_png(path)
		print("WAR_PORTRAIT ", path)
	studio.queue_free()
	await process_frame
	await process_frame
	quit()
