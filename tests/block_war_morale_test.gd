extends SceneTree
## Real capture, construction, projectiles, movement, pause and new-match state.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < .00001, "%s: %s / %s" % [label, actual, expected])

func reset() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.morale.configure(game.faction_count)
	game.shields.clear()
	game.finished = false
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.kind = 0
		building.level = 1
		building.population = 30.0
		building.faction = building.building_id if building.building_id < 6 else -1
		game.tower_clocks[building.building_id] = 100.0
		building.refresh_visual()

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	check(game.faction_count == 6, "authored six-player battlefield")
	_captures()
	_combat()
	_interceptions()
	_movement()
	_construction_and_time()
	game.update_hud()
	await game.prepare_shutdown()
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	check(game.faction_count == 2, "new match uses its own faction count")
	near(game.morale.points(0) + game.morale.points(1), 0.0, "new match never inherits morale")
	near(game.marches.base_speed(0), WarMarches.SPEED, "new match resets marching speed")
	await game.prepare_shutdown()
	print("BLOCK_WAR_MORALE ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _captures() -> void:
	for neutral: bool in [true, false]:
		for kind: int in 3:
			for tier: int in range(1, [4, 3, 1][kind] + 1):
				reset()
				var target: WarBuilding = game.by_id[6]
				target.faction = -1 if neutral else 1
				target.kind = kind
				target.level = tier
				target.population = 0.0
				game.morale.adjust(1, 1500.0)
				game._on_unit_arrived(6, 0, 1.0)
				check(target.faction == 0 and target.level == maxi(1, tier - 1), "capture retains native ownership and downgrade")
				near(game.morale.points(0), WarMorale.capture_reward(kind, tier, neutral), "capture reward uses the level before downgrade")
				near(game.morale.points(1), 1500.0 if neutral else 1500.0 - WarMorale.loss_penalty(kind, tier), "former owner alone pays loss penalty")
				near(game.morale.points(2), 0.0, "teammates have independent morale")

func _combat() -> void:
	reset()
	var target: WarBuilding = game.by_id[1]
	target.population = 100.0
	game.morale.adjust(0, 500.0)
	game.morale.adjust(1, 4000.0)
	near(game.combat_multiplier(0, target), 1.05 / 2.0, "attack and defense use each owner's whole-star multiplier")
	game._on_unit_arrived(1, 0, 10.0)
	near(target.population, 94.75, "real attack resolves the morale coefficient")
	near(game.morale.points(0), 400.0, "ten consumed attackers lose one hundred morale")
	near(game.morale.points(1), 4100.0, "defender gains ten points per incoming attacker killed")
	near(game.combat_multiplier(0, target), .5, "dropping below one star removes its bonus immediately")
	game._on_unit_arrived(2, 0, 4.0)
	near(game.morale.points(0), 400.0, "allied reinforcement is not a combat loss")
	near(game.morale.points(2), 0.0, "receiving allied troops awards no morale")
	reset()
	target.population = 2.0
	game.morale.adjust(0, 100.0)
	game.morale.adjust(1, 100.0)
	game._on_unit_arrived(1, 0, 5.0)
	near(target.population, 3.0, "surviving attackers enter captured building")
	near(game.morale.points(0), 180.0, "capture survivors are not charged as dead attackers")
	near(game.morale.points(1), 70.0, "defensive kills and lost building each settle once")
	reset()
	game.morale.adjust(0, 10.0)
	game.morale.adjust(1, 20.0)
	game.marches.send(0, 1, 0, 1, PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 1)]))
	game._simulate_step(.4)
	near(game.morale.points(0), 0.0, "real march arrival settles its attacking loss")
	near(game.morale.points(1), 30.0, "real march arrival settles defensive kill credit")
	near(game.morale.idle_seconds(0), 0.0, "new zero-capped combat event is not backdated")
	near(game.morale.idle_seconds(1), 0.0, "new defensive event is not backdated")
	near(game.morale.idle_seconds(2), .4, "unrelated faction still accumulates idle time")

