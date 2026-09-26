extends SceneTree
## Local W boundaries, ownership, exact time integration and shared UI/AI rules.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var serial := 2000

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.002, "%s: %s = %s" % [label, actual, expected])

func reset() -> void:
	game.marches.clear()
	for state: RefCounted in game.faction_skills:
		state.energy = 100.0
		state.cooldowns.fill(0.0)
		state.durations.fill(0.0)
	game.update_hud()

func soldier(faction: int, from: Vector3, to: Vector3) -> WarMarches.MarchUnit:
	serial += 1
	game.marches.send(serial, 1, faction, 1, PackedVector3Array([from, to]))
	return game.marches._units[-1]

func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		building.kind = 2
		building.population = 1000.0
		building.refresh_visual()
	var portrait: TextureRect = game.hud.get_node("UI/Player/Icon")
	check(portrait.texture.resource_path.ends_with("commanders/squirrel.png") and portrait.material == null, "default squirrel keeps its full silhouette without a circular crop")
	check(portrait.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel commander uses nearest filtering")
	check(game.hud.get_node("UI/Player/Name").text.contains("榛果"), "default commander is named 榛果")
	check(not game.cast_skill(1, null) and not game.cast_skill(1, game.by_id[0]), "W requires a ground location, never a global or building cast")
	for at: Vector3 in [Vector3.INF, Vector3(NAN, 0, 0), Vector3(100, 0, 0)]:
		check(not game.cast_ground_skill(1, at), "invalid W terrain cannot place a field")
	near(game.energy, 100.0, "rejected fields spend no energy")
	var own := soldier(0, Vector3.ZERO, Vector3(35, 0, 0))
	var enemy := soldier(1, Vector3.ZERO, Vector3(35, 0, 0))
	var ally := soldier(2, Vector3.ZERO, Vector3(35, 0, 0))
	var far := soldier(0, Vector3(0, 0, 9), Vector3(35, 0, 9))
	check(game.cast_ground_skill(1, Vector3.ZERO), "ground W creates a field")
	near(game.energy, 70.0, "field costs thirty energy")
	check(not game.cast_ground_skill(1, Vector3(8, 0, 0)), "cooldown prevents a second field and relocation")
	game.simulate(0.5)
	near(own.distance, 2.48, "own soldier inside the field gains sixty percent speed")
	near(enemy.distance, 1.55, "enemy in the same field has ordinary speed")
	near(ally.distance, 1.55, "allied commanders retain their own skill ownership")
	near(far.distance, 1.55, "own soldier on a distant route has ordinary speed")
	check(game.world_effects.get_node("HasteFields").multimesh.visible_instance_count == 1, "placed field has one native ground visual")
	game.set_paused(true)
	game.simulate(20.0)
	near(game.marches.haste_zones[0].remaining, 7.5, "pause freezes the local field")
	check(game.world_effects.get_node("HasteMotes").speed_scale == 0.0, "pause freezes the field particles")
	game.set_paused(false)
	game.simulate(7.5)
	check(game.marches.haste_zones.is_empty() and game.world_effects.get_node("HasteFields").multimesh.visible_instance_count == 0, "eight-second expiry clears gameplay and field visual together")
	reset()
	var crossing := soldier(0, Vector3(-20, 0, 0), Vector3(35, 0, 0))
	game.cast_ground_skill(1, Vector3.ZERO)
	game.marches.tick(8.0)
	near(crossing.distance, 28.175, "long tick integrates ordinary entry, nine boosted metres, then ordinary exit")
	near(game.marches.speed_multiplier(crossing), 1.0, "leaving the field removes speed immediately")
	var previous := crossing.distance
	game.marches.tick(1.0)
	near(crossing.distance - previous, 3.1, "no residual speed buff after field expiry")
	reset()
	var expiring := soldier(0, Vector3.ZERO, Vector3(35, 0, 0))
	game.marches.create_haste_zone(0, Vector3.ZERO, 4.5, 0.25, 1.6)
	game.marches.tick(1.0)
	near(expiring.distance, 3.565, "field expiring mid-tick accelerates only its first quarter second")
	reset()
	var queued := soldier(0, Vector3.ZERO, Vector3(35, 0, 0))
	queued.distance = -1.0
	game.cast_ground_skill(1, Vector3.ZERO)
	game.marches.tick(0.2)
	near(queued.distance, -0.38, "unspawned doorway queue receives no early speed")
	game.marches.tick(0.2)
	near(queued.distance, 0.384, "speed begins only after the soldier emerges into the field")
	var distances: Array[float] = []
	for small_steps: bool in [false, true]:
		reset()
		var route := PackedVector3Array([Vector3(-20, 0, -5), Vector3(-5, 0, -5), Vector3(0, 0, 0), Vector3(5, 0, 5), Vector3(30, 0, 5)])
		game.marches.send(900, 1, 0, 6, route)
		game.cast_ground_skill(1, Vector3.ZERO)
		if small_steps:
			for step: int in 160:
				game.marches.tick(0.05)
			for index: int in 6:
				near(game.marches._units[index].distance, distances[index], "curved lane %d has equal long/short-step travel" % index)
		else:
			game.marches.tick(8.0)
			for unit: WarMarches.MarchUnit in game.marches._units:
				distances.append(unit.distance)
	reset()
	for faction: int in 6:
		check(game.cast_ground_skill(1, Vector3(-25 + faction * 10, 0, 6), faction), "each faction can place its own independent field")
	check(game.world_effects.get_node("HasteFields").multimesh.visible_instance_count == 6, "six regional W visuals coexist without replacing each other")
	game.simulate(8.0)
	check(game.marches.haste_zones.is_empty(), "all faction fields expire independently")
	reset()
	check(game.cast_ground_skill(3, Vector3.ZERO), "R remains ground targeted")
	check(not game.can_cast_skill(2), "R leaves too little energy to combine immediately with E")
	check(game.cast_ground_skill(1, Vector3(12, 0, 0)), "R can be combined with one deliberate local W")
	near(game.energy, 0.0, "R plus W exhausts the common energy budget")
	await game.prepare_shutdown()
	print("BLOCK_WAR_HASTE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
