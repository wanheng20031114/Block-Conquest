extends SceneTree
## GPU review of the authored scene, live marching poses and native selection UI.

var output: String
var game: Node3D

func _initialize() -> void:
	_run.call_deferred()

func capture(name: String) -> void:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)
	print("HEIGHT_CAPTURE ", name)

func frame_at(point: Vector3, zoom: float) -> void:
	game.camera.size = zoom
	game.camera_rig.zoom_target = zoom
	game.camera_rig.focus_at(point, true)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.gui_disable_input = true
	root.size = Vector2i(1600, 900)
	var session := root.get_node("Session")
	for map_id: String in ["terraces", "switchback", "crown"]:
		session.block_war_map_id = map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.camera_rig.edge_scroll = false
		game.ai_enabled = false
		game.audio.muted = true
		game.hud.get_node("%Toast").hide()
		game.map.set_visual_paused(true)
		frame_at(Vector3.ZERO, game.camera_rig.maximum_zoom)
		await capture(map_id + "_overview")
		if OS.get_cmdline_user_args().has("--terrain-only"):
			var ledge := Vector3(11, 0, 9) if map_id == "terraces" else Vector3(15, 0, -16) if map_id == "switchback" else Vector3(-27, 0, 21)
			frame_at(ledge, 34.0)
			await capture(map_id + "_terrain_detail")
			await game.prepare_shutdown()
			continue
		var target: WarBuilding = game.buildings[-1] if map_id != "crown" else game.buildings[14]
		var source: WarBuilding = game.buildings[0] if map_id != "crown" else game.buildings[2]
		var route: PackedVector3Array = game.map.get_building_route(source, target)
		game.marches.send(source.building_id, target.building_id, source.faction, 120, route)
		var focus := Vector3(-18, 0, 0) if map_id == "terraces" else Vector3(0, 0, -14) if map_id == "switchback" else Vector3(-43, 0, 0)
		# Spread real units along the saved route to inspect every elevation seam.
		for index: int in game.marches._units.size():
			var unit: WarMarches.MarchUnit = game.marches._units[index]
			unit.distance = unit.order.length * float(index / 6 + 1) / 22.0
			game.marches._update_pose(unit)
		game.marches._render()
		frame_at(focus, 28.0)
		await capture(map_id + "_ramp_troops")
		for frame: int in 36:
			game.marches.tick(1.0 / 30.0)
			await process_frame
		await capture(map_id + "_ramp_motion")
		frame_at(target.global_position, 28.0)
		await capture(map_id + "_summit")
		# An owned tower reveals how its subtle range decal follows the upper
		# terrace, slopes and lower ground without painting buildings or trees.
		var tower: WarBuilding = game.buildings[10] if map_id == "crown" else target
		tower.faction = 0
		tower.refresh_visual()
		tower.set_attack_range_emphasis(true, false)
		tower._update_attack_range(1.0)
		frame_at(tower.global_position, 34.0)
		await capture(map_id + "_tower_range")
		if map_id == "switchback":
			# Different receivers and effects straddle both a ramp and a sheer edge.
			game.marches.clear()
			var slope: Vector3 = game.map.definition.surface_point(Vector3(0, 0, -13))
			game.marches.create_haste_zone(0, slope, 7.0, 6.0, 1.5)
			game.world_effects.update_skills(0.0, game.faction_skills, game.shields, game.by_id, game.marches)
			frame_at(Vector3(0, 0, -12), 30.0)
			await capture("switchback_haste_ramp")
			game.marches.clear()
			game.world_effects.update_skills(0.0, game.faction_skills, game.shields, game.by_id, game.marches)
			var ledge: Vector3 = game.map.definition.surface_point(Vector3(7, 0, 0))
			game.world_effects.get_node("Rabbit").start_recall(0, ledge, 7.0)
			game.world_effects.get_node("Rabbit").tick(0.3)
			frame_at(Vector3(7, 0, 0), 30.0)
			await capture("switchback_recall_cliff")
			game.world_effects.get_node("Rabbit").reset()
			var fire: RefCounted = game.start_fire(ledge, 7.0, 0)
			fire.age = 0.8
			game.world_effects.sync_fire_states(game.fire_states)
			await capture("switchback_fire_cliff")
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	for size_class: int in 3:
		current_scene.get_node("%%Size%d" % size_class).pressed.emit()
		current_scene.get_node("%Map2").pressed.emit()
		await capture("selection_" + str(size_class))
	print("BLOCK_WAR_HEIGHTS_VISUAL complete")
	quit()
