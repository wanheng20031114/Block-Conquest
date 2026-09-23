extends SceneTree
## Native review; pass --fixed-fps 60 for matching particle/simulation clocks.

var game: Node3D
const CENTER := Vector3(-22, 0, 10)
var video := false

func _initialize() -> void:
	_run.call_deferred()

func reset_game() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.hud.get_node("%Toast").hide()
	await physics_frame

func advance(seconds: float) -> void:
	for frame: int in ceili(seconds * 60.0):
		game.simulate(1.0 / 60.0)
		game.update_hud()
		game.overlay.queue_redraw()
		await process_frame

func motion(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(at: Vector2, down: bool) -> void:
	motion(at)
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func drag_fire() -> void:
	var start: Vector2 = game.hud.get_node("UI/Skills/Row/Skill3").get_global_rect().get_center()
	var target: Vector2 = game.camera.unproject_position(CENTER)
	mouse(start, true)
	assert(game.armed_skill == 3)
	for frame: int in 36:
		motion(start.lerp(target, smoothstep(0.0, 1.0, float(frame + 1) / 36.0)))
		await advance(1.0 / 60.0)
	await capture("drag")
	mouse(target, false)
	assert(game.armed_skill == -1 and game.cooldowns[3] == 60.0)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://artifacts/block_war_combat_" + label + ".png") == OK)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	video = "--video" in OS.get_cmdline_user_args()
	await reset_game()
	game.camera_rig.focus_at(Vector3(-24, 0, -4), true)
	game.camera.size = 30.0
	await advance(0.6)
	await capture("menu")
	if "--actions-only" in OS.get_cmdline_user_args():
		await game.prepare_shutdown()
		print("BLOCK_WAR_ACTIONS_VISUAL captured")
		quit()
		return
	if video:
		await advance(0.8)
	game.convert_selected(2)
	game.hud.get_node("%Toast").hide()
	await advance(2.0)
	await capture("conversion")
	if video:
		await advance(8.3)
		await capture("converted")
	await reset_game()
	game.camera_rig.focus_at(CENTER + Vector3(0, 0, -2), true)
	game.camera.size = 22.0
	game.select_building(null)
	game.marches.send(900, 1, 0, 72, PackedVector3Array([CENTER + Vector3(-5, 0, 0.6), CENTER + Vector3(30, 0, 0.6)]))
	game.marches.send(901, 0, 1, 72, PackedVector3Array([CENTER + Vector3(5, 0, -0.6), CENTER + Vector3(-30, 0, -0.6)]))
	await advance(0.8)
	await drag_fire()
	game.hud.get_node("%Toast").hide()
	await advance(0.18)
	await capture("fire_early")
	await advance(0.37)
	await capture("fire_middle")
	await advance(0.60)
	await capture("fire_edge")
	await advance(0.5)
	await capture("fire_embers")
	if video:
		await advance(1.5)
	await reset_game()
	var tower: WarBuilding = game.by_id[6]
	tower.faction = 0
	tower.level = 3
	tower.refresh_visual()
	game.select_building(tower)
	game.camera_rig.focus_at(tower.global_position + Vector3(-2, 0, 3), true)
	game.camera.size = 22.0
	await advance(0.6)
	var start := tower.global_position + Vector3(-4.5, 0, 5.5)
	game.marches.send(902, 0, 1, 48, PackedVector3Array([start, start + Vector3(-30, 0, 0)]))
	game.marches.tick(1.2)
	await advance(0.10)
	await capture("cannon_flight")
	await advance(0.18)
	await capture("cannon_hit")
	await advance(0.45)
	await capture("cannon_settle")
	if video:
		await advance(2.2)
	else:
		game.hud._open_help()
		await advance(0.5)
		await capture("help")
	print("BLOCK_WAR_COMBAT_VISUAL menu, conversion, expanding fire and real cannon hits captured")
	await game.prepare_shutdown()
	quit()
