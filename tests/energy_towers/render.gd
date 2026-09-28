extends SceneTree
## Capture the authored four-way comparison and individual native model views.

var review: Control
var output: String

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.content_scale_size = Vector2i(1920, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.size = Vector2i(1440, 960)
	root.gui_disable_input = true
	change_scene_to_file("res://tests/energy_towers/review.tscn")
	await scene_changed
	review = current_scene
	for key: String in ["A", "B", "C", "D"]:
		var camera: Camera3D = review.get_node(key + "/View/Viewport/Stage/Camera")
		camera.look_at(Vector3(0, 1.9, 0))
	await _settle()
	assert(root.get_texture().get_image().save_png(output.path_join("energy_towers_comparison.png")) == OK)
	for key: String in ["A", "B", "C", "D"]:
		var container: SubViewportContainer = review.get_node(key + "/View")
		var viewport: SubViewport = container.get_node("Viewport")
		container.stretch = false
		viewport.size = Vector2i(1200, 1000)
		await _settle()
		assert(viewport.get_texture().get_image().save_png(output.path_join(key.to_lower() + "_detail.png")) == OK)
		container.stretch = true
	# A second sheet checks the compact, more top-down battlefield silhouette.
	for key: String in ["A", "B", "C", "D"]:
		var camera: Camera3D = review.get_node(key + "/View/Viewport/Stage/Camera")
		camera.position = Vector3(4, 16, 12)
		camera.look_at(Vector3(0, 1.4, 0))
		camera.size = 8.6
	review.get_node("Subtitle").text = "战场俯视角对照 · 同一建筑的四种外观 · 不可升级"
	await _settle()
	assert(root.get_texture().get_image().save_png(output.path_join("energy_towers_battle_view.png")) == OK)
	print("ENERGY_TOWER_REVIEW four models / six screenshots / native Forward+ capture: ", output)
	review.queue_free()
	await process_frame
	quit(0)
