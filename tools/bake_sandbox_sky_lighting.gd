extends SceneTree
## Offline Godot bake: preserve the existing art lighting separately from the visible sky.
## Requires a graphical renderer, e.g. --audio-driver Dummy; do not use --headless.
const SOURCE := preload("res://assets/sky/sandbox_lighting_source.tres")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Sky lighting bake requires the graphical renderer.")
		quit(2)
		return
	create_timer(45, true, false, true).timeout.connect(func(): quit(3))
	AudioServer.set_bus_mute(0, true)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready:
		await process_frame
	game.get_node("WorldEnvironment").environment.sky = SOURCE
	# The native sky finishes its incremental radiance bake over several frames.
	for frame: int in 60:
		await RenderingServer.frame_post_draw
	var lighting := RenderingServer.sky_bake_panorama(SOURCE.get_rid(), 1.0, false, Vector2i(512, 256))
	var error := lighting.save_exr("res://assets/sky/sandbox_lighting.exr", false)
	print("SANDBOX_SKY_LIGHTING_BAKE ", error_string(error))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
