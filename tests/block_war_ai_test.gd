extends SceneTree
## Real scenes and legal orders verify economic priorities, safety and progress.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func _load_match() -> void:
	if game != null:
		await game.prepare_shutdown()
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true

func _fixture() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.shields.clear()
	game.ai_enabled = false
	game.ai_clock = 6.0
	game.elapsed = 0.0
	game._ai_strategy = game.AI_STRATEGY.new()
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.faction = -1
		building.kind = 0
		building.level = 1
		building.population = 1000.0
		building.refresh_visual()
	game.by_id[0].faction = 0
	game.by_id[0].population = 60.0
	game.by_id[1].faction = 1
	game.by_id[1].population = 60.0

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	await _load_match()
	var home: WarBuilding = game.by_id[1]
	game._ai_turn()
	check(home.is_constructing and home.level == 1 and home.population == 50.0, "opening spends ten on housing before launching an army")
	check(home.construction_remaining == 10.0 and game.marches.total_for(1) == 0, "AI uses the full ten-second construction contract")
	check(game.selected == game.by_id[0] and game.by_id[0].population == 60.0, "enemy investment does not alter the player's selection or garrison")
	game._ai_turn()
	check(game.marches.incoming_for(4, 1) + game.marches.incoming_for(5, 1) == 25, "opening chooses a nearby neutral residence with a sufficient legal wave")
	check(home.population == 25.0 and game.total_for(1) == 50, "expansion keeps a guard and conserves all unspent troops")
	game._ai_turn()
	check(game.total_for(1) == 50 and game.marches.total_for(1) == 25, "pending construction and expansion cannot be paid twice")
	game.simulate(9.9)
	check(home.level == 1 and home.is_constructing, "investment retains its old level before completion")
	game.simulate(0.1)
	check(home.level == 2 and not home.is_constructing, "AI housing completes through the normal simulation")

	_fixture()
	game.ai_enabled = true
	game.simulate(6.0)
	check(home.population == 50.0 and home.construction_remaining == 10.0, "a long opening step grants no construction time before payment")
	game.ai_enabled = false
	game.simulate(9.999)
	check(home.level == 1, "new AI construction cannot finish early after a long step")
	game.simulate(0.001)
	check(home.level == 2, "AI construction finishes exactly ten seconds after payment")
	_fixture()
	game.ai_enabled = true
	game.simulate(18.0)
	var long_step := [home.level, home.population, home.construction_remaining, game.ai_clock]
	_fixture()
	game.ai_enabled = true
	for step: int in 36:
		game.simulate(0.5)
	check(long_step == [home.level, home.population, home.construction_remaining, game.ai_clock], "long and short simulation steps make the same economic decisions at the same times")

	_fixture()
	home.population = 30.0
	var second: WarBuilding = game.by_id[4]
	second.faction = 1
	second.population = 30.0
	game._ai_turn()
	game._ai_turn()
	check(home.is_constructing and not second.is_constructing and second.population == 30.0, "two residences stagger investments and keep an army reserve")
	check(home.population == 20.0, "full level-one housing can afford development without draining its guard")

	_fixture()
	home.population = 18.0
	second.faction = 1
	second.level = 4
	second.population = 80.0
	game.by_id[0].population = 40.0
	game.issue_order(game.by_id[0], home, 75)
	game._ai_turn()
	check(game.marches.incoming_for(1, 1) == 20 and second.population == 60.0, "a threatened residence receives reinforcements before any development")
	check(home.population == 18.0 and not home.is_constructing, "incoming attackers prevent investment or dispatch from the endangered home")
	game._ai_turn()
	check(game.marches.incoming_for(1, 1) == 20, "reinforcement planning accounts for the support already on its way")
	check(game.marches.incoming_for(0, 1) == 0, "defending does not open another offensive front")

	_fixture()
	home.population = 10.0
	second.faction = 1
	second.level = 4
	second.population = 40.0
	game.by_id[0].population = 100.0
	game.issue_order(game.by_id[0], home, 100)
	game._ai_turn()
	check(game.marches.incoming_for(1, 1) == 20 and second.population == 20.0, "partial relief uses a legal safe percentage even when the full deficit is unaffordable")
	game._ai_turn()
	check(not home.is_constructing and not second.is_constructing, "unresolved invasion suspends nonessential spending")

	_fixture()
	home.level = 4
	home.population = 80.0
	game.by_id[0].level = 4
	game.by_id[0].population = 12.0
	game._ai_turn()
	check(game.marches.total_for(1) == 0 and home.population == 80.0, "AI waits when defenders will recruit enough troops during the long approach")

	_fixture()
	home.level = 4
	home.population = 80.0
	game.by_id[0].kind = 2
	game.by_id[0].population = 10.0
	game.by_id[2].faction = 0
	game.by_id[2].population = 100.0
	game.issue_order(game.by_id[2], game.by_id[0], 50)
	game._ai_turn()
	check(game.marches.total_for(1) == 0, "hostile reinforcements are included when evaluating a seemingly empty forge")
	game.marches.clear()
	game._ai_turn()
	check(game.marches.incoming_for(0, 1) > 0, "an exposed forge remains a valid target without those reinforcements")

	_fixture()
	home.level = 4
	home.population = 80.0
	game.by_id[5].population = 5.0
	game.issue_order(game.by_id[0], game.by_id[5], 25)
	game._ai_turn()
	check(game.marches.incoming_for(5, 1) == 0, "neutral land contested by an arriving player army is not treated as a free expansion")
	game.marches.clear()
	game._ai_turn()
	check(game.marches.incoming_for(5, 1) == 20, "uncontested expansion uses the smallest sufficient dispatch tier")
	var route: PackedVector3Array = game.map.get_building_route(home, game.by_id[4])
	var route_length := 0.0
	for index: int in range(1, route.size()):
		route_length += route[index - 1].distance_to(route[index])
	var queued_arrival: float = game.marches.estimate_arrival_time(1, route_length, 30)
	game.marches.clear()
	var free_arrival: float = game.marches.estimate_arrival_time(1, route_length, 30)
	check(queued_arrival > free_arrival and free_arrival > route_length / WarMarches.SPEED, "arrival planning includes queued departures and the final marching rank")

	_fixture()
	home.level = 4
	home.population = 80.0
	game.by_id[0].kind = 2
	game.by_id[0].population = 25.0
	game.shields[0] = 10.0
	game._ai_turn()
	check(game.marches.total_for(1) == 0, "shield defense prevents an understrength assault")
	game.shields.clear()
	game._ai_turn()
	check(game.marches.incoming_for(0, 1) == 60, "the same army attacks once the shield expires and the exchange is favorable")

	_fixture()
	home.level = 4
	home.population = 80.0
	game.by_id[0].faction = -1
	game.by_id[0].population = 1000.0
	var tower: WarBuilding = game.by_id[7]
	tower.faction = 0
	tower.kind = 1
	tower.level = 3
	tower.population = 30.0
	game._ai_turn()
	check(game.marches.total_for(1) == 0, "tower interception losses are budgeted before attacking its garrison")

	_fixture()
	home.level = 4
	home.population = 80.0
	second.faction = 1
	second.level = 4
	second.population = 80.0
	var forge: WarBuilding = game.by_id[9]
	forge.faction = 1
	forge.kind = 2
	forge.population = 60.0
	game._ai_turn()
	check(not forge.is_constructing and forge.population == 60.0, "an established economy never attempts to upgrade its fixed-level forge")
	check(is_equal_approx(game.attack_bonus(1), 0.1), "one forge provides ten percent attack")
	game.simulate(10.0)
	check(forge.level == 1 and is_equal_approx(game.attack_bonus(1), 0.1), "forge remains at level one without an automatic upgrade")

	_fixture()
	home.kind = 2
	home.population = 20.0
	game._ai_turn()
	check(home.conversion_target == 0 and home.population == 0.0 and home.kind == 2, "a safe surviving forge pays to restore a lost production base")
	game.simulate(11.0)
	check(home.kind == 0 and home.level == 1 and is_equal_approx(home.population, 1.0), "recovered housing resumes ordinary production after conversion")

	_fixture()
	game.set_paused(true)
	game._ai_turn()
	game.simulate(20.0)
	check(home.population == 60.0 and not home.is_constructing and game.elapsed == 0.0, "pause blocks AI orders and investment")
	game.set_paused(false)

	_fixture()
	home.faction = -1
	home.population = 1000.0
	second.faction = 1
	second.level = 4
	second.population = 80.0
	var other: WarBuilding = game.by_id[5]
	other.faction = 1
	other.level = 4
	other.population = 80.0
	game._ai_turn()
	var target_id := 4 if game.marches.incoming_for(4, 1) > 0 else 5
	var source_id := 5 if target_id == 4 else 4
	check(game.marches.incoming_for(target_id, 1) > 0, "surplus troops gather even when both homes share an X coordinate")
	check(game.by_id[source_id].population >= 14.0, "rear consolidation preserves the donor's garrison")
	game._ai_turn()
	check(game.marches.incoming_for(source_id, 1) == 0, "consolidation never bounces troops back toward the donor")

	_fixture()
	home.level = 4
	home.population = 220.0
	game.by_id[0].population = 10.0
	game._ai_turn()
	check(game.marches.incoming_for(0, 1) > 0 and home.population >= 100.0, "a prepared army commits enough troops and keeps substantial reserves")
	var committed: int = game.marches.total_for(1)
	game.elapsed += 3.0
	game._ai_turn()
	check(game.marches.total_for(1) == committed, "offensives have a recovery interval instead of launching every decision tick")
	game.elapsed += 15.0
	game._ai_turn()
	check(game.marches.total_for(1) == committed, "a target already receiving an assault is not fed another wave")
	game.simulate(60.0)
	check(game.by_id[0].faction == 1 and game.finished, "economic play still converts a clear military advantage into victory")

	await _load_match()
	game.ai_enabled = true
	var most_homes := 1
	var highest_level := 1
	var first_attack := -1.0
	var homes_at_attack := 0
	for step: int in 480:
		game.simulate(0.5)
		var homes := 0
		for building: WarBuilding in game.buildings:
			if building.faction == 1 and building.kind == 0:
				homes += 1
				highest_level = maxi(highest_level, building.level)
		most_homes = maxi(most_homes, homes)
		if first_attack < 0.0 and game.marches.incoming_for(0, 1) > 0:
			first_attack = game.elapsed
			homes_at_attack = homes
		if game.finished:
			break
	print("AI_ECONOMY_CAMPAIGN elapsed=", game.elapsed, " homes=", most_homes, " level=", highest_level, " first_attack=", first_attack, " homes_at_attack=", homes_at_attack, " finished=", game.finished)
	check(most_homes >= 3 and highest_level >= 2, "the real opening develops a productive territory instead of only sending attacks")
	check(first_attack > 0.0 and homes_at_attack >= 2, "a developed economy eventually attacks rather than remaining passive")
	await game.prepare_shutdown()
	print("BLOCK_WAR_AI checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
