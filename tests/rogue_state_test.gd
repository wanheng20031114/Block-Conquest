extends SceneTree
## Deterministic first-floor economy, graph guarantees and atomic checkpoint boundary.
var checks: int = 0
var failures: Array[String] = []
const TEST_SAVE: String = "user://rogue_state_test.json"

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func _fresh(strategy: String = "ranged", pack: String = "steady", seed_value: int = 721) -> RogueRunState:
	var state := RogueRunState.new()
	_check(state.start_new(strategy, pack, seed_value) == OK, "new run initializes")
	return state

func _run() -> void:
	_test_generation()
	_test_progression_and_modifiers()
	_test_recruitment_and_formation()
	_test_nodes_and_siege()
	_test_checkpoint()
	for path: String in [TEST_SAVE, TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "test save removed")
	print("ROGUE_STATE ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _test_generation() -> void:
	for pack: String in RogueCatalog.PACKS:
		var state: RogueRunState = _fresh("ranged", pack)
		_check(state.population() == 18 and state.population_cap() == 20, pack + " begins with eighteen of twenty population")
		_check(state.data.gold == 20 and state.data.bread == 3 and state.data.ap == 12 and state.data.tickets.size() == 1, "approved starting economy")
		_check(state.checkpoint_error().is_empty(), "starting checkpoint validates: " + state.checkpoint_error())
		_check(state.formation_error("outpost").is_empty() and state.formation_error("siege").is_empty(), "both default formations are valid")
	for seed_value: int in range(1, 101):
		var state: RogueRunState = _fresh("melee", "mobile", seed_value)
		_check(state.data.nodes.size() == 34 and state.data.edges.size() == 37, "4c topology size")
		var distances: Dictionary = state._distances(int(state.data.start_node))
		var battle_near: bool = false
		var camp_near: bool = false
		var emergencies_safe: bool = true
		var kinds: Dictionary = {}
		for entry: Dictionary in state.data.nodes:
			kinds[entry.kind] = int(kinds.get(entry.kind, 0)) + 1
			if entry.kind == "battle" and int(distances[int(entry.id)]) <= 2: battle_near = true
			if entry.kind == "camp" and int(distances[int(entry.id)]) <= 3: camp_near = true
			if entry.kind == "emergency" and int(distances[int(entry.id)]) <= 1: emergencies_safe = false
		_check(battle_near and camp_near and emergencies_safe and distances.size() == 34, "seed %d has accessible safe opening and connected graph" % seed_value)
		_check(kinds.battle == 6 and kinds.emergency == 2 and kinds.shop == 2 and kinds.event == 4 and kinds.camp == 3 and kinds.road == 17, "approved first-floor content counts")
	var first: RogueRunState = _fresh()
	var repeat: RogueRunState = _fresh()
	_check(JSON.stringify(first.data) == JSON.stringify(repeat.data), "same seed reproduces map, tickets, rewards and formations")

func _test_progression_and_modifiers() -> void:
	var state: RogueRunState = _fresh("ranged")
	state.data.relics = {"ranged_attack": 2, "health": 2, "range": 2, "speed": 2, "population": 2}
	var base_archer: UnitDefinition = BalanceCatalog.unit("archer")
	var archer: UnitDefinition = state.unit_definition("archer")
	_check(is_equal_approx(archer.damage, base_archer.damage * 1.2), "strategy and repeated attack relics add percentages")
	_check(is_equal_approx(archer.hp, base_archer.hp * 1.2) and is_equal_approx(archer.speed, base_archer.speed * 1.1), "health and speed stack linearly")
	_check(archer.range == base_archer.range + 2 and state.population_cap() == 30, "range and population relics stack")
	_check(state.unit_definition("cannon").range == BalanceCatalog.unit("cannon").range, "infantry range does not affect siege engines")
	_check(base_archer.damage == 11 and base_archer.hp == 60 and base_archer.range == 10, "catalog resources remain immutable")
	state.data.strategy = "melee"
	state.data.relics = {"melee_attack": 2, "melee_armor": 2, "ranged_armor": 1}
	var knight: UnitDefinition = state.unit_definition("knight")
	_check(is_equal_approx(knight.damage, BalanceCatalog.unit("knight").damage * 1.2), "melee attack modifier")
	_check(knight.bonuses == BalanceCatalog.unit("knight").bonuses, "percentage modifiers never multiply matchup bonus damage")
	_check(state.unit_definition("heavy_cannon").melee_armor == BalanceCatalog.unit("heavy_cannon").melee_armor + 3, "all-unit melee armor includes siege engines")
	state = _fresh()
	_stage(state, "battle")
	_check(state.resolve_battle(true) == OK, "normal battle resolves")
	_check(state.data.gold == 40 and state.data.bread == 5 and state.data.xp == 50 and state.data.tickets.size() == 2, "normal rewards match approved economy")
	var after: String = JSON.stringify(state.data)
	_check(state.resolve_battle(true) != OK and JSON.stringify(state.data) == after, "battle settlement cannot replay")
	_stage(state, "battle", 1)
	state.resolve_battle(true)
	_check(state.data.level == 2 and state.data.xp == 0 and state.data.bread == 8 and state.population_cap() == 25 and state.xp_required() == 150, "level adds bread and population exactly once")
	_stage(state, "emergency")
	_check(state.resolve_battle(true) == OK and state.data.phase == "reward" and state.data.pending_choices.size() == 3, "emergency waits for relic choice")
	_check(state.data.gold == 90 and state.data.bread == 11 and state.data.xp == 80 and state.data.tickets.size() == 4, "emergency economy")
	var selected_uid: int = int(state.data.roster[0].uid)
	_check(state.set_deployed(selected_uid, false) == OK and state.set_deployed(selected_uid, true) == OK, "army remains editable from emergency reward screen")
	_check(state.data.phase == "reward" and state.data.pending_choices.size() == 3, "army edits cannot skip pending emergency reward")
	var chosen: String = state.data.pending_choices[0]
	_check(state.choose_relic(chosen) == OK and state.data.phase == "map" and int(state.data.relics[chosen]) == 1, "emergency relic completes node")
	_check(state.choose_relic(chosen) != OK, "relic reward cannot replay")

func _test_recruitment_and_formation() -> void:
	var state: RogueRunState = _fresh()
	for _index: int in 100: state._add_ticket()
	for ticket: Dictionary in state.data.tickets:
		var unique: Dictionary = {}
		var cheap: bool = false
		for kind: String in ticket.candidates:
			unique[kind] = true
			cheap = cheap or int(RogueCatalog.RECRUIT[kind].bread) == 1
		_check(unique.size() == 3 and cheap, "each held ticket has three distinct choices with an affordable unit")
	state.data.tickets = [{"uid": 500, "candidates": ["swordsman", "heavy_cannon", "priest"]}]
	state.data.next_ticket_uid = 501
	var before: int = state.data.roster.size()
	_check(state.recruit(500, "swordsman", 4) != OK and state.data.bread == 3 and state.data.roster.size() == before, "batch limit has no partial mutation")
	_check(state.recruit(500, "heavy_cannon", 1) != OK and state.data.tickets.size() == 1, "insufficient bread preserves coupon")
	_check(state.recruit(500, "swordsman", 3) == OK and state.data.bread == 0 and state.data.roster.size() == before + 9 and state.data.tickets.is_empty(), "one coupon recruits three batches atomically")
	_check(state.population() == 18, "new recruits remain in standby")
	state.data.roster.clear()
	for _index: int in 5: state._add_unit("heavy_cannon", false)
	for index: int in 4:
		_check(state.set_deployed(int(state.data.roster[index].uid), true) == OK, "heavy cannon can deploy within capacity")
	_check(state.population() == 20 and state.set_deployed(int(state.data.roster[4].uid), true) != OK, "four heavy cannons fill twenty population")
	for _index: int in 100: state._add_unit("swordsman", false)
	_check(state.data.roster.size() == 105 and state.population() == 20, "standby roster is not population-limited")
	var first_uid: int = int(state.data.roster[0].uid)
	var second_layout: Array = state.data.roster[1].layouts.outpost
	_check(state.set_layout(first_uid, "siege", [0, 0, 0]) != OK, "central base cannot be occupied")
	_check(state.set_layout(first_uid, "outpost", [12, 0, 0]) != OK, "unit footprint must remain inside deployment area")
	_check(state.set_layout(first_uid, "outpost", second_layout) != OK, "deployment rejects overlapping units")
	_check(state.set_layout(first_uid, "outpost", [0.0, 7.0, 1.2]) == OK, "legal position and facing accepted")
	_check(state.data.roster[0].layouts.siege != state.data.roster[0].layouts.outpost, "two battle layouts are independent")
	_check(state.checkpoint_error().is_empty(), "large standby roster remains a valid checkpoint")

func _test_nodes_and_siege() -> void:
	var state: RogueRunState = _fresh()
	_stage(state, "shop")
	state.data.gold = 100
	var shop_id: int = int(state.data.active_node)
	_check(state.purchase(0) == OK, "shop purchase succeeds")
	var gold: int = int(state.data.gold)
	_check(state.purchase(0) != OK and state.data.gold == gold, "sold offer cannot charge or reward twice")
	state.leave_node()
	state.data.current_node = state._neighbors(shop_id)[0]
	var offers: String = JSON.stringify(state.node(shop_id).offers)
	_check(state.enter_node(shop_id) == OK and state.data.phase == "map" and JSON.stringify(state.node(shop_id).offers) == offers, "completed shop becomes traversal only and stock stays sold")
	_stage(state, "camp")
	state.data.ap = 11
	_check(state.choose_camp(0) == OK and state.data.ap == 12, "camp action points cap at twelve")
	_check(state.choose_camp(1) != OK, "camp cannot award twice")
	state.leave_node()
	_stage(state, "camp", 1)
	_check(state.choose_camp(2) == OK and state.data.pending_choices.size() == 3, "camp presents stable relic choices")
	_check(state.leave_node() != OK, "unclaimed relic selection cannot be silently skipped")
	state.choose_relic(state.data.pending_choices[0])
	_check(state.data.phase == "node" and state.leave_node() == OK, "camp choice keeps result page until explicit exit")
	state = _fresh()
	var cart: Dictionary = {}
	for entry: Dictionary in state.data.nodes:
		if entry.kind == "event" and entry.event_id == "bread_cart": cart = entry
	state.data.current_node = cart.id
	state.data.active_node = cart.id
	state.data.phase = "node"
	state.data.ap = 1
	_check(state.resolve_event(0) == OK and state.data.ap == 0 and state.data.phase == "node", "event can exhaust AP without interrupting result")
	_check(state.resolve_event(0) != OK, "event reward cannot replay")
	_check(state.leave_node() == OK and state.data.phase == "siege_briefing" and state.data.pending_siege, "node exit schedules mandatory siege")
	_check(state.checkpoint_error().is_empty(), "pending siege is a complete loadable checkpoint")
	var before: Dictionary = state.data.duplicate(true)
	_check(state.enter_node(state._neighbors(int(state.data.current_node))[0]) != OK, "pending siege blocks route movement")
	_check(state.launch_battle() == OK, "mandatory siege launches")
	_check(state.resolve_battle(true) == OK and state.data.phase == "intermission" and state.data.floor == 2 and state.data.ap == 12, "siege victory restores AP and reaches layer intermission")
	_check(state.data.gold == before.gold and state.data.bread == before.bread and state.data.xp == before.xp and state.data.roster == before.roster, "siege grants no farmable economy and casualties do not alter roster")
	_check(state.checkpoint_error().is_empty(), "intermission is a loadable checkpoint")
	state = _fresh()
	_stage(state, "battle")
	var roster: String = JSON.stringify(state.data.roster)
	_check(state.resolve_battle(false) == OK and state.data.phase == "game_over" and JSON.stringify(state.data.roster) == roster, "any combat loss ends run without removing roster units")
	state = _fresh()
	var start: int = int(state.data.start_node)
	var next: int = int(state._neighbors(start)[0])
	state.node(next).completed = true
	state.node(next).resolved = true
	state.data.ap = 1
	_check(state.enter_node(next) == OK and state.data.phase == "siege_briefing", "last AP spent on completed node still triggers siege")

func _test_checkpoint() -> void:
	var session: RogueSession = root.get_node("Session/Rogue")
	session.save_path = TEST_SAVE
	session.state = null
	_check(session.save_checkpoint() == ERR_UNCONFIGURED, "lobby null state cannot save an unstarted run")
	session.state = _fresh()
	_check(session.save_checkpoint() == OK, "first atomic checkpoint write: " + session.error_message)
	var original: String = FileAccess.get_file_as_string(TEST_SAVE)
	var loaded: Dictionary = session._read_checkpoint(TEST_SAVE)
	_check(not loaded.is_empty(), "saved plain JSON checkpoint reads and validates")
	var clone := RogueRunState.new()
	_check(clone.import_checkpoint(loaded) == OK and JSON.stringify(clone.data) == JSON.stringify(session.state.data), "checkpoint roundtrip preserves all stable data")
	_stage(session.state, "shop")
	session.state.purchase(3)
	_check(session.save_checkpoint() == ERR_BUSY and FileAccess.get_file_as_string(TEST_SAVE) == original, "mid-shop changes never overwrite checkpoint")
	session.state.leave_node()
	_check(session.save_checkpoint() == OK, "exit persists completed shop and purchase")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.gold == 8 and loaded.tickets.size() == 2, "purchase appears only after node exit checkpoint")
	var completed_shop: String = FileAccess.get_file_as_string(TEST_SAVE)
	_stage(session.state, "emergency")
	session.state.resolve_battle(true)
	var held_uid: int = int(session.state.data.roster[0].uid)
	_check(session.set_deployed(held_uid, false) == OK and FileAccess.get_file_as_string(TEST_SAVE) == completed_shop, "reward-screen formation changes do not save a half-resolved node")
	_check(session.choose_relic(session.state.data.pending_choices[0]) == OK, "emergency selection commits the combined reward and formation checkpoint")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(not loaded.roster[0].deployed and loaded.phase == "map", "reward-screen formation is preserved after node exit")
	var bad: Dictionary = loaded.duplicate(true)
	bad.version = 999
	_check(clone.import_checkpoint(bad) != OK, "unknown checkpoint version rejected")
	bad = loaded.duplicate(true)
	bad.roster[0].kind = "res://malicious.gd"
	_check(clone.import_checkpoint(bad) != OK, "saved resource paths are never accepted as unit kinds")
	bad = loaded.duplicate(true)
	bad.edges[0][1] = 33
	_check(clone.import_checkpoint(bad) != OK, "tampered graph topology rejected")
	bad = loaded.duplicate(true)
	bad.roster[0].layouts.siege = [0, 0, 0]
	_check(clone.import_checkpoint(bad) != OK, "invalid saved base-overlap formation rejected")
	var good_file: String = FileAccess.get_file_as_string(TEST_SAVE)
	var corrupt := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	corrupt.store_string(good_file.replace("sha256", "broken_digest"))
	corrupt.close()
	_check(session._read_checkpoint(TEST_SAVE).is_empty(), "corrupt checkpoint fails explicitly")
	corrupt = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	corrupt.store_string(JSON.stringify({"format": {"unexpected": true}, "snapshot": "{}", "sha256": ""}))
	corrupt.close()
	_check(session._read_checkpoint(TEST_SAVE).is_empty(), "wrong envelope field type is rejected without executing data")
	_check(session.save_checkpoint() == OK, "atomic replacement recovers from a corrupt destination")
	_check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "successful rename leaves no temporary file")
	session.state.data.phase = "game_over"
	good_file = FileAccess.get_file_as_string(TEST_SAVE)
	_check(session.save_checkpoint() == ERR_BUSY and FileAccess.get_file_as_string(TEST_SAVE) == good_file, "defeat preserves latest checkpoint")
	session.save_path = RogueSession.SAVE_PATH

func _stage(state: RogueRunState, kind: String, ordinal: int = 0) -> void:
	var found: int = 0
	for entry: Dictionary in state.data.nodes:
		if entry.kind != kind: continue
		if found != ordinal:
			found += 1
			continue
		state.data.current_node = int(entry.id)
		state.data.active_node = int(entry.id)
		state.data.phase = "battle" if kind in ["battle", "emergency"] else "node"
		state.data.battle_kind = "outpost"
		state.data.emergency = kind == "emergency"
		return
	_check(false, "test fixture node exists: " + kind)
