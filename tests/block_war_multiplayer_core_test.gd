extends SceneTree
## Authority and seat boundaries use the real battle rules, without a socket.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var presentations: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func config() -> Dictionary:
	var result := {"map_id": "highland", "host_player_id": 105, "slots": []}
	var commanders := ["squirrel", "rabbit", "bear", "frog", "rabbit", "bear"]
	for faction: int in 6:
		result.slots.append({"slot_id": faction, "faction_id": faction, "team_id": faction % 2,
			"kind": "human" if faction in [1, 4, 5] else "bot", "commander": commanders[faction],
			"player_id": 100 + faction if faction in [1, 4, 5] else -1, "name": "Seat %d" % faction,
			"controller": "human" if faction in [1, 4, 5] else "bot", "control_epoch": 1})
	return result

func clean() -> void:
	game.marches.clear()
	game.projectiles.clear()
	game.bear.shots.clear()
	game.simulation_paused = false
	game._local_menu = false
	game.finished = false
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.kind = 0
		building.level = 1
		building.population = 60.0
		building.faction = building.building_id if building.building_id < 6 else -1
		building.refresh_visual()
	for state: RefCounted in game.faction_skills:
		state.cooldowns.fill(0.0)
		state.energy = 100.0
	presentations.clear()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.configure_match(config(), 105)
	game.presentation_event.connect(func(kind: String, payload: Dictionary): presentations.append({"kind": kind, "payload": payload}))
	check(game.local_faction == 5 and game.local_team == 1 and game.online_host, "host can occupy final seat on opposing team")
	check(game._bot_factions == [0, 2, 3], "bots occupy arbitrary seats including faction zero")
	for slot: Dictionary in config().slots:
		check(game.faction_skills[slot.faction_id].commander == StringName(slot.commander), "commander belongs to individual seat %d" % slot.faction_id)
	game.energy = 71.0
	check(game.faction_skills[5].energy == 71.0 and game.faction_skills[0].energy == 30.0, "local HUD energy reads and writes own account")
	check(game.faction_name(5) == "Seat 5（你）" and game.faction_name(0) == "Seat 0", "names follow player identity instead of faction zero")
	clean()
	game.select_building(game.by_id[5])
	game.morale.adjust(5, 2000.0)
	game.update_hud()
	var debug: Dictionary = preload("res://scripts/block_war/war_debug_data.gd").capture(game)
	check(is_equal_approx(debug.attack_multiplier, 1.15) and is_equal_approx(debug.defense_multiplier, 1.60) and is_equal_approx(debug.speed_multiplier, 1.30), "optional debug data uses local morale rather than first player's morale")
	check(game.hud.get_node("%Balance")._order == [5, 1, 3, 0, 2, 4], "own faction and teammates lead the territory bar")
	check(game.hud.get_node("UI/Enemy/Role").text == "1 名玩家 · 2 名电脑", "enemy panel identifies human and bot mixture")
	check(game.hud.get_node("%Balance").get_node("Stars/Faction5").tooltip_text.begins_with("Seat 5（你）"), "morale tooltip labels local seat")
	for faction: int in 6: game.by_id[faction].population = 0.4
	game.update_hud()
	check(game.hud.get_node("%PlayerTotal").text == "1" and game.hud.get_node("%EnemyTotal").text == "未知", "team HUD preserves known fractional totals and hides enemy population")
	check(game.total_for(5) == 0 and game.team_total_for(5) == 1, "individual floor and aggregate team floor remain distinct")
	for faction: int in 6: game.by_id[faction].population = 60.0

	# Local menus cannot pause a host or forbid another human's valid command.
	game.set_paused(true)
	var before: float = game.elapsed
	game.simulate(0.1)
	check(game.elapsed > before and not game.is_rule_paused(), "online host simulates while its menu is open")
	check(game.execute_network_command(1, {"type": "dispatch", "source": 1, "target": 7, "percent": 50}).accepted, "remote order accepted while host menu is open")
	check(not game.submit_player_command({"type": "upgrade", "building": 5}).accepted, "menu blocks only local input")
	game.simulation_paused = true
	before = game.elapsed
	game.simulate(1.0)
	check(game.elapsed == before and not game.execute_network_command(1, {"type": "upgrade", "building": 1}).accepted, "real network pause blocks simulation and commands")
	game.simulation_paused = false
	game.set_paused(false)

	clean()
	check(not game.execute_network_command(5, {"type": "dispatch", "source": 1, "target": 7, "percent": 50}).accepted, "same-team human cannot order another player's garrison")
	check(not game.execute_network_command(5, {"type": "upgrade", "building": 0}).accepted, "opponent cannot upgrade another faction's building")
	check(not game.execute_network_command(5, {"type": "convert", "building": 5, "kind": -1}).accepted, "convert cannot disguise an upgrade")
	check(not game.execute_network_command(5, {"type": "dispatch", "source": 5, "target": 7, "percent": 51}).accepted, "arbitrary dispatch percentages rejected")
	check(not game.execute_network_command(-1, {"type": "upgrade", "building": 5}).accepted, "neutral faction cannot submit input")
	check(not game.execute_network_command(6, {"type": "upgrade", "building": 5}).accepted, "out of range faction rejected")
	for malformed: Variant in [null, true, "5", 5.2, INF, NAN, 2147483648]:
		check(not game.execute_network_command(5, {"type": "upgrade", "building": malformed}).accepted, "invalid building type/range rejected: %s" % str(malformed))
	check(not game.execute_network_command(5, {"type": "upgrade", "building": 99999}).accepted, "missing building safely rejected")
	check(not game.execute_network_command(5, {"type": "skill_ground", "skill": 1, "x": INF, "z": 0}).accepted, "nonfinite skill point rejected")
	check(not game.execute_network_command(5, {"type": "skill_ground", "skill": 99, "x": 0, "z": 0}).accepted, "invalid skill index safely rejected")
	check(not game.execute_network_command(5, {"type": "skill_ground", "skill": 1, "x": 999999, "z": 0}).accepted, "out of map skill point rejected")
	check(game.execute_network_command(5, {"type": "upgrade", "building": 5.0}).accepted, "integral JSON numeric identifier accepted")
	check(game.by_id[5].population == 50.0 and game.by_id[5].is_constructing, "host pays construction once through shared action")
	check(not game.execute_network_command(5, {"type": "upgrade", "building": 5}).accepted and game.by_id[5].population == 50.0, "busy construction rejects second payment")
	check(game.cast_skill(0, game.by_id[5]), "default skill faction resolves to local seat five")
	check(game.by_id[5].level == 2 and game.by_id[5].population == 55.0, "bear completion refund survives command routing")
	check(presentations.any(func(event: Dictionary): return event.kind == "skill" and event.payload.faction == 5 and event.payload.target == 5), "successful skill produces primitive event for own seat")
	check(presentations.any(func(event: Dictionary): return event.kind == "construction_complete"), "instant skill completion publishes construction fact")

	# Identity survives recall and array compaction; aim-only orders consume none.
	clean()
	var route := PackedVector3Array([Vector3(-10, 0, 0), Vector3(10, 0, 0)])
	game.marches.send(5, 7, 5, 12, route)
	game.marches.tick(1.0)
	var first: WarMarches.MarchUnit = game.marches._units[0]
	var second: WarMarches.MarchUnit = game.marches._units[1]
	var first_id := first.unit_id
	var outbound_id := first.order.order_id
	var next_id: int = game.marches._next_order_id
	var returning: WarMarches.MarchOrder
	for preview: int in 30:
		returning = game.marches.return_order(first.order)
	check(game.marches._next_order_id == next_id and returning.order_id == 0, "repeated recall previews do not consume order identities")
	game.marches.redirect(first, returning)
	game.marches.redirect(second, returning)
	check(returning.order_id == next_id and game.marches._next_order_id == next_id + 1, "shared return order assigned exactly once on real redirection")
	check(first.unit_id == first_id and first.order.order_id != outbound_id and second.order == first.order, "recall preserves soldiers and replaces only their shared order")
	var ids := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.unit_id > 0 and not ids.has(unit.unit_id), "each soldier has unique positive identity")
		ids[unit.unit_id] = true
	game.marches.hit_target(second, Vector3.UP)
	check(first.unit_id == first_id, "death compaction does not renumber survivors")
	var last_id: int = game.marches._next_unit_id
	game.marches.clear()
	game.marches.send_tunnel(5, 7, 5, 6, route, 0.16)
	check(game.marches._units[0].unit_id >= last_id, "tunnel spawn does not reuse cleared identities")

	# Human recovery changes controllers without rebuilding strategy/economy.
	clean()
	var strategy: RefCounted = game._ai_by_faction[0]
	strategy._next_attack_at = 123.0
	var slots: Array = config().slots
	slots[1].controller = "bot"
	game.configure_controllers(slots)
	check(game._bot_factions == [0, 1, 2, 3] and game._ai_by_faction[0] == strategy and strategy._next_attack_at == 123.0, "disconnection adds AI without resetting existing strategies")
	slots[1].controller = "human"
	game.configure_controllers(slots)
	for state: RefCounted in game.faction_skills:
		state.cooldowns.fill(99999.0)
	game._ai_turn()
	check(game.by_id[0].is_constructing and game.by_id[2].is_constructing and game.by_id[3].is_constructing, "bots act in seats zero two three")
	check(not game.by_id[1].is_constructing and not game.by_id[4].is_constructing and not game.by_id[5].is_constructing, "all human-controlled seats remain untouched by AI")

	# Replica methods must never manufacture truth even if called directly.
	clean()
	game.online_host = false
	before = game.elapsed
	game.simulate(2.0)
	check(game.elapsed == before, "client simulate never advances authoritative clock")
	check(not game.execute_network_command(5, {"type": "upgrade", "building": 5}).accepted, "client command executor cannot mutate")
	check(game.issue_order(game.by_id[5], game.by_id[7], 50) == 0, "client direct march action cannot mutate")
	check(not game.cast_ground_skill(1, Vector3.ZERO) and not game.begin_building_construction(game.by_id[5], -1, 5), "client direct skill/construction actions cannot mutate")
	game._ai_turn()
	check(game.by_id[0].population == 60.0 and not game.by_id[0].is_constructing, "client AI never spends population")
	game._finish_match(1)
	check(game.hud.get_node("%ResultTitle").text == "胜利", "odd-team local player wins when absolute team one wins")
	await game.prepare_shutdown()
	print("BLOCK_WAR_MULTIPLAYER_CORE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
