extends SceneTree
const OUTPUT := "res://.local/moba-test1/"
var game: Node3D

func _initialize() -> void: run.call_deferred()

func capture(file: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + file + ".png")
	print("MOBA_CAPTURE ", file)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.local/moba-test1")
	create_timer(160, true, false, true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	await create_timer(.6).timeout
	await capture("menu")
	current_scene.get_node("%MobaMode").pressed.emit()
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.edge_scroll = false
	game.camera_rig.set_process(false)
	game.camera_rig.focus_at(Vector3(-62,0,0), true)
	game.hud.toast_remaining = .01
	await create_timer(1.5).timeout
	await capture("rts")
	var widget: Control = game.hud.cards[0]
	var start: Vector2 = widget.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var move := InputEventMouseMotion.new()
	move.position = start - Vector2(0,100)
	move.relative = Vector2(0,-100)
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(move)
	await process_frame
	await capture("drag")
	root.gui_cancel_drag()
	press.pressed = false
	Input.parse_input_event(press)
	if "--drag-only" in OS.get_cmdline_user_args():
		await game.prepare_shutdown()
		game.queue_free()
		await process_frame
		quit()
		return
	game.play_card(0, 0, game.hands[0].slots[0].uid)
	while game.elapsed < 35 and not game.finished: await physics_frame
	game.camera_rig.focus_at(Vector3.ZERO, true)
	await capture("battle")
	var hero: MobaHero = game.local_hero()
	hero.position = Vector3(-4,0,4)
	hero.reset_physics_interpolation()
	hero.model_pivot.rotation.y = -PI/2
	game.hero_controller.set_first_person(true)
	game.hero_controller.capture_mouse(false)
	hero.hp = 150
	game.cast_skill(0)
	game.cast_skill(1)
	await capture("first-person")
	game.hero_controller.set_first_person(false)
	root.size = Vector2i(1280,720)
	await capture("compact")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("MOBA_VISUAL_DONE")
	quit()
