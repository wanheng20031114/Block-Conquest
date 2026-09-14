extends SceneTree
## Small real battles to observe the approved price/strength tradeoff, not tune it.
var game: Node3D
var results: Array[Dictionary] = []
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func duel(enemies: Array) -> void:
	game.set_running(false)
	game.clear_units()
	await physics_frame
	await physics_frame
	var gun: BattleUnit = game.spawn_unit("musketeer",0,Vector3(0,0,3.5))
	var opponents: Array[BattleUnit] = []
	var enemy_cost: int = 0
	for index: int in enemies.size():
		var enemy: BattleUnit = game.spawn_unit(enemies[index],1,Vector3((index-(enemies.size()-1)*.5)*1.2,0,-3.5))
		enemy.issue_attack(gun)
		opponents.append(enemy)
		enemy_cost += enemy._stats.cost
	gun.issue_move(Vector3(0,0,-3.5),true)
	game.set_running(true)
	var began: float = game.elapsed
	while game.elapsed-began<40:
		await physics_frame
		if not is_instance_valid(gun) or not gun.alive or opponents.all(func(unit: BattleUnit): return not is_instance_valid(unit) or not unit.alive): break
	var surviving: Array[Dictionary] = []
	for enemy: BattleUnit in opponents:
		if is_instance_valid(enemy) and enemy.alive: surviving.append({"kind":enemy.unit_type,"hp":enemy.hp})
	var gun_alive: bool = is_instance_valid(gun) and gun.alive
	var result := {"musketeer_gold":150,"opponents":enemies,"enemy_gold":enemy_cost,"seconds":game.elapsed-began,"musketeer_survived":gun_alive,"musketeer_hp":gun.hp if gun_alive else 0,"enemy_survivors":surviving}
	if game.elapsed-began>=40: failures.append("combat did not resolve: "+str(enemies))
	results.append(result)
	print("MUSKETEER_MATCHUP ",JSON.stringify(result))
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/musketeer-20260914"))
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	seed(91416)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	for enemies: Array in [["knight"],["light_cavalry"],["light_cavalry","light_cavalry"],["crossbowman","crossbowman"],["archer","archer"]]:
		await duel(enemies)
	FileAccess.open("res://.local/musketeer-20260914/matchups-results.json",FileAccess.WRITE).store_string(JSON.stringify({"results":results,"failures":failures,"limitation":"Single deterministic formation on sandbox ground; no kiting, upgrades, healing or balance changes."},"\t"))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
