extends SceneTree
## Real Vulkan codex, portrait, and sandbox captures for the current two-unit batch.
const OUT := "res://.local/advanced-units/infantry/"
const FAMILIES := ["swordsman", "shield_guard"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func capture(label: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(OUT + label + ".png") == OK, "render " + label)

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	AudioServer.set_bus_mute(0, true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	for kind: String in FAMILIES:
		codex.select_entry(0, kind)
		codex.select_advanced(true)
		codex._select_preview_action(0)
		codex.set_process(false)
		var model: UnitVisual = codex._model
		model.locomotion.seek(0, true)
		model.attack.play("strike")
		model.attack.seek(0, true)
		model.attack.pause()
		codex._request_preview_redraw()
		await capture(kind + "-codex", root)
		var triangles := 0
		for mesh: MeshInstance3D in model.get_node("Rig").find_children("*", "MeshInstance3D", true, false):
			triangles += mesh.mesh.get_faces().size() / 3
		check(triangles <= 6500, kind + " <= 6500 triangles")
		var viewport: SubViewport = codex.get_node("%CodexViewport")
		for angle: int in [0, 45, 90, 180, 270]:
			codex._anchor.rotation.y = deg_to_rad(angle)
			codex._request_preview_redraw()
			await capture(kind + "-angle-%03d" % angle, viewport)
		codex._anchor.rotation.y = 0
		model.set_team(FactionPalette.SANDBOX_OFFSET + 1)
		codex._request_preview_redraw()
		await capture(kind + "-red", viewport)
		model.set_team(0)
		codex._select_preview_action(2)
		codex.set_process(false)
		var windup: float = UnitVariantCatalog.ADVANCED[kind].definition().attack_windup_seconds
		for phase: float in [0.1, windup, 0.4, 0.6, 0.86]:
			model.attack.seek(phase, true)
			var sword: Node3D = model.get_node("Rig/Action/Waist/ArmRight/Sword")
			var grip := Vector3(.215, -.425, -.405) if kind == "shield_guard" else Vector3(.25, -.415, -.45)
			check(sword.position.is_equal_approx(grip), kind + " sword remains in hand at " + str(phase))
			if kind == "shield_guard" and is_equal_approx(phase, windup):
				check((sword.global_basis * Vector3.UP).dot(Vector3.FORWARD) > .95, "guard thrust matches .30s contact")
			codex._request_preview_redraw()
			await capture(kind + "-strike-%03d" % roundi(phase * 100), viewport)
		codex._select_preview_action(1)
		codex.set_process(false)
		var previous := 0.0
		for phase: float in [.18, .36, .54, .72]:
			var elapsed := phase - previous
			var steps := ceili(elapsed * 120)
			for step: int in steps:
				codex._advance_preview(elapsed / steps)
			previous = phase
			codex._request_preview_redraw()
			await capture(kind + "-walk-%03d" % roundi(phase * 100), viewport)
		codex._select_preview_action(0)
		codex.set_process(false)
		codex._camera.position = Vector3(0, 6, -.2)
		codex._camera.look_at(Vector3(0, 1, 0), Vector3.UP)
		codex._camera.size = 3.0
		codex._request_preview_redraw()
		await capture(kind + "-top", viewport)
		codex._camera.position = Vector3(0, 1.8, -6)
		codex._camera.look_at(Vector3(0, 1.70, 0), Vector3.UP)
		codex._camera.size = 1.3
		codex._request_preview_redraw()
		await capture(kind + "-face", viewport)
	codex.queue_free()
	await process_frame
	var portraits: Node = load("res://scenes/sandbox_model_previews.tscn").instantiate()
	root.add_child(portraits)
	for kind: String in FAMILIES:
		portraits.portrait(kind + "_advanced")
		await create_timer(.25).timeout
		await RenderingServer.frame_post_draw
		var picture: Image = portraits.portrait(kind + "_advanced").get_image()
		var bounds := picture.get_used_rect()
		check(bounds.size.x > 45 and bounds.size.y > 60, kind + " readable portrait")
		check(bounds.position.x > 1 and bounds.position.y > 1 and bounds.end.x < 191 and bounds.end.y < 215, kind + " portrait not clipped")
		check(picture.get_pixel(0, 0).a < .01, kind + " native transparent portrait")
	portraits.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.camera_rig.set_process(false)
	game.camera_rig.position = Vector3.ZERO
	game.hud.hide()
	for kind: String in FAMILIES:
		game.clear_units()
		await process_frame
		await process_frame
		# Camera faces +Z: positive X is the left side of the displayed comparison.
		var normal: BattleUnit = game.spawn_unit(kind, 0, Vector3(1.15, 0, 0))
		var advanced: BattleUnit = game.spawn_variant(kind, 0, Vector3(-1.15, 0, 0))
		game.camera.position = Vector3(3.6, 3.6, -9)
		game.camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
		game.camera.size = 5.5
		await create_timer(.2).timeout
		await capture(kind + "-comparison", root)
		game.camera.size = 18
		game.camera.look_at(Vector3(-2, 0, 0), Vector3.UP)
		game.hud.show()
		game.set_paint_kind(kind)
		game.set_paint_advanced(true)
		game.set_placing(false)
		game.select_entities([normal, advanced])
		game.hud.refresh()
		game.hud.get_node("UnitPanel").composition.activate(1)
		game.hud.refresh()
		await capture(kind + "-sandbox", root)
		game.hud.hide()
		game.camera.size = 5.5
		game.camera.look_at(Vector3(0, 1, 0), Vector3.UP)
		advanced.receive_damage(1000)
		game.set_running(true)
		await create_timer(.35).timeout
		await capture(kind + "-death", root)
		game.set_running(false)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUT + "visual-results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("ADVANCED_INFANTRY_VISUAL ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
