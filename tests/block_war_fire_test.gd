extends SceneTree
## Continuous contact, friendly fire, queues, pauses and frame partitioning.

const CENTER := Vector3(-22, 0, 10)
var game: Node3D
var checks := 0
var failures: Array[String] = []
var deaths: Array[Dictionary] = []
var serial := 1000

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.001, "%s: %s = %s" % [message, actual, expected])

func reset_match() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	deaths.clear()
	game.marches.unit_defeated.connect(func(at: Vector3, _heading: Vector3, faction: int, _impulse: Vector3, burning: bool):
		deaths.append({"at": at, "faction": faction, "burning": burning})
	)

func spawn(at: Vector3, faction: int, count: int = 1) -> WarMarches.MarchUnit:
	serial += 1
	game.marches.send(serial, 1 - faction, faction, count, PackedVector3Array([at, at + Vector3(0, 0, 30)]))
	return game.marches._units[-1]

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(3))
	var expanding := {"center": Vector3.ZERO, "from_radius": 0.0, "to_radius": 4.5, "active_fraction": 1.0}
	near(WarMarches.fire_contact(Vector3(3, 0, 0), Vector3(3, 0, 0), expanding), (3.0 - 0.18) / 4.5, "stationary soldier is struck when the front touches its body")
	check(WarMarches.fire_contact(Vector3(1, 0, 0), Vector3(10, 0, 0), expanding) < 0.0, "a fast soldier that outruns the front survives")
	var constant := {"center": Vector3.ZERO, "from_radius": 4.5, "to_radius": 4.5, "active_fraction": 1.0}
	near(WarMarches.fire_contact(Vector3(-10, 0, 0), Vector3(10, 0, 0), constant), (10.0 - 4.68) / 20.0, "continuous collision catches a full-circle crossing in one frame")
	check(WarMarches.fire_contact(Vector3(-10, 0, 4.69), Vector3(10, 0, 4.69), constant) < 0.0, "a soldier just beyond contact range survives")
	near(WarMarches.fire_contact(Vector3.ZERO, Vector3(1, 0, 0), expanding, 0.7), 0.7, "queued unit cannot be burned before it emerges")
	check(WarMarches.fire_contact(Vector3(5, 0, 0), Vector3(4.9, 0, 0), expanding, 0.0, 0.2) < 0.0, "soldier already inside its destination cannot be burned later in the tick")
	var short_fire := constant.duplicate()
	short_fire.active_fraction = 0.1
	check(WarMarches.fire_contact(Vector3(-10, 0, 0), Vector3(10, 0, 0), short_fire) < 0.0, "expired fire cannot damage a later crossing")
	var partition_totals: Array[Vector2i] = []
	for small_steps: bool in [false, true]:
		await reset_match()
		var inner: Array[WarMarches.MarchUnit] = []
		var middle: Array[WarMarches.MarchUnit] = []
		var outside: Array[WarMarches.MarchUnit] = []
		for faction: int in [0, 1]:
			inner.append(spawn(CENTER + Vector3(0.05, 0, 0), faction))
			middle.append(spawn(CENTER + Vector3(2.5, 0, 0), faction))
			outside.append(spawn(CENTER + Vector3(6, 0, 0), faction))
		var queued := spawn(CENTER, 1, 120)
		var ally: WarBuilding = game.by_id[0]
		ally.position = CENTER + Vector3(1, 0, 0)
		ally.population = 200.0
		var enemy: WarBuilding = game.by_id[1]
		enemy.position = CENTER + Vector3(3, 0, 0)
		enemy.kind = 2
		enemy.level = 3
		enemy.population = 100.0
		enemy.refresh_visual()
		var neutral: WarBuilding = game.by_id[2]
		neutral.position = CENTER + Vector3(4.5, 0, 0)
		neutral.population = 10.0
		var far: WarBuilding = game.by_id[3]
		far.position = CENTER + Vector3(4.51, 0, 0)
		far.population = 100.0
		check(game.cast_ground_skill(3, CENTER), "ground fire begins at a valid point")
		check(game.energy == 40.0 and game.cooldowns[3] == 60.0, "ignition pays once and starts R's independent cooldown")
		check(inner[0].alive and inner[1].alive and enemy.population == 100.0, "ignition does not erase the entire radius before the flame arrives")
		game.simulate(0.2)
		check(not inner[0].alive and not inner[1].alive, "inner flame kills both factions")
		check(middle[0].alive and middle[1].alive and outside[0].alive, "soldiers ahead of the expanding front remain alive")
		check(enemy.population == 100.0, "distant building is untouched until the fire reaches it")
		var wave: WarFireWave = game.world_effects.get_node("FireWaves/Fire0")
		var age := wave.age
		var before: int = game.marches.total_for(1)
		game.set_paused(true)
		game.simulate(10.0)
		check(wave.age == age and game.marches.total_for(1) == before and wave.get_node("Flames").speed_scale == 0.0, "pause freezes expansion, soldiers and native flame particles")
		game.set_paused(false)
		if small_steps:
			for frame: int in 220:
				game.simulate(0.01)
		else:
			game.simulate(2.2)
		check(not middle[0].alive and not middle[1].alive, "outward fire reaches and kills both middle ranks")
		check(outside[0].alive and outside[1].alive, "soldiers outside the fire survive on both teams")
		check(queued.alive and queued.distance < 0.0, "the hidden end of the door queue is never hit")
		check(deaths.size() > 20 and deaths.all(func(death: Dictionary): return death.burning), "every contacted soldier has a burning casualty event without a damage-count cap")
		check(deaths.any(func(death: Dictionary): return death.faction == 0) and deaths.any(func(death: Dictionary): return death.faction == 1), "casualty effects include both faction colors")
		near(ally.population, 200.0, "friendly garrison remains protected inside its building")
		near(enemy.population, 100.0 - 35.0 / 1.5, "enemy building takes one defense-adjusted hit when the front arrives")
		check(neutral.population == 0.0 and neutral.faction == -1, "fire damages a boundary garrison without capturing it")
		near(far.population, 100.0, "building beyond the radius is never hit")
		partition_totals.append(Vector2i(game.marches.total_for(0), game.marches.total_for(1)))
		var late := spawn(CENTER, 0)
		game.simulate(0.1)
		check(late.alive, "cooled ground cannot keep killing new arrivals")
		game.simulate(1.0)
		check(not wave.visible and game.world_effects._deaths.is_empty(), "flames, marks and falling bodies finish their lifetimes")
	check(partition_totals[0] == partition_totals[1], "large and small frame partitions produce the same survivors")
	await reset_match()
	for faction: int in [0, 1]:
		for troop: int in 300:
			spawn(CENTER, faction)
	check(game.cast_ground_skill(3, CENTER), "crowded opposing formations can be ignited together")
	var started := Time.get_ticks_usec()
	game.simulate(0.1)
	print("BLOCK_WAR_FIRE mass_casualties=600 cpu_ms=", float(Time.get_ticks_usec() - started) / 1000.0)
	check(game.marches.total_for(0) == 0 and game.marches.total_for(1) == 0 and deaths.size() == 600, "fire has no hidden casualty cap even with six hundred simultaneous contacts")
	check(game.world_effects.get_node("Casualties").multimesh.visible_instance_count == 600, "native casualty renderer grows beyond its initial pool without losing bodies")
	game.simulate(3.0)
	check(game.world_effects._deaths.is_empty(), "large casualty wave releases every expired body")
	await game.prepare_shutdown()
	print("BLOCK_WAR_FIRE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
