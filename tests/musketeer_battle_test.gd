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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/musketeer-20260914"))
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	Engine.time_scale=3
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game=current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var pool: BattleProjectilePool=game.get_node("ProjectilePool")
	pool.launched.connect(record)
	subject=spawn("musketeer",0,Vector3.ZERO)
	var target:=spawn("shield_guard",1,Vector3(0,0,-5))
	subject.hold()
	subject.target=target
	subject.set_physics_process(true)
	game.set_running(true)
	var began: float=game.elapsed
	await step(.28)
	check(shots.is_empty(),"no bullet before .35s windup")
	await step(.50)
	check(shots.size()==1 and target.hp==127,"one real penetrative bullet after release")
	check(shots[0].kind=="bullet" and shots[0].time-began>=.349,"short bullet with authored windup")
	await step(7.0)
	check(shots.size()>=4,"repeated single target fire")
	for index: int in range(1,shots.size()):
		var gap: float=shots[index].time-shots[index-1].time
		check(gap>=2.199 and gap<2.27,"2.2-second cadence: "+str(gap))
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
	# Explicitly interrupt an unfinished aim using the real timer and command path.
	subject._attack_cooldown = 0
	subject.issue_attack(target)
	subject.set_physics_process(true)
	await step(.12)
	check(not subject.attack_windup.is_stopped(),"aim fixture has an active windup")
	var interrupted_count: int = shots.size()
	subject.issue_move(Vector3(2,0,2))
	subject.set_physics_process(false)
	await step(.5)
	check(shots.size()==interrupted_count and subject.attack_windup.is_stopped(),"movement interrupts .35-second aim before a bullet is launched")
	check(subject._attack_cooldown>0,"cancelled aim keeps its existing cooldown")
	# Deliberately saturate visual capacity while retaining every logical flight.
	pool.reset_all()
	target.max_hp=1000000
	target.hp=target.max_hp
	var neighbor := spawn("swordsman",1,target.position+Vector3(.7,0,0))
	for index: int in 300: pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"bullet")
	check(pool.active_flights.size()==300 and pool.get_child_count()<=256 and pool.omitted_visuals>0,"bounded visual pool with all 300 logical bullets")
	pool._physics_process(1)
	check(target.hp==994600,"all 300 bullets deal eighteen despite omitted visuals")
	pool._physics_process(1)
	check(target.hp==994600,"pooled flights cannot damage twice")
	check(neighbor.hp==110,"nearby unit receives no bullet splash")
	# A tiny musket ball must not shrink the next cannon borrower.
	var cannon: ProjectileFlight=pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"cannon")
	check(cannon.visual.get_node("Cannonball").scale==Vector3.ONE and cannon.visual.get_node("Trail").visible,"bullet borrower restores cannon size and smoke")
	pool.reset_all()
	var bullet: ProjectileFlight=pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"bullet")
	check(bullet._arc_height==0 and bullet._duration<=.35 and not bullet.visual.get_node("Trail").visible,"fast direct bullet never inherits cannon smoke")
	check(bullet.visual.get_node("Cannonball").scale.is_equal_approx(Vector3.ONE*.2),"borrowed cannon mesh becomes a small bullet")
	var hp_before: float = target.hp
	pool._physics_process(bullet._duration)
	var smoke: MeshInstance3D = bullet.visual.get_node("MusketSmoke")
	var smoke_end: Vector3 = smoke.global_position + smoke.global_basis.y * .5
	check(smoke.visible and smoke_end.is_equal_approx(bullet._end),"smoke grows along the flight to the actual hit target")
	check(not bullet._active and not bullet.visual.get_node("Cannonball").visible and target.hp==hp_before-18,"impact ends bullet damage and ball while retaining smoke")
	var fixed_end: Vector3 = bullet._end
	target.position += Vector3(2,0,0)
	pool._physics_process(.1)
	check(pool.active_flights.has(bullet) and smoke.visible and bullet._end==fixed_end and target.hp==hp_before-18,"afterimage neither follows a moving target nor applies damage again")
	pool._physics_process(.15)
	check(pool.active_flights.is_empty() and not smoke.visible,"smoke tail releases its borrowed scene after 0.24 seconds")
	var reused_cannon: ProjectileFlight = pool.launch(subject,target,DamageResolver.snapshot(subject._stats,0,0,0),"cannon")
	check(not reused_cannon.visual.get_node("MusketSmoke").visible and reused_cannon.visual.get_node("Trail").emitting,"later cannon borrower cannot inherit musket smoke")
	pool.reset_all()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open("res://.local/musketeer-20260914/battle-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("MUSKETEER_BATTLE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