func _interceptions() -> void:
	reset()
	var tower: WarBuilding = game.by_id[6]
	tower.kind = 1
	tower.faction = 0
	var at := tower.global_position + Vector3(4, 0, 0)
	game.morale.adjust(1, 200.0)
	game.marches.send(1, 0, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game._fire_tower(tower)
	tower.faction = 1
	game._tick_projectiles(1.0)
	near(game.morale.points(0), 10.0, "shot remembers its firing faction after tower capture")
	near(game.morale.points(1), 190.0, "intercepted attacking soldier pays its loss")
	game._tick_projectiles(1.0)
	near(game.morale.points(0), 10.0, "dead projectile target cannot award a second kill")
	game.marches.send(1, 0, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 20.0, "defensive fire attributes a hostile attacking casualty")
	near(game.morale.points(1), 180.0, "fire and tower use the same attacking-loss rule")
	game.morale.adjust(0, 100.0)
	game.marches.send(0, 1, 0, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 110.0, "own fire can cost an attacking soldier")
	near(game.morale.points(1), 180.0, "friendly fire does not gift defensive-kill credit")
	game.marches.send(1, 1, 1, 1, PackedVector3Array([at, at + Vector3(0, 0, 10)]))
	game.marches.ignite_at(at, .45, 0)
	near(game.morale.points(0), 110.0, "intercepting a transfer is not killing an attacker")
	near(game.morale.points(1), 180.0, "a reinforcement was not on an attack order")

func _movement() -> void:
	reset()
	var route := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, 50)])
	game.morale.adjust(1, 4000.0)
	game.marches.send(0, 1, 0, 1, route)
	game.marches.send(1, 0, 1, 1, route)
	var ordinary: WarMarches.MarchUnit = game.marches._units[0]
	var charged: WarMarches.MarchUnit = game.marches._units[1]
	game.marches.tick(1.0)
	near(ordinary.distance, WarMarches.SPEED, "zero stars retain ordinary movement")
	near(charged.distance, WarMarches.SPEED * 1.4, "four stars change actual route travel")
	game.morale.adjust(1, 4000.0)
	charged.rush_remaining = 2.0
	near(game.marches.movement_distance(charged, 1.0), WarMarches.SPEED * 1.5 * 2.0, "morale multiplies the existing rush skill")
	near(game.marches.speed_multiplier(charged), 3.0, "movement feedback matches real morale speed")
	near(game.marches.estimate_arrival_time(1, 50, 1, 1) * 1.5, game.marches.estimate_arrival_time(0, 50, 1, 0), "AI arrival estimator uses the selected owner's morale")
	game.marches.clear()
	game.marches.queue_departure(1, 0, 1, 12, route)
	var limit: float = game.marches.departure_step_limit()
	game.morale.adjust(1, -8000.0)
	near(game.marches.departure_step_limit(), limit * 1.5, "doorway timing changes with live morale")
	game.marches.clear()

func _construction_and_time() -> void:
	reset()
	var house: WarBuilding = game.by_id[0]
	house.begin_construction()
	game.simulate(10.0)
	near(game.morale.points(0), 50.0, "actual completion gives first-upgrade reward")
	near(game.morale.idle_seconds(0), 0.0, "a long build frame does not backdate its new reward")
	game.simulate(9.99)
	near(game.morale.points(0), 50.0, "fresh reward keeps its full idle grace")
	game.simulate(.01)
	near(game.morale.points(0), 40.0, "idle decay is wired into real simulation")
	house.begin_construction()
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "immediate native completion also rewards once")
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "completed construction cannot reward again")
	house.begin_construction(1)
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "conversion cannot farm upgrade rewards")
	house.begin_construction()
	house.cancel_construction()
	house.advance_construction(10.0)
	near(game.morale.points(0), 140.0, "cancelled upgrade awards nothing")
	game.morale.adjust(0, 7860.0)
	game.set_paused(true)
	game.simulate(20.0)
	near(game.morale.points(0), 8000.0, "pause freezes the morale clock")
	game.set_paused(false)
	game.simulate(5.0)
	near(game.morale.points(0), 7800.0, "five-star idle decay uses two hundred points")
	game.finished = true
	game.simulate(20.0)
	near(game.morale.points(0), 7800.0, "game over freezes morale")
