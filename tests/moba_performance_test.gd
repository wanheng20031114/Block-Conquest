extends SceneTree
## Worst-case population with real targeting, navigation and damage enabled.
var game: Node3D
var timings: Array[float] = []
var physics: Array[float] = []
var started: int
var peak_count: int = 0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.local/moba-test1")
	create_timer(100, true, false, true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	root.size = Vector2i(1600,900)
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_running(false)
	game.camera_rig.edge_scroll = false
	game.hero_controller.set_follow(false)
	game.camera_rig.set_process(false)
	game.camera_rig.focus_at(Vector3.ZERO,true)
	var kinds := ["spearman", "swordsman", "archer", "archer", "musketeer", "shield_guard", "light_cavalry", "crossbowman", "knight", "cannon"]
	for owner: int in 2:
		var count: int = 0
		for x: int in range(8,79,3):
			if count >= 238: break
			for z: int in range(-15,16,3):
				if count >= 238: break
				var at := Vector3(x * (-1 if owner == 0 else 1),0,z)
				if not game.get_node("ConstructionNavigation").contains_walkable_point(at): continue
				var unit: BattleUnit = game.spawn_unit(kinds[count%kinds.size()],owner,at)
				unit.set_meta("moba_lane",1 if z>0 else -1)
				unit.set_meta("moba_file", (count / 2) % 5 - 2)
				var target: BattleBuilding = game.get_node("Director").objective_for(owner,1 if z>0 else -1)
				unit.set_meta("moba_objective",target.entity_id)
				unit.issue_move(target.position,true)
				count += 1
		print("MOBA_STRESS_SPAWN owner=",owner," count=",count)
	game.set_running(true)
	await create_timer(2).timeout
	started = Time.get_ticks_usec()
	var previous: int = started
	for frame: int in 1200:
		await process_frame
		var now := Time.get_ticks_usec()
		timings.append(float(now-previous)/1000)
		previous = now
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		peak_count = maxi(peak_count,game.army_counts[0]+game.army_counts[1]+2)
	timings.sort()
	physics.sort()
	var result := {"gpu":RenderingServer.get_video_adapter_name(),"resolution":"1600x900", "peak_entities":peak_count, "frames":timings.size(),"frame_median_ms":timings[timings.size()/2],"frame_p95_ms":timings[int(timings.size()*.95)],"physics_median_ms":physics[physics.size()/2],"physics_p95_ms":physics[int(physics.size()*.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"remaining_army":Array(game.army_counts),"bounty":Array(game.earned_gold)}
	FileAccess.open("res://.local/moba-test1/performance.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MOBA_PERFORMANCE ",JSON.stringify(result))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/moba-test1/stress.png")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit()
