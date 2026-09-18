extends SceneTree
## Real Vulkan codex, portrait, and sandbox captures for the current two-unit batch.
const OUT := "res://.local/advanced-units/infantry/"
var families: Array[String] = ["swordsman", "shield_guard"]
var output := OUT
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
	check(viewport.get_texture().get_image().save_png(output + label + ".png") == OK, "render " + label)

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		families.assign(args)
		output = "res://.local/advanced-units/" + "-".join(families) + "/"
	for kind: String in families:
		assert(kind in ["swordsman", "shield_guard", "spearman", "archer", "crossbowman", "knight", "light_cavalry", "war_elephant"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1600, 900)
	AudioServer.set_bus_mute(0, true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	for kind: String in families:
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
		check(triangles <= (10000 if kind == "war_elephant" else 8000 if kind in ["knight", "light_cavalry"] else 6500), kind + " within triangle budget")
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
		var phases: Array[float] = [0.1, windup, 0.4, 0.6, 0.86]
		if kind == "archer": phases = [.1, .24, .27, .4, .6, .86, 1.1]
		if kind == "spearman": phases = [.1, .16, .22, .43, .65, .88]
		if kind == "crossbowman": phases = [.14, .20, .40, .55, .70, .82, .96]
		if kind == "light_cavalry": phases = [.07, .145, .20, .25, .40, .62, .85]
		if kind == "war_elephant": phases = [.16, .34, .55, .66, .90, 1.23, 1.55]
		for phase: float in phases:
			model.attack.seek(phase, true)
			check_weapon_pose(model, kind, phase)
			codex._request_preview_redraw()
			await capture(kind + "-strike-%03d" % roundi(phase * 100), viewport)
		codex._select_preview_action(1)
		codex.set_process(false)
		var previous := 0.0
		var walk_phases: Array[float] = [.18, .36, .54, .72]
		if kind == "knight": walk_phases = [.15, .30, .45, .60]
		if kind == "light_cavalry": walk_phases = [.12, .24, .36, .48]
		if kind == "war_elephant": walk_phases = [.31, .62, .93, 1.24]
		for phase: float in walk_phases:
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
		codex._camera.size = 5.5 if kind == "war_elephant" else 4.0 if kind in ["knight", "light_cavalry"] else 3.0
		codex._request_preview_redraw()
		await capture(kind + "-top", viewport)
		var face_height: float = 2.65 if kind == "war_elephant" else 2.10 if kind in ["knight", "light_cavalry"] else 1.70
		codex._camera.position = Vector3(0, face_height + .20, -6)
		codex._camera.look_at(Vector3(0, face_height, 0), Vector3.UP)
		codex._camera.size = 2.8 if kind == "war_elephant" else 2.0 if kind in ["knight", "light_cavalry"] else 1.3
		codex._request_preview_redraw()
		await capture(kind + "-face", viewport)
	codex.queue_free()
	await process_frame
	var portraits: Node = load("res://scenes/sandbox_model_previews.tscn").instantiate()
	root.add_child(portraits)
	for kind: String in families:
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
	for kind: String in families:
		game.clear_units()
		await process_frame
		await process_frame
		# Camera faces +Z: positive X is the left side of the displayed comparison.
		var spacing := 1.60 if kind == "war_elephant" else 1.15
		var normal: BattleUnit = game.spawn_unit(kind, 0, Vector3(spacing, 0, 0))
		var advanced: BattleUnit = game.spawn_variant(kind, 0, Vector3(-spacing, 0, 0))
		game.camera.position = Vector3(3.6, 3.6, -9)
		if kind == "war_elephant": game.camera.position = Vector3(4.3, 5.2, -10)
		var focus_height := 1.6 if kind == "war_elephant" else 1.0
		var comparison_size := 7.9 if kind == "war_elephant" else 6.4 if kind in ["knight", "light_cavalry"] else 5.5
		game.camera.look_at(Vector3(0, focus_height, 0), Vector3.UP)
		game.camera.size = comparison_size
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
		game.camera.size = comparison_size
		game.camera.look_at(Vector3(0, focus_height, 0), Vector3.UP)
		advanced.receive_damage(1000)
		game.set_running(true)
		await create_timer(.35).timeout
		await capture(kind + "-death", root)
		game.set_running(false)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(output + "visual-results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "families": families}, "\t"))
	print("ADVANCED_INFANTRY_VISUAL ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func check_weapon_pose(model: UnitVisual, kind: String, phase: float) -> void:
	if kind == "archer":
		var bow: Node3D = model.find_child("Bow")
		if is_equal_approx(phase, .24):
			var hand: Node3D = model.find_child("ForearmRight")
			check(hand.to_global(Vector3(.02, -.24, -.075)).distance_to(bow.to_global(Vector3(0, 0, .46))) < .025, "advanced archer hand meets drawn string")
			check(model.find_child("StringUpper").position.z > .44, "archer string fully drawn")
			check(bow.global_basis.y.dot(Vector3.UP) > .97, "archer aimed bow stays upright")
		if is_equal_approx(phase, .27):
			check(not model.find_child("Arrow").visible, "archer arrow releases at .27s")
			check(model.find_child("StringUpper").position.z < .16, "archer string snaps at release")
	elif kind == "spearman":
		var spear: Node3D = model.get_node("Rig/Action/Waist/ArmRight/Spear")
		check(spear.position.is_equal_approx(Vector3(.25, -.445, -.45)), "spear remains in gauntlet at " + str(phase))
		if is_equal_approx(phase, .22):
			check((spear.global_basis * Vector3.UP).dot(Vector3.FORWARD) > .98, "advanced spear points forward at contact")
	elif kind == "crossbowman":
		var bow: Node3D = model.find_child("Crossbow")
		var hand: Node3D = model.find_child("ForearmLeft")
		check(hand.to_global(Vector3(-.025, -.235, -.055)).distance_to(bow.to_global(Vector3(-.025, -.07, -.045))) < .025, "crossbow supporting hand stays on stock at " + str(phase))
		if is_equal_approx(phase, .20):
			check(not model.find_child("Bolt").visible, "crossbow bolt releases at .20s")
		if is_equal_approx(phase, .82):
			check(model.find_child("Bolt").visible, "crossbow bolt reseated during reload")
	elif kind == "light_cavalry":
		check(model.find_child("Sword").position.is_equal_approx(Vector3(.09, -.42, -.22)), "light cavalry retains sword grip at " + str(phase))
		check(model.find_child("HorseHead").get_parent().name == &"Body", "light cavalry retains horse head joint")
	elif kind == "war_elephant":
		check(model.find_child("Head").get_parent().name == &"HeadMotion", "elephant forehead and tusk sockets follow head at " + str(phase))
		check(model.find_child("RiderHead").get_parent().name == &"Rider", "elephant rider hat follows original rider joint")
	elif kind == "knight":
		check(model.find_child("ArmRight").get_parent().name == &"Waist", "knight weapon and gauntlet share the arm at " + str(phase))
		check(model.find_child("HorseHead").get_parent().name == &"Body", "knight horse armor follows the original head joint")
	else:
		var sword: Node3D = model.get_node("Rig/Action/Waist/ArmRight/Sword")
		var grip := Vector3(.215, -.425, -.405) if kind == "shield_guard" else Vector3(.25, -.415, -.45)
		check(sword.position.is_equal_approx(grip), kind + " sword remains in hand at " + str(phase))
		if kind == "shield_guard" and is_equal_approx(phase, .30):
			check((sword.global_basis * Vector3.UP).dot(Vector3.FORWARD) > .95, "guard thrust matches .30s contact")
