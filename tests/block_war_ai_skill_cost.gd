extends SceneTree
## A bounded CPU sample; no native windows or GPU benchmark required.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	var game: Node3D = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.set_process(false)
	var visible: Array[WarMarches.MarchUnit] = []
	for group: int in 24:
		var start := Vector3(-36 + (group % 8) * 9, 0, -20 + (group / 8) * 18)
		game.marches.send(1000 + group, group % 2, group % 2, 60, PackedVector3Array([start, start + Vector3(25, 0, 0)]))
	for unit: WarMarches.MarchUnit in game.marches._units:
		unit.distance = maxf(0.0, -unit.distance)
		game.marches._update_pose(unit)
		visible.append(unit)
	var ai := preload("res://scripts/block_war/war_ai_skills.gd").new(1)
	var samples: Array[float] = []
	for iteration: int in 12:
		var begin := Time.get_ticks_usec()
		ai._fire_target(game, visible)
		samples.append(float(Time.get_ticks_usec() - begin) / 1000.0)
		await process_frame
	samples.sort()
	print("BLOCK_WAR_AI_SKILL_COST units=", visible.size(), " median_ms=", samples[6], " max_ms=", samples[-1])
	await game.prepare_shutdown()
	quit()
