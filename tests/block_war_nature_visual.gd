extends SceneTree
## Six saved maps: tactical composition, close bank contacts, reverse angle and
## forest silhouette. Native review scene uses the match light and materials;
## it can inspect art independently of changes to gameplay/UI/audio scripts.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const OUTPUT := "res://artifacts/nature_review/"
var gallery: Node3D
var camera: Camera3D

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-20000, -20000))
	_run.call_deferred()

func capture(label: String, focus: Vector3, zoom: float, offset: Vector3) -> void:
	# Orthographic size controls framing. Keep the eye far enough away that
	# foreground crowns cannot cross the near plane in a low-angle close-up.
	camera.global_position = focus + offset
	camera.look_at(focus)
	camera.size = zoom
	for frame: int in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK)
	print("NATURE_CAPTURE ", label)

func frame_cost(label: String) -> void:
	var values: Array[float] = []
	for frame: int in 120:
		await process_frame
		values.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	values.sort()
	print("NATURE_GPU_MS ", label, " median=", values[60], " p95=", values[114])

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	change_scene_to_file("res://tests/block_war_nature_review.tscn")
	await scene_changed
	gallery = current_scene
	camera = gallery.get_node("Camera")
	for definition: Resource in CATALOG.MAPS:
		var requested := OS.get_cmdline_user_args()
		if not requested.is_empty() and definition.map_id not in requested:
			continue
		var map: WarMap = load(definition.scene_path).instantiate()
		gallery.add_child(map)
		for building: Node3D in map.get_node("Buildings").get_children():
			building.get_node("PopulationBadge").hide()
			for label: Label3D in building.find_children("*", "Label3D", true, false):
				label.hide()
		map.set_visual_paused(true)
		await capture(definition.map_id + "_overview", Vector3.ZERO,
			maxf(58.0, definition.half_size.y * 1.85), Vector3(0, 60, 46.86))
		await frame_cost(definition.map_id)
		var stone: Node3D
		var tree: Node3D
		for decoration: Node3D in map.get_node("Nature").get_children():
			if "BankStone" in decoration.name or "RiverStone" in decoration.name or "Ridge0Summit" in decoration.name:
				if stone == null or decoration.position.length_squared() < stone.position.length_squared():
					if decoration.scale.y > .60:
						stone = decoration
			if "ClearingTree" in decoration.name or "WayfindingTree" in decoration.name:
				if tree == null or decoration.position.x > tree.position.x:
					tree = decoration
		assert(stone != null and tree != null)
		await capture(definition.map_id + "_stone", stone.global_position + Vector3(0, 1, 0), 15, Vector3(24, 30, 39))
		await capture(definition.map_id + "_stone_reverse", stone.global_position + Vector3(0, .5, 0), 11, Vector3(-27, 18, -33))
		await capture(definition.map_id + "_grove", tree.global_position + Vector3(0, 2, 0), 18, Vector3(27, 30, 45))
		map.queue_free()
		await process_frame
	quit()
