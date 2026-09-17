extends SceneTree
## Bounded native acquisition with 500 units and logical shots past visual capacity.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func scan_metrics(building: BattleBuilding) -> Dictionary:
	var samples: Array[float] = []
	for warmup: int in 20: building._acquire_weapon_targets()
	for sample: int in 120:
		var start: int = Time.get_ticks_usec()
		for repeat: int in 8: building._acquire_weapon_targets()
		samples.append((Time.get_ticks_usec()-start)/8.0)
	samples.sort()
	var total: float = 0
	for sample: float in samples: total += sample
	return {"mean_usec":total/samples.size(),"median_usec":samples[60],"p95_usec":samples[114]}
func _run() -> void:
	create_timer(60,true,false,true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var castle: BattleBuilding = game.spawn_building("castle",0,Vector3.ZERO)
	var tower: BattleBuilding = game.spawn_building("cannon_tower",0,Vector3.ZERO)
	for i: int in 500:
		var angle: float = i*TAU/500
		var distance: float = 7.0+(i%8)
		var unit: BattleUnit = game.spawn_unit("swordsman",1,Vector3(cos(angle)*distance,0,sin(angle)*distance))
		unit.set_physics_process(false); unit.navigation_agent.avoidance_enabled = false
	game.set_running(true); game.set_physics_process(false)
	castle.set_physics_process(false); tower.set_physics_process(false)
	for unit: BattleUnit in game.get_node("Units").get_children(): unit.set_physics_process(false)
	await physics_frame
	await process_frame
	check(game.sandbox_unit_count == 500,"native space contains full sandbox unit limit")
	var metrics := {"units":500,"cannon_tower":scan_metrics(tower),"castle":scan_metrics(castle),"scope":"CPU native target acquisition only; 120 samples of 8 queries, no GPU frame claim"}
	check(castle.weapons[0].target != castle.weapons[1].target and castle.weapons[1].target != castle.weapons[2].target,"bounded crowded query still distributes all three guns")
	var target: BattleUnit = castle.weapons[0].target
	target.max_hp = 20000; target.hp = 20000
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.reset_all(); pool.set_physics_process(false)
	var payload := DamageResolver.snapshot(castle._stats,0,0,0)
	for i: int in 300: pool.launch(castle,target,payload,"cannon",i%3)
	pool.set_physics_process(false)
	check(pool.active_flights.size() == 300 and pool.visual_count() == 256 and pool.omitted_visuals == 44,"indexed castle shots preserve all logical flights beyond bounded visuals")
	pool._physics_process(1)
	check(target.hp == 20000-300*26,"all 300 single-target castle shots resolve despite omitted visuals")
	pool._physics_process(.5)
	check(pool.active_flights.is_empty(),"impact retires every logical flight")
	var allocated: int = pool.allocated_flights
	for i: int in 300: pool.launch(castle,target,payload,"cannon",i%3)
	pool.set_physics_process(false)
	check(pool.allocated_flights == allocated,"second burst reuses cached logical records")
	pool.reset_all()
	check(pool.active_flights.is_empty() and pool.visual_count() == 0,"reset retires pending multi-gun projectiles")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://.local/defenses/castle")
	metrics["checks"] = checks; metrics["failures"] = failures
	FileAccess.open("res://.local/defenses/castle/capacity.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print("CASTLE_CAPACITY ",JSON.stringify(metrics))
	quit(0 if failures.is_empty() else 1)
