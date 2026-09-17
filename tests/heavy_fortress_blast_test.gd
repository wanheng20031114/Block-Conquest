extends SceneTree
## Mixed radii, dead/moving targets, authority and visual capacity in native space.
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame
func scan_metrics(building: BattleBuilding) -> Dictionary:
	var samples: Array[float] = []
	for i: int in 20: building._acquire_weapon_targets()
	for i: int in 120:
		var start := Time.get_ticks_usec()
		for repeat: int in 8: building._acquire_weapon_targets()
		samples.append((Time.get_ticks_usec()-start)/8.0)
	samples.sort()
	var total: float = 0
	for sample: float in samples: total += sample
	return {"mean_usec":total/samples.size(),"median_usec":samples[60],"p95_usec":samples[114]}
func _run() -> void:
	create_timer(80,true,false,true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	var game: Node3D = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var fortress: BattleBuilding = game.spawn_building("heavy_fortress",0,Vector3.ZERO)
	var castle: BattleBuilding = game.spawn_building("castle",0,Vector3.ZERO)
	var center := Vector3(0,0,-12)
	var victims: Array[BattleUnit] = []
	for i: int in 500:
		var angle: float = i*TAU/500
		var unit: BattleUnit = game.spawn_unit("swordsman",1,center+Vector3(cos(angle),0,sin(angle))*((i%8)*.15))
		unit.max_hp = 100000; unit.hp = 100000
		victims.append(unit)
	game.set_running(true); game.set_physics_process(false)
	fortress.set_physics_process(false); castle.set_physics_process(false)
	for unit: BattleUnit in victims:
		unit.set_physics_process(false); unit.navigation_agent.avoidance_enabled = false
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.set_physics_process(false)
	await settle()
	check(game.sandbox_unit_count == 500,"all 500 native units participate in dense blast")
	var metrics := {"units":500,"fortress":scan_metrics(fortress),"castle":scan_metrics(castle),"scope":"CPU target acquisition; 120 samples of 8 queries. Dense blast timing includes 500 real damage callbacks."}
	var payload := DamageResolver.snapshot(fortress._stats,0,0,fortress.alliance_id)
	pool.launch(fortress,victims[0],payload,"cannon")
	pool.set_physics_process(false)
	var blast_start := Time.get_ticks_usec()
	pool._physics_process(1)
	metrics["dense_blast_usec"] = Time.get_ticks_usec()-blast_start
	check(victims.all(func(unit): return unit.hp == 99922),"one blast damages every one of 500 enemies, exceeding old 256 query cap")
	check(ProjectileFlight._blast_query_capacity > 500,"saturated local query grows without truncating victims")
	pool.reset_all()
	for i: int in 500:
		victims[i].hp = 100000
		victims[i].position = center+Vector3(10+(i%25)*1.1,0,10+(i/25)*1.1) if i>2 else center+Vector3(i*1.5,0,0)
	await settle()
	# Two victims inside, one outside. Damage remains independent of 256 visuals.
	for i: int in 300: pool.launch(fortress,victims[0],payload,"cannon",i%2)
	pool.set_physics_process(false)
	check(pool.active_flights.size() == 300 and pool.visual_count() == 256 and pool.omitted_visuals == 44,"300 real explosive flights share bounded 256 projectile visuals")
	pool._physics_process(1)
	check(victims[0].hp == 76600 and victims[1].hp == 76600 and victims[2].hp == 100000,"all 300 blasts hit both in-range enemies and spare outside target")
	pool._physics_process(.5)
	check(pool.active_flights.is_empty(),"all exploded flights retire")
	var allocated := pool.allocated_flights
	for i: int in 300: pool.launch(fortress,victims[0],payload,"cannon",i%2)
	check(pool.allocated_flights == allocated,"second burst reuses cached flight records")
	pool.reset_all(); pool.set_physics_process(false)
	check(pool.visual_count() == 0 and pool.active_flights.is_empty(),"reset clears flight payloads and visible objects")
	# Alternate large/small radii to detect accidental shared shape state leakage.
	victims[2].position = center+Vector3(0,0,3.02) # radius .5 => 2.52 ground-edge distance
	await settle()
	for kind: String in ["catapult","heavy_fortress","catapult","heavy_fortress"]:
		for i: int in 3: victims[i].hp = 100000
		var definition: CombatDefinition = BalanceCatalog.unit(kind) if kind == "catapult" else fortress._stats
		pool.launch(fortress,victims[0],DamageResolver.snapshot(definition,0,0,fortress.alliance_id),"stone" if kind == "catapult" else "cannon")
		pool.set_physics_process(false); pool._physics_process(3)
		check(victims[2].hp == (99976 if kind == "catapult" else 100000),"mixed launch radii retain their own boundary: "+kind)
		pool.reset_all()
	for i: int in 3: victims[i].hp = 100000
	pool.launch(fortress,victims[0],DamageResolver.snapshot(castle._stats,0,0,fortress.alliance_id),"cannon")
	pool.set_physics_process(false); pool._physics_process(1)
	check(victims[0].hp == 99974 and victims[1].hp == 100000,"single-target cannon stays single-target after cached blast reuse")
	pool.reset_all()
	# The target vanishes after release; impact still explodes at its last location.
	victims[0].hp = 100000; victims[1].hp = 100000
	pool.launch(fortress,victims[0],payload,"cannon")
	victims[0].alive = false
	pool.set_physics_process(false); pool._physics_process(1)
	check(victims[0].hp == 100000 and victims[1].hp == 99922,"dead primary target does not suppress nearby blast or receive duplicate damage")
	pool.reset_all(); victims[0].alive = true
	# Visual-only replicas cannot run splash arithmetic.
	victims[1].hp = 100000
	pool.launch_visual(fortress.get_projectile_origin(),center+Vector3.UP,"cannon",.3,.13,victims[0])
	pool.set_physics_process(false); pool._physics_process(1)
	check(victims[1].hp == 100000,"client cannon visual has no blast authority")
	pool.reset_all()
	game.is_authority = false
	pool.launch(fortress,victims[0],payload,"cannon")
	pool.set_physics_process(false); pool._physics_process(1)
	check(victims[1].hp == 100000,"non-authority world rejects explosive damage even with a payload")
	game.is_authority = true
	await game.prepare_shutdown(); game.queue_free(); await settle()
	metrics["checks"] = checks; metrics["failures"] = failures
	DirAccess.make_dir_recursive_absolute("res://.local/defenses/heavy_fortress")
	FileAccess.open("res://.local/defenses/heavy_fortress/blast.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	print("FORTRESS_BLAST ",JSON.stringify(metrics))
	quit(0 if failures.is_empty() else 1)
