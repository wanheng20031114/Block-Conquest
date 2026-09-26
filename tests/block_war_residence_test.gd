extends SceneTree
## Production boundaries, paid upgrades and ownership changes use actual match logic.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s = %s" % [message, actual, expected])

func _run() -> void:
	create_timer(30.0).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	var home: WarBuilding = game.by_id[0]
	var enemy: WarBuilding = game.by_id[1]
	var neutral: WarBuilding = game.by_id[2]
	home.level = 4
	home.refresh_visual()
	await physics_frame
	for path: String in ["Visual/House/Roof", "Visual/House/Metal"]:
		var part: MeshInstance3D = home.get_node(path)
		var bounds := part.mesh.get_aabb()
		for corner: int in 8:
			var world := part.to_global(bounds.get_endpoint(corner))
			check(game.pick_building(game.camera.unproject_position(world)) == home, "level-four roof and crown remain inside the authored click area")
	var rates := [1.0, 1.25, 1.4, 1.5]
	var limits := [30.0, 50.0, 60.0, 80.0]
	for tier: int in [1, 2, 3, 4]:
		home.level = tier
		enemy.level = tier
		neutral.level = tier
		home.population = 10.0
		enemy.population = 10.0
		neutral.population = 10.0
		var rate: float = rates[tier - 1]
		var limit: float = limits[tier - 1]
		near(home.capacity, limit, "tier %d production limit" % tier)
		near(home.production_rate, rate, "tier %d production rate" % tier)
		game.simulate(1.0)
		near(home.population, 10.0 + rate, "tier %d one second growth" % tier)
		near(enemy.population, home.population, "enemy follows identical production rules")
		near(neutral.population, 10.0, "neutral house never produces")
		home.population = 10.0
		for delta: float in [0.13, 0.29, 0.07, 0.51]:
			game.simulate(delta)
		near(home.population, 10.0 + rate, "fractional production does not depend on frame partition")
		home.population = limit - 0.1
		game.simulate(5.0)
		near(home.population, limit, "long frame stops exactly at the production limit")
		game.simulate(1.0)
		near(home.population, limit, "population equal to the limit stays stopped")
		game._on_unit_arrived(home.building_id, 0, 1500.0)
		game.simulate(3.0)
		near(home.population, limit + 1500.0, "large reinforcement survives above the limit without natural growth")
		home.population = limit
		check(game.issue_order(home, neutral, 100) == int(limit), "all natural garrison can leave through normal dispatch")
		game.marches.clear()
		game.simulate(1.0)
		near(home.population, rate, "production resumes after dispatch leaves space")
		# Q contributes +5/s while normal production uses the same tier rate/cap.
		game.energy = 100.0
		game.cooldowns[0] = 0.0
		home.population = limit - 1.0
		check(game.cast_skill(0, home), "near-cap residence accepts Q")
		game.simulate(8.0)
		var result: float = home.population
		near(result, limit - 1.0 + 30.0 + rate / (5.0 + rate), "Q crossing the cap integrates both rates exactly")
		game.energy = 100.0
		game.cooldowns[0] = 0.0
		home.population = limit - 1.0
		check(game.cast_skill(0, home), "same tier accepts a fresh Q for small-frame comparison")
		for step: int in 80:
			game.simulate(0.1)
		near(home.population, result, "Q soft-cap crossing and expiry are frame independent at every level")
		game.energy = 100.0
		game.cooldowns[0] = 0.0
		home.population = limit + 20.0
		check(game.cast_skill(0, home), "over-cap residence accepts Q")
		game.simulate(7.0)
		near(home.population, limit + 50.0, "Q adds thirty above the cap and then stops")
	# Each purchase accepts the exact cost, rejects fractional shortfalls, and
	# changes the model, natural rate and limit only after ten seconds of work.
	game.select_building(home)
	for tier: int in [1, 2, 3]:
		home.level = tier
		home.population = tier * 10.0 - 0.01
		game.upgrade_selected()
		check(home.level == tier, "fractional purchase shortfall cannot upgrade")
		near(home.population, tier * 10.0 - 0.01, "rejected upgrade spends nothing")
		home.population = tier * 10.0
		game.upgrade_selected()
		check(home.level == tier and home.is_constructing, "exact cost starts construction at the current level")
		near(home.population, 0.0, "upgrade deducts exactly ten/twenty/thirty")
		near(home.capacity, limits[tier - 1], "construction retains the current production limit")
		game.simulate(10.0)
		check(home.level == tier + 1 and not home.is_constructing, "ten seconds completes the next residence level")
		near(home.population, rates[tier - 1] * 10.0, "construction retains ordinary production at the old rate")
		near(home.capacity, limits[tier], "completed upgrade switches production limit")
		game.simulate(1.0)
		near(home.population, rates[tier - 1] * 10.0 + rates[tier], "completed upgrade switches production rate")
		home.population = limits[tier]
		game.simulate(1.0)
		near(home.population, limits[tier], "upgraded residence stops at its new limit")
	home.population = 300.0
	game.upgrade_selected()
	check(home.level == 4 and home.population == 300.0, "maximum level cannot spend population")
	# Recruitment during construction still uses the old natural production rate.
	home.level = 1
	home.population = 10.0
	game.energy = 100.0
	game.cooldowns[0] = 0.0
	check(game.cast_skill(0, home), "recruitment starts before an upgrade")
	game.simulate(1.0)
	game.upgrade_selected()
	game.simulate(1.0)
	near(home.population, 12.0, "active Q retains the 1/s natural rate during construction")
	game._cancel_recruitment()
	game.simulate(9.0)
	check(home.level == 2 and not home.is_constructing, "construction completes after Q is cancelled")
	# Losing a level-four home restores the existing level-three silhouette and
	# derives its lower production limit without destroying over-cap survivors.
	home.level = 4
	home.population = 0.0
	home.refresh_visual()
	game.by_id[3].faction = 0
	game._on_unit_arrived(home.building_id, 1, 100.0)
	check(home.level == 3 and home.faction == 1, "capture downgrades four to three")
	near(home.capacity, 60.0, "capture derives the lower production limit")
	game.simulate(1.0)
	near(home.population, 100.0, "over-cap surviving attackers stay intact")
	check(home.get_node("Visual/House/Stone").mesh.resource_path.ends_with("house_3_stone.res"), "capture immediately shows level-three geometry")
	home.faction = 0
	home.level = 4
	home.population = 130.0
	game.convert_selected(2)
	check(home.kind == 0 and home.level == 4 and home.population == 110.0 and home.is_constructing, "conversion pays twenty and retains level-four housing until completion")
	game.simulate(10.0)
	check(home.kind == 2 and home.level == 1 and home.max_level == 1, "level-four residence converts to a fixed level-one forge")
	game.simulate(2.0)
	near(home.population, 110.0, "forge conversion pays twenty and does not produce")
	game.convert_selected(0)
	game.simulate(10.0)
	check(home.kind == 0 and home.level == 1 and home.capacity == 30.0, "conversion back derives level-one house rules")
	game.simulate(2.0)
	near(home.population, 90.0, "over-cap garrison survives conversion back")
	# At the level-one cap the AI invests to reopen growth rather than waiting
	# for an unreachable forty-person dispatch threshold.
	game.marches.clear()
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.faction = 0
		building.population = 1000.0
	var reserve: WarBuilding = game.by_id[4]
	var front: WarBuilding = game.by_id[5]
	reserve.faction = 1
	reserve.population = 30.0
	front.faction = 1
	front.population = 200.0
	game._ai_turn()
	check(reserve.is_constructing and reserve.population == 20.0, "AI invests ten soldiers from a full level-one residence")
	await game.prepare_shutdown()
	print("BLOCK_WAR_RESIDENCE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
