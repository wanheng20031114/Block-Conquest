extends SceneTree
## Real Vulkan rendering of the authored scene, animation and battle placement.
const OUT := "res://.local/defenses/heavy_fortress/"
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
	codex.select_entry(1,"heavy_fortress")
	await create_timer(.6).timeout
	check(codex.get_node("%Stats").text.contains("1800") and codex.get_node("%Stats").text.contains("独立火炮"), "codex shows cost and independent gun count")
	var model: DefensiveTowerVisual = codex._model
	var triangles := 0
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): triangles += mesh.mesh.get_faces().size()/3
	check(triangles <= 32000,"heavy_fortress triangle budget")
	check(model.guns.size() == 2,"two authored heavy gun scenes")
	var clears_stone := true
	var max_sweep := 0.0
	for gun: DefensiveGunVisual in model.guns:
		gun.elevation.rotation.x = DefensiveGunVisual.MIN_PITCH
		for angle: int in range(0,360,15):
			gun.turret.rotation.y = deg_to_rad(angle)
			for phase: float in [0.0,.09,1.5]:
				gun.sample_fire(phase)
				for mesh: MeshInstance3D in gun.get_node("Turret/Elevation/Barrel").find_children("*","MeshInstance3D",true,false):
					for vertex: Vector3 in mesh.mesh.get_faces():
						var point: Vector3 = model.to_local(mesh.to_global(vertex))
						max_sweep = maxf(max_sweep,Vector2(point.x-gun.position.x,point.z-gun.position.z).length())
						if point.y < 4.70: clears_stone = false
						if absf(point.x) < 1.825 and absf(point.z-3.08) < 1.175 and point.y < 4.94: clears_stone = false
		gun.turret.rotation.y = 0
		gun.elevation.rotation.x = 0
		gun.sample_fire(1.5)
	check(clears_stone,"full sweep and recoil clear fortress parapets, platforms and magazine")
	check(max_sweep*2 < 6.9,"the two barrel sweep disks never intersect")
	await capture("codex",root)
	var viewport: SubViewport = codex.get_node("%CodexViewport")
	for angle: int in [0,90,180,270]:
		codex._anchor.rotation.y = deg_to_rad(angle)
		codex._request_preview_redraw()
		await capture("angle_%03d" % angle,viewport)
	codex._anchor.rotation.y = 0
	var original: Transform3D = codex._camera.transform
	var original_size: float = codex._camera.size
	codex._camera.position = Vector3(12,2.3,-20)
	codex._camera.look_at(Vector3(0,1.0,0),Vector3.UP)
	codex._camera.size = 13.5
	codex._request_preview_redraw()
	await capture("foundation_low",viewport)
	codex._camera.size = original_size
	codex._camera.position = Vector3(1,20,-3)
	codex._camera.look_at(Vector3(0,2,0),Vector3.UP)
	codex._request_preview_redraw()
	await capture("top",viewport)
	codex._camera.transform = original
	FactionPalette.apply_model(model,FactionPalette.SANDBOX_OFFSET+1)
	codex._request_preview_redraw()
	await capture("red_team",viewport)
	FactionPalette.apply_model(model,0)
	for i: int in 2:
		model.guns[i].turret.rotation.y = [-.65,.75][i]
		model.guns[i].sample_fire([.09,1.5][i])
	codex._request_preview_redraw()
	await capture("independent_guns",viewport)
	check(model.guns[0].get_node("Turret/Elevation/Barrel").position.z > model.guns[1].get_node("Turret/Elevation/Barrel").position.z and model.guns[1].get_node("Turret/Elevation/Barrel").position == Vector3.ZERO,"each AnimationPlayer owns only its barrel")
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
	var heavy_fortress: BattleBuilding = game.spawn_building("heavy_fortress",0,Vector3.ZERO)
	var castle: BattleBuilding = game.spawn_building("castle",0,Vector3(-12,0,1))
	var hq: BattleBuilding = game.spawn_building("headquarters",0,Vector3(14,0,2))
	game.spawn_unit("engineer",0,Vector3(2,0,-6.5))
	game.spawn_unit("cannon",0,Vector3(-4,0,-7))
	game.camera.position = Vector3(17,21,-31)
	game.camera.look_at(Vector3(1,3,0),Vector3.UP)
	game.camera.size = 38
	await create_timer(.3).timeout
	await capture("comparison",root)
	castle.hide(); hq.hide()
	game.camera.position = Vector3(12,14,-20)
	game.camera.look_at(Vector3(0,3,0),Vector3.UP)
	game.camera.size = 21
	heavy_fortress.set_selected(true)
	await capture("battle_close",root)
	game.hud.show()
	game.select_entities([heavy_fortress])
	game.camera.size = 30
	game.camera.look_at(Vector3(-2,2,0),Vector3.UP)
	await capture("sandbox",root)
	heavy_fortress.under_construction = true
	heavy_fortress.construction_progress = .5
	heavy_fortress.hp = 2970
	heavy_fortress._update_construction_visuals()
	await capture("construction",root)
	check(heavy_fortress.scaffolding.visible and heavy_fortress.construction_bar.visible,"native scaffold and progress bar during construction")
	heavy_fortress.under_construction = false
	heavy_fortress.construction_progress = 1.0
	heavy_fortress.hp = 5400
	heavy_fortress._update_construction_visuals()
	game.hud.hide()
	game.camera.size = 25
	game.camera.look_at(Vector3(0,2,-3),Vector3.UP)
	for i: int in 9: game.spawn_unit("shield_guard",1,Vector3(-3+(i%3)*2.3,0,-11-(i/3)*2.0))
	game.spawn_unit("war_elephant",1,Vector3(5,0,-12))
	game.set_running(true)
	for unit: BattleUnit in game.get_node("Units").get_children(): unit.set_physics_process(false)
	for building: BattleBuilding in game.get_node("Buildings").get_children(): building.set_physics_process(false)
	await physics_frame
	heavy_fortress._scan_time = 0
	for weapon: BuildingWeaponState in heavy_fortress.weapons: weapon.cooldown = 0
	heavy_fortress._physics_process(.5)
	await create_timer(.05).timeout
	await capture("firing",root)
	while game.get_node("ProjectilePool").active_flights.any(func(flight): return flight._active): await process_frame
	await create_timer(.025).timeout
	await capture("impact",root)
	check(game.get_node("Units").get_children().filter(func(unit): return unit.owner_id == 1 and unit.hp < unit.max_hp).size() >= 3,"real battlefield impact damages a group of enemies")
	heavy_fortress.receive_damage(6000)
	await create_timer(.16).timeout
	await capture("collapse",root)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(OUT+"visual.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"triangles":triangles},"\t"))
	print("FORTRESS_VISUAL ",checks," checks; ",failures.size()," failures; ",triangles," triangles")
	quit(0 if failures.is_empty() else 1)
