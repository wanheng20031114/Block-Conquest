extends SceneTree
## Rule hazards survive particle pool reuse, hiding, and visual resynchronization.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		# Keep population stationary without the forge's faction defense bonus.
		building.kind = 3
		building.population = 100.0
	var target: WarBuilding = game.by_id[1]
	target.position = Vector3.ZERO
	var fire: RefCounted = game.world_effects.start_fire(Vector3.ZERO, 4.5, 0)
	check(fire.get_class() == "RefCounted", "authoritative fire owns no native visual node")
	check(fire.effect_id == 1 and game.fire_states[0] == fire, "fire has a stable match identity")
	var pool: Node = game.world_effects.get_node("FireWaves")
	for index: int in pool.get_child_count():
		game.world_effects.start_fire(Vector3(1000 + index * 20, 0, 1000), 4.5, 1)
	check(game.fire_states.size() == pool.get_child_count() + 1, "rules retain more simultaneous hazards than particle slots")
	check(pool.get_child(0).effect_id != fire.effect_id, "oldest particle slot was actually reused")
	game.simulate(0.3)
	check(is_equal_approx(target.population, 75.0), "overwritten fire still damages building exactly once")
	check(fire.hit_buildings.has(1) and is_equal_approx(fire.age, 0.3), "damage ledger and age belong to rule state")
	for visual: WarFireWave in pool.get_children():
		visual.tick(30.0)
		visual.clear_visual()
		visual.radius = 0.001
	check(is_equal_approx(fire.age, 0.3) and fire.radius == 4.5 and fire.hit_buildings.has(1), "arbitrary visual aging and reset cannot mutate age radius or hit ledger")
	game.world_effects.hide()
	game.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 20)]))
	var soldier: WarMarches.MarchUnit = game.marches._units[0]
	game.simulate(0.1)
	check(not soldier.alive, "hidden reused visuals cannot prevent a later soldier from burning")
	check(is_equal_approx(target.population, 75.0), "visual restart cannot damage an already-hit building again")
	var before: float = target.population
	var ledger: Dictionary = fire.hit_buildings.duplicate()
	for attempt: int in 4:
		game.world_effects.sync_fire_states(game.fire_states)
	check(target.population == before and fire.hit_buildings == ledger, "repeated snapshot presentation never repeats fire damage")
	game.simulate(3.0)
	check(game.fire_states.is_empty() and not game.world_effects.has_fire(), "expired independent hazards are released")
	check(pool.get_children().all(func(visual: WarFireWave): return not visual.visible), "cleared states hide every authored renderer")
	var later: RefCounted = game.world_effects.start_fire(Vector3.ZERO, 4.5, 0)
	check(later.effect_id > pool.get_child_count() + 1 and later.hit_buildings.is_empty(), "later fires never reuse identity or earlier hit ledger")
	game._tick_fire_buildings()
	check(is_equal_approx(target.population, 50.0), "new fire can independently hit a previously burned building")
	await game.prepare_shutdown()
	print("BLOCK_WAR_FIRE_STATE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
