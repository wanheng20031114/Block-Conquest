extends SceneTree
## Native input and gameplay Tween recording for the adopted 01 motion.
## Godot --path . --script res://tests/block_war_selection/live_render.gd --fixed-fps 30

const OUTPUT := "res://artifacts/block_war_selection_live"
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func click(at: Vector2) -> void:
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	game.hud.get_node("%Toast").hide()
	var home: WarBuilding = game.by_id[0]
	game.camera_rig.focus_at(home.global_position + Vector3(0, 0, -2), true)
	game.camera.size = 22.0
	for frame: int in 24:
		await process_frame
	for kind: int in [0, 1, 2]:
		home.kind = kind
		home.level = 2
		home.refresh_visual()
		game.select_building(null)
		await physics_frame
		var at: Vector2 = game.camera.unproject_position(home.global_position + Vector3(0, 1.5, 0))
		assert(game.pick_building(at) == home)
		for frame: int in 90:
			if frame == 18:
				click(at)
				assert(game.selected == home and home._selection_body_tween.is_running())
			if frame == 70:
				game.select_building(null)
			await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var path := OUTPUT + "/kind_%d_%03d.png" % [kind, frame]
				assert(root.get_texture().get_image().save_png(path) == OK)
	await game.prepare_shutdown()
	print("BLOCK_WAR_SELECTION_LIVE kinds=3 frames=270")
	quit()
