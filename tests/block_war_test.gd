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
	check(home.population == 60.0 and home.capacity == 30.0, "authored starting army remains above the new production limit")
	home.population = 20.0
	var initial: float = home.population
	var neutral_initial: float = neutral.population
	game.simulate(1.0)
	check(is_equal_approx(home.population, initial + 1.0), "residence produces exactly one population each second")
	check(neutral.population == neutral_initial, "neutral residence does not grow")
	home.population = 30.0
	game.simulate(2.0)
	check(home.population == 30.0, "automatic growth stops at soft cap")
	game._on_unit_arrived(0, 0, 1.0)
	game.simulate(1.0)
	check(home.population == 31.0, "reinforcement above cap is preserved")
	home.population = 60.0
	check(game.issue_order(home, neutral, 25) == 15 and home.available_population == 45.0 and home.population == 60.0, "25 percent dispatch reserves fifteen until they leave the garrison")
	check(game.marches.total_for(0) == 15 and game.marches.incoming_for(2, 0) == 15, "queued ranks remain in population total")
	check(game.issue_order(home, home, 100) == 0 and game.issue_order(game.by_id[1], home, 100) == 0, "self orders and enemy-source orders rejected")
	game.marches.clear()
	home.population = 30.0
	neutral.population = 14.0
	check(game.issue_order(home, neutral, 100) == 30 and home.available_population == 0.0 and home.population == 30.0, "100 percent commits all available militia without removing queued ranks")
	for step: int in 500:
		game.simulate(0.05)
	check(neutral.faction == 0 and neutral.population >= 16.0 and game.marches.total_for(0) == 0, "real marching soldiers capture and enter destination")
	var tower: Node3D = game.by_id[6]
	tower.population = 4.75
	tower.faction = -1
	for soldier: int in 5:
		game._on_unit_arrived(6, 0, 1.0)
	check(tower.population == 0.0 and tower.faction == -1, "five attackers trade for 4.75 defenders at a neutral level-one tower without capturing")
	game._on_unit_arrived(6, 0, 1.0)
	check(tower.faction == 0 and tower.population == 1.0, "first surviving arrival captures building")
	var forge: Node3D = game.by_id[8]
	forge.faction = 0
	check(is_equal_approx(game.attack_bonus(0), 0.1), "one forge grants its current owner ten percent attack")
	check(is_zero_approx(game.defense_bonus(home)), "forge provides no defense bonus")
	forge.faction = 1
	check(is_zero_approx(game.attack_bonus(0)) and is_equal_approx(game.attack_bonus(1), 0.1), "forge benefit transfers immediately with ownership")
	forge.faction = -1
	game.cooldowns.fill(0.0)
	var before: float = home.population
	check(game.cast_skill(0, home) and home.population == before and game.active_durations[0] == 6.0, "recruit starts six seconds of gradual militia growth")
	check(game.cooldowns[0] == 35.0 and game.cooldowns[1] == 0.0 and game.cooldowns[2] == 0.0 and game.cooldowns[3] == 0.0, "skills have independent cooldowns")
	check(not game.cast_skill(0, home) and home.population == before, "cooldown prevents repeat recruitment")
	check(not game.cast_skill(2, game.by_id[1]) and game.cooldowns[2] == 0.0, "invalid skill target does not spend cooldown")
	check(game.cast_skill(2, home), "shield targets allied building")
	home.population = 50.0
	game._on_unit_arrived(0, 1, 1.0)
	check(is_equal_approx(home.population, 49.25), "shield reduces ordinary incoming building damage by twenty-five percent")
	game.cooldowns[3] = 0.0
	game.energy = game.ENERGY_MAX
	tower.faction = -1
	tower.population = 10.0
	check(game.cast_ground_skill(3, tower.global_position), "ground fire starts without capturing")
	game.simulate(0.05)
	check(tower.population == 0.0 and tower.faction == -1, "expanding fire cannot capture without militia")
	game.cooldowns[1] = 0.0
	check(game.cast_ground_skill(1, Vector3.ZERO) and game.active_durations[1] == 8.0, "haste creates a chosen ground field without a selected building")
	var clock: float = game.elapsed
	var cd: float = game.cooldowns[0]
	game.set_paused(true)
	game.simulate(5.0)
	check(game.elapsed == clock and game.cooldowns[0] == cd and game.active_durations[1] == 8.0, "pause freezes simulation cooldown and effect time")
	check(game.issue_order(home, neutral, 50) == 0 and not game.cast_skill(0, home), "pause blocks orders and skills")
	game.set_paused(false)
	game.simulate(1.0)
	check(is_equal_approx(game.cooldowns[0], cd - 1.0) and is_equal_approx(game.active_durations[1], 7.0), "resume advances independent clocks")
	game.simulate(10.0)
	check(game.shields.is_empty() and game.active_durations[1] == 0.0, "temporary effects expire")
	game.select_building(home)
	home.population = 100.0
	game.upgrade_selected()
	check(home.level == 1 and home.is_constructing and home.population == 90.0, "house upgrade pays once and starts ten seconds of construction")
	game.simulate(10.0)
	check(home.level == 2 and home.capacity == 50.0 and home.population == 90.0, "house upgrade spends ten and raises the production limit")
	game.convert_selected(2)
	game.simulate(10.0)
	check(home.kind == 2 and home.level == 1 and home.population == 70.0, "convert costs twenty and resets building level after ten seconds")
	game.simulate(1.0)
	check(home.population == 70.0, "forge does not automatically produce troops")
	game.convert_selected(0)
	game.simulate(10.0)
	check(home.kind == 0 and home.population == 50.0 and home.capacity == 30.0, "forge converts back to a level-one residence with its production limit")
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
	check(game.by_id[1].is_constructing and game.by_id[1].population == 50.0, "AI opens with a paid residence upgrade")
	game.simulate(3.0)
	check(game.marches.total_for(1) > 0 and game.by_id[1].population >= 20, "AI expands through normal dispatch while retaining a garrison")
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
