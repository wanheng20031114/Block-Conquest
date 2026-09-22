extends SceneTree
## Scripted native movie for reviewing door emission, bridge turns and skill motion.
## Godot --path . --script res://tests/block_war_motion_review.gd --write-movie artifacts/block_war_motion.avi --fixed-fps 30

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	var game: Node3D = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	for id: int in [0, 2, 3, 6, 8, 1, 4, 5, 7, 9]:
		var source: Node3D = game.by_id[id]
		source.faction = 0 if id in [0, 2, 3, 6, 8] else 1
		source.population = 200.0
		source.refresh_visual()
	game.update_hud()
	await create_timer(0.4).timeout
	for pair: Vector2i in [Vector2i(0, 10), Vector2i(3, 11), Vector2i(1, 10), Vector2i(5, 11)]:
		game.issue_order(game.by_id[pair.x], game.by_id[pair.y], 75, game.by_id[pair.x].faction)
	await create_timer(6.0).timeout
	game.cast_skill(1, null)
	await create_timer(3.0).timeout
	game.camera_rig.zoom_target = 37.0
	game.camera_rig.focus_at(Vector3(-12, 0, 14))
	await create_timer(6.0).timeout
	game.camera_rig.zoom_target = 58.0
	game.camera_rig.focus_at(Vector3(0, 0, 2))
	game.cast_skill(2, game.by_id[0])
	await create_timer(2.0).timeout
	await game.prepare_shutdown()
	print("BLOCK_WAR_MOTION_REVIEW complete")
	quit()
