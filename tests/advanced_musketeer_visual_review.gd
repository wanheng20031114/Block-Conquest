extends SceneTree
## Vulkan captures of the real codex and sandbox; no synthetic art.
const OUT := "res://.local/advanced-units/"
func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()
func capture(label: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().save_png(OUT + label + ".png") == OK)
func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600,900)
	AudioServer.set_bus_mute(0,true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	codex.select_entry(0,"musketeer")
	codex.select_advanced(true)
	await create_timer(.6).timeout
	await capture("codex", root)
	codex._toggle_preview_pause()
	var viewport: SubViewport = codex.get_node("%CodexViewport")
	for angle: int in [0,90,180,270]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		await capture("angle_%03d" % angle, viewport)
	codex._anchor.rotation.y = 0
	codex._model.set_team(FactionPalette.SANDBOX_OFFSET + 1)
	codex._request_preview_redraw()
	await capture("red_team", viewport)
	codex._model.set_team(0)
	for sample: float in [.22,.35,.40,.85,1.2,1.46,1.94]:
		codex._select_preview_action(2)
		codex._process(sample)
		codex._toggle_preview_pause()
		await capture("action_%03d" % roundi(sample*100), viewport)
	codex._select_preview_action(1)
	codex._process(.18)
	codex._toggle_preview_pause()
	await capture("walk", viewport)
	codex.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.camera_rig.set_process(false)
	game.camera_rig.position = Vector3.ZERO
	game.hud.hide()
	var normal: BattleUnit = game.spawn_unit("musketeer",0,Vector3(-1.05,0,0))
	var advanced: BattleUnit = game.spawn_variant("musketeer",0,Vector3(1.05,0,0))
	game.camera.position = Vector3(3.6,3.6,-9)
	game.camera.look_at(Vector3(0,1.0,0),Vector3.UP)
	game.camera.size = 5.5
	await create_timer(.3).timeout
	await capture("comparison",root)
	game.camera.size = 18
	game.camera.look_at(Vector3(-2,0,0),Vector3.UP)
	game.hud.show()
	game.set_paint_kind("musketeer")
	game.set_paint_advanced(true)
	game.set_placing(false)
	game.select_entities([normal,advanced])
	game.hud.refresh()
	game.hud.get_node("UnitPanel").composition.activate(1)
	game.hud.refresh()
	await capture("sandbox",root)
	game.hud.hide()
	game.camera.size = 7.5
	game.camera.look_at(Vector3(0,1,0),Vector3.UP)
	advanced.receive_damage(200)
	game.set_running(true)
	await create_timer(.35).timeout
	await capture("death", root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("ADVANCED_VISUAL completed")
	quit()
