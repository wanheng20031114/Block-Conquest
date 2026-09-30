extends SceneTree
## Private-desktop capture; no foreground activation or system input.
var game: Node3D
var output: String

func _initialize() -> void:
	run.call_deferred()

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func reset() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.select_building(null)
	game.update_hud()
	await create_timer(0.3).timeout

func step(delta: float) -> void:
	game.marches.tick(delta)
	game._tick_projectiles(delta)
	game.world_effects.tick(delta)
	game.world_effects.get_node("Frog").sync(game.marches, delta)

func run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	root.get_node("Session").block_war_map_id = "rift"
	root.get_node("Session").block_war_commander = &"frog"
	await reset()
	for index: int in [0, 2]:
		var button: Button = game.hud.get_node("UI/Skills/Row/Skill%d" % index)
		var event := InputEventMouseMotion.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event, true)
		await create_timer(0.75).timeout
		await capture("hint_%d" % index)
	await reset()
	game.hud.hide()
	var center := Vector3(-23, 0, 0)
	game.camera_rig.focus_at(center + Vector3(0, 0, 3), true)
	game.camera.size = 22.0
	game.marches.send(0, 1, 0, 24, PackedVector3Array([center - Vector3(0, 0, 8), center + Vector3(0, 0, 80)]))
	game.marches.tick(2.8)
	await capture("cloak_before")
	assert(game.cast_ground_skill(2, center))
	# Compare old and new alpha on the exact same animated models and terrain.
	var mesh: MultiMeshInstance3D = game.marches.get_node("CloakedMilitia")
	var material: ShaderMaterial = mesh.material_override
	var old_material: ShaderMaterial = material.duplicate()
	var old_shader: Shader = material.shader.duplicate()
	old_shader.code = old_shader.code.replace("ALPHA = 0.012 + rim * 0.075;", "ALPHA = 0.025 + rim * 0.12;")
	old_material.shader = old_shader
	mesh.material_override = old_material
	await capture("cloak_previous")
	mesh.material_override = material
	await capture("cloak_current")
	game.camera.size = 58.0
	await capture("cloak_normal_zoom")
	game.camera.size = 22.0
	for frame: int in 72:
		step(1.0 / 24.0)
		game.camera_rig.focus_at(game.marches._units[12].position, true)
		await process_frame
		await capture("cloak_%03d" % frame)
	step(8.0)
	game.camera_rig.focus_at(game.marches._units[12].position, true)
	assert(game.marches.get_node("CloakedMilitia").multimesh.visible_instance_count == 24)
	await capture("cloak_after_11_seconds")
	await reset()
	game.hud.hide()
	var tower: WarBuilding = game.buildings[0]
	tower.kind = 1
	tower.level = 3
	tower.refresh_visual()
	center = tower.global_position + Vector3(5.0, 0, -1.0)
	game.camera_rig.focus_at(center, true)
	game.camera.size = 18.0
	game.marches.send(1, 0, 1, 18, PackedVector3Array([center - Vector3(0, 0, 5), center + Vector3(0, 0, 10)]))
	game.marches.tick(1.55)
	var cloud: Vector3 = game.marches._units[6].position
	game._fire_tower(tower)
	assert(not game.projectiles.is_empty())
	assert(game.cast_ground_skill(0, cloud))
	for frame: int in 108:
		if frame % 18 == 0:
			game._fire_tower(tower)
		step(1.0 / 24.0)
		await process_frame
		await capture("mist_%03d" % frame)
	await game.prepare_shutdown()
	print("FROG_PERSISTENCE_VISUAL complete")
	quit()
