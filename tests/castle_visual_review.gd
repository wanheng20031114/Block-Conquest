extends SceneTree
## Real Vulkan rendering of the authored scene, animation and battle placement.
const OUT := "res://.local/defenses/castle/"
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
	create_timer(90,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600,900)
	AudioServer.set_bus_mute(0,true)
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.open_codex()
	codex.select_entry(1,"castle")
	await create_timer(.6).timeout
	check(codex.get_node("%Stats").text.contains("950") and codex.get_node("%Stats").text.contains("独立火炮"), "codex shows cost and independent gun count")
	var model: DefensiveTowerVisual = codex._model
	var triangles := 0
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): triangles += mesh.mesh.get_faces().size()/3
	check(triangles <= 36000,"castle triangle budget")
	check(model.guns.size() == 3,"three authored gun scenes")
	var clears_stone := true
	for gun: DefensiveGunVisual in model.guns:
		gun.elevation.rotation.x = DefensiveGunVisual.MIN_PITCH
		for angle: int in range(0,360,15):
			gun.turret.rotation.y = deg_to_rad(angle)
			for phase: float in [0.0,.07,.9]:
				gun.sample_fire(phase)
				for mesh: MeshInstance3D in gun.get_node("Turret/Elevation/Barrel").find_children("*","MeshInstance3D",true,false):
					for vertex: Vector3 in mesh.mesh.get_faces():
						var point: Vector3 = model.to_local(mesh.to_global(vertex))
						if absf(point.x) < 1.785 and point.z > -.685 and point.z < 2.845 and point.y < 6.83: clears_stone = false
						for x: float in [-3.05,3.05]:
							for z: float in [-2.5,2.5]:
								if Vector2(point.x-x,point.z-z).length() < 1.25 and point.y < (5.56 if z < 0 else 6.85): clears_stone = false
		gun.turret.rotation.y = 0
		gun.elevation.rotation.x = 0
		gun.sample_fire(.9)
	check(clears_stone,"full sweep and recoil clear corner towers and central keep")
	await capture("codex",root)
	var viewport: SubViewport = codex.get_node("%CodexViewport")
	for angle: int in [0,90,180,270]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		await capture("angle_%03d" % angle,viewport)
	codex._anchor.rotation.y = 0
	var original: Transform3D = codex._camera.transform
	codex._camera.position = Vector3(1,20,-3)
	codex._camera.look_at(Vector3(0,2,0),Vector3.UP)
	codex._request_preview_redraw()
	await capture("top",viewport)
	codex._camera.transform = original
	FactionPalette.apply_model(model,FactionPalette.SANDBOX_OFFSET+1)
	codex._request_preview_redraw()
	await capture("red_team",viewport)
	FactionPalette.apply_model(model,0)
	for i: int in 3:
		model.guns[i].turret.rotation.y = [-.65,.75,PI][i]
		model.guns[i].sample_fire([.07,.5,.9][i])
	codex._request_preview_redraw()
	await capture("independent_guns",viewport)
	check(model.guns[0].get_node("Turret/Elevation/Barrel").position.z > model.guns[1].get_node("Turret/Elevation/Barrel").position.z and model.guns[2].get_node("Turret/Elevation/Barrel").position == Vector3.ZERO,"each AnimationPlayer owns only its barrel")
	codex._select_preview_action(2)
	codex._process(.07)
	codex._toggle_preview_pause()
	var phase: float = model.guns[0].animation.current_animation_position
	await capture("recoil",viewport)
	check(is_equal_approx(model.guns[0].animation.current_animation_position,phase),"preview pause freezes recoil")
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
	var castle: BattleBuilding = game.spawn_building("castle",0,Vector3.ZERO)
	var tower: BattleBuilding = game.spawn_building("cannon_tower",0,Vector3(-10,0,1))
	var hq: BattleBuilding = game.spawn_building("headquarters",0,Vector3(12,0,2))
	game.spawn_unit("engineer",0,Vector3(2,0,-5))
	game.spawn_unit("cannon",0,Vector3(-4,0,-5))
	game.camera.position = Vector3(17,21,-31)
	game.camera.look_at(Vector3(1,3,0),Vector3.UP)
	game.camera.size = 32
	await create_timer(.3).timeout
	await capture("comparison",root)
	tower.hide(); hq.hide()
	game.camera.position = Vector3(12,14,-20)
	game.camera.look_at(Vector3(0,3,0),Vector3.UP)
	game.camera.size = 18
	castle.set_selected(true)
	await capture("battle_close",root)
	game.hud.show()
	game.select_entities([castle])
	game.camera.size = 26
	game.camera.look_at(Vector3(-2,2,0),Vector3.UP)
	await capture("sandbox",root)
	game.hud.hide()
	game.camera.size = 21
	game.camera.look_at(Vector3(0,2,-2),Vector3.UP)
	for i: int in 3: game.spawn_unit("war_elephant",1,Vector3(-6+i*6,0,-12))
	game.set_running(true)
	for unit: BattleUnit in game.get_node("Units").get_children(): unit.set_physics_process(false)
	for building: BattleBuilding in game.get_node("Buildings").get_children(): building.set_physics_process(false)
	await physics_frame
	castle._scan_time = 0
	for weapon: BuildingWeaponState in castle.weapons: weapon.cooldown = 0
	castle._physics_process(.5)
	await create_timer(.05).timeout
	await capture("firing",root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUT+"visual.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles":triangles},"\t"))
	print("CASTLE_VISUAL ",checks," checks; ",failures.size()," failures; ",triangles," triangles")
	quit(0 if failures.is_empty() else 1)
