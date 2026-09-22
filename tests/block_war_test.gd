extends SceneTree
## End-to-end population, dispatch, capture, skills, pause and match contracts.

var game: Node3D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func reset_match() -> void:
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	await physics_frame

func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	await reset_match()
	check(game.buildings.size() == 13, "thirteen authored building nodes")
	var own := 0
	var enemy := 0
	for building: Node3D in game.buildings:
		own += int(building.faction == 0)
		enemy += int(building.faction == 1)
	check(own == 1 and enemy == 1 and game.by_id[0].kind == 0, "exactly one starting residence per side")
	var home: Node3D = game.by_id[0]
	var neutral: Node3D = game.by_id[2]
	var initial: float = home.population
	var neutral_initial: float = neutral.population
	game.simulate(1.0)
	check(is_equal_approx(home.population, initial + 1.0), "residence produces exactly one population each second")
	check(neutral.population == neutral_initial, "neutral residence does not grow")
	home.population = 200.0
	game.simulate(2.0)
	check(home.population == 200.0, "automatic growth stops at soft cap")
	game._on_unit_arrived(0, 0, 1.0)
	game.simulate(1.0)
	check(home.population == 201.0, "reinforcement above cap is preserved")
	home.population = 60.0
	check(game.issue_order(home, neutral, 25) == 15 and home.population == 45.0, "25 percent dispatch deducts exact integer count")
	check(game.marches.total_for(0) == 15 and game.marches.incoming_for(2, 0) == 15, "queued ranks remain in population total")
	check(game.issue_order(home, home, 100) == 0 and game.issue_order(game.by_id[1], home, 100) == 0, "self orders and enemy-source orders rejected")
	game.marches.clear()
	home.population = 30.0
	neutral.population = 14.0
	check(game.issue_order(home, neutral, 100) == 30 and home.population == 0.0, "100 percent sends all available militia")
	for step: int in 500:
		game.simulate(0.05)
	check(neutral.faction == 0 and neutral.population >= 16.0 and game.marches.total_for(0) == 0, "real marching soldiers capture and enter destination")
	var tower: Node3D = game.by_id[6]
	tower.population = 5.0
	tower.faction = -1
	for soldier: int in 5:
		game._on_unit_arrived(6, 0, 1.0)
	check(tower.population == 0.0 and tower.faction == -1, "equal forces annihilate without a surviving occupier")
	game._on_unit_arrived(6, 0, 1.0)
	check(tower.faction == 0 and tower.population == 1.0, "first surviving arrival captures building")
	var forge: Node3D = game.by_id[8]
	forge.faction = 0
	forge.level = 2
	check(is_equal_approx(game.attack_multiplier(0), 1.2), "forge grants current owner global attack bonus")
	check(is_equal_approx(game.defense_multiplier(home), 1.2), "forge grants global defense bonus")
	forge.faction = 1
	check(is_equal_approx(game.attack_multiplier(0), 1.0) and is_equal_approx(game.attack_multiplier(1), 1.2), "forge benefit transfers immediately with ownership")
	forge.faction = -1
	game.cooldowns.fill(0.0)
	var before: float = home.population
	check(game.cast_skill(0, home) and home.population == before + 30.0, "recruit adds thirty militia")
	check(game.cooldowns[0] == 35.0 and game.cooldowns[1] == 0.0 and game.cooldowns[2] == 0.0 and game.cooldowns[3] == 0.0, "skills have independent cooldowns")
	check(not game.cast_skill(0, home) and home.population == before + 30.0, "cooldown prevents repeat recruitment")
	check(not game.cast_skill(2, game.by_id[1]) and game.cooldowns[2] == 0.0, "invalid skill target does not spend cooldown")
	check(game.cast_skill(2, home), "shield targets allied building")
	home.population = 50.0
	game._on_unit_arrived(0, 1, 1.0)
	check(is_equal_approx(home.population, 49.5), "shield halves incoming building damage")
	game.cooldowns[3] = 0.0
	tower.faction = -1
	tower.population = 10.0
	check(game.cast_skill(3, tower) and tower.population == 0.0 and tower.faction == -1, "siege skill cannot capture without militia")
	game.cooldowns[1] = 0.0
	check(game.cast_skill(1, null) and game.active_durations[1] == 8.0, "haste activates without selected building")
	var clock: float = game.elapsed
	var cd: float = game.cooldowns[0]
	game.set_paused(true)
	game.simulate(5.0)
	check(game.elapsed == clock and game.cooldowns[0] == cd and game.active_durations[1] == 8.0, "pause freezes simulation cooldown and effect time")
	check(game.issue_order(home, neutral, 50) == 0 and not game.cast_skill(0, home), "pause blocks orders and skills")
	game.set_paused(false)
	game.simulate(1.0)
	check(is_equal_approx(game.cooldowns[0], cd - 1.0) and game.active_durations[1] == 7.0, "resume advances independent clocks")
	game.simulate(10.0)
	check(game.shields.is_empty() and game.active_durations[1] == 0.0, "temporary effects expire")
	game.select_building(home)
	home.population = 100.0
	game.upgrade_selected()
	check(home.level == 2 and home.capacity == 300.0 and home.population == 70.0, "upgrade spends garrison and increases capacity")
	game.convert_selected(2)
	check(home.kind == 2 and home.level == 1 and home.population == 40.0, "convert costs thirty and resets building level")
	game.simulate(1.0)
	check(home.population == 40.0, "forge does not automatically produce troops")
	game.convert_selected(0)
	check(home.kind == 0 and home.population == 10.0, "forge can convert back to residence")
	game.camera_rig.focus_at(Vector3(999, 0, -999), true)
	check(game.camera_rig.position == Vector3(34, 0, -23), "camera panning stays inside battlefield bounds")
	game.camera_rig.zoom_by(999)
	check(game.camera_rig.zoom_target == 95.0, "zoom upper bound")
	game.camera_rig.drag_by(Vector2(200, 50))
	check(game.camera_rig.destination.x < 34.0, "middle mouse camera movement uses native camera projection")
	await reset_match()
	game.ai_enabled = true
	game.ai_clock = 0.0
	game.simulate(0.05)
	check(game.marches.total_for(1) > 0 and game.by_id[1].population < 20, "AI expands through same dispatch rules")
	game.ai_enabled = false
	game.marches.clear()
	var route: PackedVector3Array = game.map.get_building_route(game.by_id[0], game.by_id[2])
	game.marches.send(0, 2, 0, 30, route)
	game.by_id[0].faction = 1
	game._check_victory()
	check(not game.finished, "army still marching can rescue a faction with no buildings")
	game.marches.clear()
	game._check_victory()
	check(game.finished and game.hud.get_node("%ResultOverlay").visible, "defeat requires no buildings and no remaining marches")
	await physics_frame
	await process_frame
	var retiring_playbacks: Array[WeakRef] = game.audio._playbacks.duplicate()
	await game.prepare_shutdown()
	check(retiring_playbacks.all(func(reference: WeakRef): return reference.get_ref() == null), "shutdown releases result audio before leaving")
	game.queue_free()
	await process_frame
	print("BLOCK_WAR_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
