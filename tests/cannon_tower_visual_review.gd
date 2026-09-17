extends SceneTree
## Saved model, catalogue, and battlefield captured by the actual Vulkan renderer.
const OUT := "res://.local/defenses/cannon_tower/"
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	root.unfocusable = true
	root.visible = false
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func capture(label: String, viewport: Viewport) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().save_png(OUT + label + ".png") == OK, "render " + label)
func _run() -> void:
	create_timer(80, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600,900)
	AudioServer.set_bus_mute(0, true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	codex.select_entry(1, "cannon_tower")
	await create_timer(.6).timeout
	check(codex.get_node("%Stats").text.contains("350") and codex.get_node("%Stats").text.contains("1500"), "live codex balance values")
	check(codex.get_node("%PreviewAnimationControls").visible and not codex.get_node("%PreviewWalk").visible, "building exposes native idle and firing previews")
	var model: DefensiveTowerVisual = codex._model
	var triangles: int = 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false): triangles += mesh.mesh.get_faces().size() / 3
	check(triangles <= 10000, "building triangle budget")
	var clears_stone := true
	# Inspect the exported tube vertices at the lowest allowed pitch, across a
	# full sweep and all recoil extremes. Corner caps end at y=3.75.
	model.guns[0].elevation.rotation.x = DefensiveGunVisual.MIN_PITCH
	for yaw: int in range(0,360,15):
		model.guns[0].turret.rotation.y = deg_to_rad(yaw)
		for phase: float in [0.0,.07,.9]:
			model.sample_fire(phase)
			for mesh: MeshInstance3D in model.get_node("Gun/Turret/Elevation/Barrel").find_children("*", "MeshInstance3D", true, false):
				for vertex: Vector3 in mesh.mesh.get_faces():
					var point: Vector3 = model.to_local(mesh.to_global(vertex))
					if absf(absf(point.x)-1.96) < .38 and absf(absf(point.z)-1.96) < .38 and point.y < 3.80:
						clears_stone = false
	check(clears_stone, "full rotation and recoil clear stone caps by at least five centimetres")
	model.guns[0].elevation.rotation.x = 0
	model.guns[0].turret.rotation.y = 0
	model.sample_fire(.9)
	await capture("codex", root)
	var viewport: SubViewport = codex.get_node("%CodexViewport")
	for angle: int in [0,90,180,270]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		await capture("angle_%03d" % angle, viewport)
	codex._anchor.rotation.y = 0
	model.guns[0].turret.rotation.y = PI * .25
	model.guns[0].elevation.rotation.x = DefensiveGunVisual.MIN_PITCH
	codex._request_preview_redraw()
	await capture("diagonal_clearance", viewport)
	model.guns[0].turret.rotation.y = 0
	model.guns[0].elevation.rotation.x = 0
	var original: Transform3D = codex._camera.transform
	codex._camera.position = Vector3(1,12,-2)
	codex._camera.look_at(Vector3(0,2,0),Vector3.UP)
	codex._request_preview_redraw()
	await capture("top", viewport)
	codex._camera.transform = original
	FactionPalette.apply_model(model, FactionPalette.SANDBOX_OFFSET + 1)
	codex._request_preview_redraw()
	await capture("red_team", viewport)
	FactionPalette.apply_model(model, 0)
	codex._select_preview_action(2)
	codex._process(.07)
	codex._toggle_preview_pause()
	var phase: float = model.guns[0].animation.current_animation_position
	await capture("recoil", viewport)
	check(is_equal_approx(model.guns[0].animation.current_animation_position,phase), "pause holds authored recoil")
	codex._select_preview_action(0)
	check(model.get_node("Gun/Turret/Elevation/Barrel").position == Vector3.ZERO, "idle resets paused recoil")
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
	var tower: BattleBuilding = game.spawn_building("cannon_tower",0,Vector3.ZERO)
	var arrow: BattleBuilding = game.spawn_building("defense_tower",0,Vector3(-7,0,0))
	var hq: BattleBuilding = game.spawn_building("headquarters",0,Vector3(9,0,2))
	game.spawn_unit("engineer",0,Vector3(3,0,-2.5))
	game.spawn_unit("cannon",0,Vector3(-3.5,0,-3.7))
	game.camera.position = Vector3(15,17,-26)
	game.camera.look_at(Vector3(1,2,0),Vector3.UP)
	game.camera.size = 23
	await create_timer(.35).timeout
	await capture("comparison", root)
	arrow.hide(); hq.hide()
	game.camera.position = Vector3(9,10,-13)
	game.camera.look_at(Vector3(0,2,0),Vector3.UP)
	game.camera.size = 12
	tower.set_selected(true)
	await capture("battle_close", root)
	game.hud.show()
	game.select_entities([tower])
	game.camera.size = 22
	game.camera.position = Vector3(14,18,-23)
	game.camera.look_at(Vector3(-2,1,0),Vector3.UP)
	await capture("sandbox", root)
	game.hud.hide()
	game.camera.size = 13
	game.camera.look_at(Vector3(0,2,0),Vector3.UP)
	var target: BattleUnit = game.spawn_unit("war_elephant",1,Vector3(0,0,-10))
	game.set_running(true)
	for unit: BattleUnit in game.get_node("Units").get_children(): unit.set_physics_process(false)
	for building: BattleBuilding in game.get_node("Buildings").get_children(): building.set_physics_process(false)
	tower.weapons[0].target = target
	tower._scan_time = 100
	tower.weapons[0].cooldown = 0
	tower._physics_process(.5)
	await create_timer(.05).timeout
	await capture("firing", root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUT + "visual.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles":triangles},"\t"))
	print("CANNON_TOWER_VISUAL ",checks," checks; ",failures.size()," failures; ",triangles," triangles")
	quit(0 if failures.is_empty() else 1)
