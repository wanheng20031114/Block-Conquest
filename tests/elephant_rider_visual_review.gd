extends SceneTree
## Real native/instanced renders focused on the elephant rider's seating contacts.
var output := "res://.local/advanced-units/elephant-rider-fix/"
var captures := 0
var failures: Array[String] = []

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func capture(label: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if viewport.get_texture().get_image().save_png(output + label + ".png") != OK:
		failures.append(label)
	captures += 1

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	if "--before" in OS.get_cmdline_user_args(): output += "before/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600, 900)
	AudioServer.set_bus_mute(0, true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	for advanced: bool in [false, true]:
		var grade := "advanced" if advanced else "normal"
		codex.select_entry(0, "war_elephant")
		codex.select_advanced(advanced)
		codex._select_preview_action(0)
		codex.set_process(false)
		var model: UnitVisual = codex._model
		model.locomotion.seek(0, true)
		model.attack.play("strike")
		model.attack.seek(0, true)
		model.attack.pause()
		codex._request_preview_redraw()
		await capture(grade + "-codex", root)
		var view: SubViewport = codex.get_node("%CodexViewport")
		codex._camera.position = Vector3(2.8, 3.9, -6)
		codex._camera.look_at(Vector3(0, 2.85, .1), Vector3.UP)
		codex._camera.size = 1.85
		for angle: int in [0, 60, 120, 180, 240, 300]:
			codex._anchor.rotation.y = deg_to_rad(angle)
			codex._request_preview_redraw()
			await capture(grade + "-rider-%03d" % angle, view)
		codex._anchor.rotation.y = 0
		codex._camera.position = Vector3(0, 6, .12)
		codex._camera.look_at(Vector3(0, 2.6, .1), Vector3.FORWARD)
		codex._camera.size = 2.2
		codex._request_preview_redraw()
		await capture(grade + "-top", view)
		codex._camera.position = Vector3(2.8, 3.9, -6)
		codex._camera.look_at(Vector3(0, 2.85, .1), Vector3.UP)
		codex._camera.size = 1.85
		codex._select_preview_action(2)
		codex.set_process(false)
		for phase: float in [.16, .34, .55, .66, .90, 1.55]:
			model.attack.seek(phase, true)
			codex._request_preview_redraw()
			await capture(grade + "-strike-%03d" % roundi(phase * 100), view)
		codex._select_preview_action(1)
		codex.set_process(false)
		for phase: float in [.0, .31, .62, .93]:
			model.locomotion.seek(phase, true)
			codex._request_preview_redraw()
			await capture(grade + "-walk-%03d" % roundi(phase * 100), view)
		codex._select_preview_action(0)
		codex.set_process(false)
		model.set_team(FactionPalette.SANDBOX_OFFSET + 1)
		codex._request_preview_redraw()
		await capture(grade + "-red", view)
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
	game.spawn_unit("war_elephant", 0, Vector3(1.6, 0, 0))
	game.spawn_variant("war_elephant", 0, Vector3(-1.6, 0, 0))
	game.camera.position = Vector3(4.3, 5.2, -10)
	game.camera.look_at(Vector3(0, 1.6, 0), Vector3.UP)
	game.camera.size = 7.9
	await create_timer(.25).timeout
	await capture("comparison", root)
	game.camera.position = Vector3(2, 4.4, -9)
	game.camera.look_at(Vector3(0, 2.75, .1), Vector3.UP)
	game.camera.size = 5.7
	await capture("riders-comparison", root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(output + "visual-results.json", FileAccess.WRITE).store_string(JSON.stringify({"captures": captures, "failures": failures}, "\t"))
	print("ELEPHANT_RIDER_VISUAL captures=", captures, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
