extends SceneTree
## Native renders at horizon, zenith and panorama seam; no concept-image substitution.
const OUT := "res://.local/hero/sky/"
var game: Node3D

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func capture(label: String) -> Image:
	await create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	frame.save_png(OUT + label + ".png")
	return frame

func run() -> void:
	create_timer(60, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready:
		await process_frame
	# Unattended captures must not react to the user's typing/mouse or take focus.
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	root.gui_disable_input = true
	var controller: SandboxHeroController = game.hero_controller
	controller.create_or_update(HeroProfile.defaults(), false)
	controller.hero.position = Vector3.ZERO
	controller.hero.model_pivot.rotation = Vector3.ZERO
	game.spawn_unit("shield_guard", 1, Vector3(0, 0, -8))
	game.spawn_unit("musketeer", 0, Vector3(-3, 0, -5))
	game.set_placing(false)
	game.camera_rig.focus_at(Vector3.ZERO, true)
	game.camera_rig.set_process(false)
	game.camera.size = 24
	var baseline := "--baseline" in OS.get_cmdline_user_args()
	if baseline:
		var environment: Environment = game.get_node("WorldEnvironment").environment
		environment.sky = load("res://assets/sky/sandbox_lighting_source.tres")
		environment.fog_sky_affect = 1.0
	await capture("rts_before" if baseline else "rts_after")
	controller.set_first_person(true)
	controller._capture(false)
	controller.yaw = 0
	controller.pitch = -0.075
	# Keep troops still; permit the normal HUD for a representative gameplay frame.
	game.set_running(true)
	for unit: BattleUnit in get_nodes_in_group("units"):
		unit.set_physics_process(false)
	await capture("before" if baseline else "first_person")
	if not baseline:
		for direction: int in 4:
			controller.yaw = direction * PI * 0.5
			controller.pitch = deg_to_rad(25)
			await capture("direction_%d" % direction)
		controller.yaw = 0
		controller.pitch = deg_to_rad(78)
		await capture("zenith")
		controller.yaw = 0
		controller.pitch = deg_to_rad(10)
		for fov: float in [70.0, 110.0]:
			game.settings.fp_fov = fov
			await capture("seam_fov_%d" % int(fov))
		game.settings.fp_fov = 90.0
		controller.pitch = -0.075
		controller.yaw = 0
		controller.interface.open_inventory()
		await capture("inventory")
		controller.interface.close_panels()
	controller.set_first_person(false)
	if not baseline:
		await capture("rts_return")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_SKY_VISUAL_REVIEW_COMPLETE")
	quit()
