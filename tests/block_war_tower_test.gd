extends SceneTree
## Real projectiles: acquire a live soldier, travel, then resolve one actual hit.

var game: Node3D
var tower: WarBuilding
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func reset_match(level: int = 1, faction: int = 0) -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	tower = game.by_id[6]
	tower.kind = 1
	tower.level = level
	tower.faction = faction
	tower.population = 100.0
	tower.refresh_visual()
	await physics_frame

func spawn(offset: Vector3, faction: int, count: int = 1) -> void:
	var start := tower.global_position + offset
	game.marches.send(100 + faction, 12, faction, count, PackedVector3Array([start, start + Vector3(0, 0, 40)]))

func land() -> void:
	var duration := 0.0
	for shot: Dictionary in game.projectiles:
		duration = maxf(duration, shot.duration - shot.age)
	game.simulate(duration + 0.001)

func _run() -> void:
	create_timer(60.0).timeout.connect(func(): quit(3))
	for faction: int in [0, 1]:
		for tier: int in [1, 2, 3]:
			await reset_match(tier, faction)
			var enemy := 1 - faction
			spawn(Vector3(5, 0, 0), enemy, 6)
			spawn(Vector3(5, 0, 2), faction, 6)
			game.marches.tick(0.25)
			game.simulate(0.001)
			check(game.projectiles.size() == tier and game.marches.total_for(enemy) == 6, "each tier launches its own volley without killing before impact")
			var first: WarMarches.MarchUnit = game.projectiles[0].target
			check(first.alive and first.reserved, "a projectile holds the actual live target through MultiMesh slot changes")
			land()
			check(game.marches.total_for(enemy) == 6 - tier and not first.alive, "arriving balls kill exactly their targeted hostile soldiers")
			check(game.marches.total_for(faction) == 6, "tower volleys never harm friendly soldiers")
			check(game.world_effects._deaths.size() == tier and game.world_effects.get_node("Casualties").multimesh.visible_instance_count == tier, "every hit produces a visible falling soldier")
			check(game.projectiles.is_empty(), "resolved projectiles leave no floating trails")
			var reload: float = game.tower_clocks[tower.building_id]
			game.simulate(reload - 0.01)
			check(game.projectiles.is_empty(), "reload cannot launch a volley early")
			game.simulate(0.011)
			check(game.projectiles.size() == tier and game.marches.total_for(enemy) == 6 - tier, "reload launches the next live volley before damage")
			land()
			check(game.marches.total_for(enemy) == 6 - tier * 2, "the next volley also resolves only on impact")
	for tier: int in [1, 2, 3]:
		await reset_match(tier)
		var reach: float = [11.0, 13.0, 15.0][tier - 1]
		check(game.tower_range(tower) == reach, "tier %d exposes its larger actual range" % tier)
		spawn(Vector3(reach + 0.05, 0, 0), 1)
		game.simulate(0.001)
		check(game.projectiles.is_empty() and game.tower_clocks[tower.building_id] == 0.0, "outside-range scans do not consume reload")
		game.marches.clear()
		spawn(Vector3(-reach + 0.05, 0, 0), 1)
		game.simulate(0.001)
		check(game.projectiles.size() == 1, "a newly in-range soldier is acquired immediately")
		land()
		check(game.marches.total_for(1) == 0, "inside-range projectile reaches the moving target")
		for direction: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			game.tower_clocks[tower.building_id] = 0.0
			spawn(direction * 5.0, 1)
			game.simulate(0.001)
			check(game.projectiles.size() == 1, "a cannon aims at each cardinal direction")
			var shot: Dictionary = game.projectiles[0]
			var forward: Vector3 = -tower.get_node("Visual/Tower/Gun").global_basis.z
			forward.y = 0.0
			check(forward.normalized().dot(direction) > 0.999, "cannon barrel actually faces its target")
			check(shot.at.distance_to(tower.muzzle_position()) < 0.001, "ball leaves the authored muzzle at the current model tier")
			check(shot.to.distance_to(shot.target.position + Vector3(0, 0.65, 0)) < 0.001, "ball aims at the moving soldier's body")
			land()
	await reset_match()
	spawn(Vector3(8, 0, 0), 1)
	game.simulate(0.02)
	var flight: Dictionary = game.projectiles[0]
	var at: Vector3 = flight.position
	var clock: float = flight.age
	game.set_paused(true)
	game.simulate(4.0)
	check(flight.age == clock and flight.position == at and game.marches.total_for(1) == 1, "pause freezes projectile, target and impact timing")
	check(game.world_effects.get_node("Hits/Hit0/Sparks").speed_scale == 0.0, "pause freezes muzzle and impact particles")
	game.set_paused(false)
	land()
	check(game.marches.total_for(1) == 0, "resuming completes the pending shot")
	# Removing a target while its ball flies must never damage a replacement slot.
	await reset_match()
	spawn(Vector3(6, 0, 0), 1)
	game.simulate(0.001)
	var old_target: WarMarches.MarchUnit = game.projectiles[0].target
	game.marches.clear()
	spawn(Vector3(6, 0, 0), 1)
	land()
	check(not old_target.alive and game.marches.total_for(1) == 1, "a stale target reference cannot kill the new occupant of its render slot")
	# Upgrade completion changes future range and volleys, never a ball in flight.
	await reset_match()
	game.select_building(tower)
	game.upgrade_selected()
	game.simulate(9.9)
	check(tower.level == 1 and tower.population == 70.0 and game.tower_range(tower) == 11.0, "construction retains the current tower's combat rules")
	spawn(Vector3(5, 0, 0), 1, 6)
	game.marches.tick(0.25)
	game._fire_tower(tower)
	check(game.projectiles.size() == 1, "unfinished level two still fires one ball")
	game.simulate(0.1)
	check(tower.level == 2 and game.tower_range(tower) == 13.0, "ten-second completion expands range to thirteen")
	land()
	check(game.marches.total_for(1) == 5, "an in-flight level-one ball is not multiplied by upgrading")
	game.marches.clear()
	game.upgrade_selected()
	game.simulate(10.0)
	check(tower.level == 3 and tower.population == 10.0 and game.tower_range(tower) == 15.0, "third tier completes with its original cost and fifteen-metre range")
	# Neutral towers stay silent; capture swaps targeting after the same 0.6s delay.
	await reset_match(3, -1)
	spawn(Vector3(4, 0, 0), 0)
	spawn(Vector3(5, 0, 0), 1)
	game.simulate(0.1)
	check(game.projectiles.is_empty(), "neutral towers cannot fire")
	tower.population = 0.0
	game._on_unit_arrived(tower.building_id, 0, 100.0)
	game.simulate(0.59)
	check(game.projectiles.is_empty() and tower.level == 2, "capture immediately downgrades and preserves its firing delay")
	game.simulate(0.02)
	land()
	check(game.marches.total_for(0) == 1 and game.marches.total_for(1) == 0, "captured tower targets the new owner's enemies")
	tower.population = 0.0
	game._on_unit_arrived(tower.building_id, 1, 100.0)
	game.simulate(0.61)
	land()
	check(tower.level == 1 and game.marches.total_for(0) == 0, "recapture reverses target allegiance and immediately downgrades again")
	print("BLOCK_WAR_TOWER checks=", checks, " failures=", failures.size())
	await game.prepare_shutdown()
	quit(0 if failures.is_empty() else 1)
