extends SceneTree
## Native work/completion/capture review. Use --fixed-fps 30 --write-movie ... -- --video.

var game: Node3D
var sites: Array[WarBuilding] = []

func _initialize() -> void:
	_run.call_deferred()

func _capture(label: String) -> void:
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://artifacts/block_war_construction_" + label + ".png") == OK)

func _start_work() -> void:
	for site: WarBuilding in sites:
		game.select_building(site)
		game.upgrade_selected()
	game.select_building(sites[0])
	game.hud.get_node("%Toast").hide()

func _capture_home() -> void:
	sites[0].population = 0.0
	game._on_unit_arrived(sites[0].building_id, 1, 80.0)
	game.update_hud()
	game.hud.get_node("%Toast").hide()

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	sites.assign([game.by_id[0], game.by_id[6], game.by_id[8]])
	for site: WarBuilding in sites:
		site.faction = 0
		site.level = 2
		site.population = 120.0
		site.refresh_visual()
	game.select_building(sites[0])
	game.hud.get_node("%Toast").hide()
	game.camera_rig.focus_at(Vector3(-24, 0, -4), true)
	game.camera.size = 30.0
	if OS.get_cmdline_user_args().has("--video"):
		for frame: int in 510:
			if frame == 30:
				_start_work()
			elif frame == 375:
				game.upgrade_selected()
				game.hud.get_node("%Toast").hide()
			elif frame == 435:
				_capture_home()
			game.simulate(1.0 / 30.0)
			game.update_hud()
			await process_frame
	else:
		_start_work()
		game.simulate(4.0)
		game.update_hud()
		await create_timer(1.6).timeout
		await _capture("working")
		game.camera.size = 58.0
		game.camera_rig.focus_at(Vector3(-10, 0, 0), true)
		await _capture("default_zoom")
		game.camera.size = 30.0
		game.camera_rig.focus_at(Vector3(-24, 0, -4), true)
		game.simulate(6.0)
		await create_timer(0.22).timeout
		await _capture("complete")
		game.upgrade_selected()
		game.simulate(3.0)
		await create_timer(0.8).timeout
		_capture_home()
		await create_timer(0.5).timeout
		await _capture("captured")
		game.hud._open_help()
		await create_timer(0.3).timeout
		await _capture("help")
	print("BLOCK_WAR_CONSTRUCTION_VISUAL house, tower and forge work/completion/capture reviewed")
	await game.prepare_shutdown()
	quit()
