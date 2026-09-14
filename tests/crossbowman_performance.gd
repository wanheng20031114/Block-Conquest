extends SceneTree
## Fixed 500-unit scenarios. Comparison is between unit types, not old/new builds.
var game: Node3D
var results: Dictionary = {}
func _initialize() -> void: _run.call_deferred()
func measure(kind: String) -> void:
	game.set_running(false)
	game.clear_units()
	await process_frame
	await physics_frame
	for index: int in 250:
		var at := Vector3((index%20-9.5)*2.5,0,(index/20-6)*4.5)
		var unit: BattleUnit=game.spawn_unit(kind,0,at)
		unit.hold()
		var target: BattleUnit=game.spawn_unit("shield_guard",1,at+Vector3(0,0,-2))
		target.max_hp=1000000
		target.hp=target.max_hp
		target.stop()
		target.set_physics_process(false)
		target.navigation_agent.avoidance_enabled=false
		unit.target=target
	game.set_running(true)
	await create_timer(1.5).timeout
	var pool: BattleProjectilePool=game.get_node("ProjectilePool")
	var start: int=Time.get_ticks_usec()
	var previous: int=start
	var shots: int=pool.launch_count
	var samples: Array[float]=[]
	while Time.get_ticks_usec()-start<5000000:
		await process_frame
		var now: int=Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous=now
	samples.sort()
	results[kind]={"units":500,"shooters":250,"median_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*.95)],"frames":samples.size(),"shots":pool.launch_count-shots,"peak_flights":pool.peak_active,"visuals":pool.get_child_count()}
	print("CROSSBOW_PERFORMANCE ",kind," ",JSON.stringify(results[kind]))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/crossbow-20260914"))
	create_timer(55,true,false,true).timeout.connect(func():quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	seed(91415)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game=current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.hud.hide()
	game.camera_rig.set_process(false)
	game.camera_rig.camera.position=Vector3(8,60,-50)
	game.camera_rig.camera.look_at(Vector3.ZERO,Vector3.UP)
	game.camera_rig.camera.size=90
	await measure("archer")
	await measure("crossbowman")
	results.settings={"resolution":str(root.size),"gpu":RenderingServer.get_video_adapter_name(),"tps":Engine.physics_ticks_per_second,"msaa":root.msaa_3d,"limitation":"Different unit workloads on the same build; not a before/after regression baseline."}
	FileAccess.open("res://.local/crossbow-20260914/performance-results.json",FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit()
