extends SceneTree
## Inspect the real map scenes and settlement spacing without consuming stale routes.

const DETAILS := {
	"terraces": Vector3(-32, 0, 0),
	"switchback": Vector3(-35, 0, 0),
	"crown": Vector3(-52, 0, -28),
	"highland": Vector3(-59, 0, 0),
}
var output: String

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String) -> void:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)
	print("HOUSING_CAPTURE ", name)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.gui_disable_input = true
	root.size = Vector2i(1600, 900)
	var session := root.get_node("Session")
	for definition: Resource in load("res://scripts/block_war/war_map_catalog.gd").MAPS:
		session.block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.camera_rig.edge_scroll = false
		game.ai_enabled = false
		game.audio.muted = true
		game.map.set_visual_paused(true)
		game.camera.size = game.camera_rig.maximum_zoom
		game.camera_rig.zoom_target = game.camera.size
		game.camera_rig.focus_at(Vector3.ZERO, true)
		await _capture(definition.map_id + "_overview")
		if DETAILS.has(definition.map_id):
			game.camera.size = 46.0
			game.camera_rig.zoom_target = 46.0
			game.camera_rig.focus_at(DETAILS[definition.map_id], true)
			await _capture(definition.map_id + "_village")
		await game.prepare_shutdown()
	print("HOUSING_VISUAL complete")
	quit()
