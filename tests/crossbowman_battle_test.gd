extends SceneTree
## Actual attack timer, range boundary, command cancellation and saturated pool.
var game: Node3D
var subject: BattleUnit
var shots: Array[Dictionary] = []
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func spawn(kind: String,owner: int,at: Vector3) -> BattleUnit:
	var unit: BattleUnit = game.spawn_unit(kind,owner,at)
	unit.stop()
	unit.set_physics_process(false)
	unit.navigation_agent.avoidance_enabled = false
	return unit
func step(seconds: float) -> void:
	var until: float = game.elapsed+seconds
	while game.elapsed < until-.000001: await physics_frame
func record(flight: ProjectileFlight) -> void:
	if flight._source == subject: shots.append({"time":game.elapsed,"kind":flight._kind,"origin":flight._start})
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/crossbow-20260914"))
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	Engine.time_scale=3
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game=current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var pool: BattleProjectilePool=game.get_node("ProjectilePool")
	pool.launched.connect(record)
	subject=spawn("crossbowman",0,Vector3.ZERO)
	var target:=spawn("shield_guard",1,Vector3(0,0,-5))
	subject.hold()
	subject.target=target
	subject.set_physics_process(true)
	game.set_running(true)
	var began: float=game.elapsed
	await step(.14)
	check(shots.is_empty(),"no bolt before .20s windup")
	await step(.50)
	check(shots.size()==1 and target.hp==140,"one real penetrative bolt after release")
	check(shots[0].kind=="bolt" and shots[0].time-began>=.199,"short bolt with authored windup")
	await step(3.6)
	check(shots.size()>=4,"repeated single target fire")
	for index: int in range(1,shots.size()):
		var gap: float=shots[index].time-shots[index-1].time
		check(gap>=.999 and gap<1.07,"one-second cadence: "+str(gap))
	subject.stop()
	await step(.6)
	var stopped_count: int=shots.size()
	subject.set_physics_process(false)
	await step(.4)
	check(shots.size()==stopped_count,"stop cancels pending launch")
	# Edges, not centre distances, are the common range contract.
	target.position=Vector3(0,0,-7-subject.radius-target.radius-.01)
	check(not subject._within_attack_range(target),"outside seven-edge range")
	target.position.z+=.02
	check(subject._within_attack_range(target),"inside seven-edge range")
	subject.target=target
	subject._attack_cooldown=.65
	subject.issue_attack(target)
	check(subject._attack_cooldown>=.649,"new attack order cannot reset cooldown")
	subject.stop()
	# Deliberately saturate visual capacity while retaining every logical flight.
	pool.reset_all()
	target.max_hp=1000000
	target.hp=target.max_hp
	for index: int in 300: pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"bolt")
	check(pool.active_flights.size()==300 and pool.get_child_count()<=256 and pool.omitted_visuals>0,"bounded visual pool with all 300 logical bolts")
	pool._physics_process(1)
	check(target.hp==998500,"all 300 bolts deal five despite omitted visuals")
	pool._physics_process(1)
	check(target.hp==998500,"pooled flights cannot damage twice")
	# The shared arrow presentation must reset its length after a short bolt.
	var arrow: ProjectileFlight=pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"arrow")
	check(arrow.visual.get_node("Arrow").scale==Vector3.ONE,"bolt borrower does not shrink subsequent archer arrow")
	pool.reset_all()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open("res://.local/crossbow-20260914/battle-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CROSSBOW_BATTLE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
