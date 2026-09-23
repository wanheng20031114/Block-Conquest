extends SceneTree
## Render the saved maps and native selection screen for visual review.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const OUTPUT := "res://artifacts/block_war_maps/"

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	for frame: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := root.get_texture().get_image()
	assert(output.save_png(OUTPUT + name + ".png") == OK)
	print("MAP_CAPTURE ", name)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var session := root.get_node("Session")
	for definition: Resource in CATALOG.MAPS:
		session.block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		game.camera_rig.focus_at(Vector3.ZERO, true)
		game.camera.size = maxf(58.0, definition.half_size.y * 1.85)
		game.camera_rig.zoom_target = game.camera.size
		await _capture(definition.map_id)
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	for size_class: int in 3:
		current_scene.get_node("%%Size%d" % size_class).pressed.emit()
		await _capture("selection_%d" % size_class)
	session.block_war_map_id = "rift"
	quit()
