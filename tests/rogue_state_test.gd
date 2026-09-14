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

func _fresh(strategy: String = "ranged", pack: String = "steady", seed_value: int = 721, pending: bool = false) -> RogueRunState:
	var state := RogueRunState.new()
	_check(state.start_new(strategy, pack, seed_value) == OK, "new run initializes")
	if not pending: _discard_all(state)
	return state

func _discard_all(state: RogueRunState) -> void:
	while not state.data.pending_recruits.is_empty():
		_check(state.discard_recruit(int(state.pending_recruit().uid)) == OK, "pending recruitment is explicitly discarded")

func _run() -> void:
	_test_generation()
	_test_difficulty()
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
		var state: RogueRunState = _fresh("ranged", pack, 721, true)
		_check(state.population() == 18 and state.population_cap() == 20, pack + " begins with eighteen of twenty population")
		_check(state.data.gold == 20 and state.data.bread == 3 and state.data.ap == 12 and state.data.pending_recruits.size() == 1 and state.data.phase == "recruit_unit", "starting coupon is a mandatory pending choice")
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

func _test_difficulty() -> void:
	var state: RogueRunState = _fresh()
	_check(state.data.battle_difficulty == 1 and state.data.nodes.all(func(entry: Dictionary) -> bool: return int(entry.difficulty) == 1), "first-floor node and battle difficulties are explicitly one")
	for kind: String in ["battle", "emergency"]:
		var target: Dictionary = {}
		for entry: Dictionary in state.data.nodes:
			if entry.kind == kind:
				target = entry
				break
		state.data.phase = "map"
		state.data.current_node = state._neighbors(int(target.id))[0]
		state.data.battle_difficulty = 5
		_check(state.enter_node(int(target.id)) == OK and state.data.battle_difficulty == 1 and bool(state.data.emergency) == (kind == "emergency"), "entering " + kind + " uses node difficulty independently of emergency variant")
	state = _fresh()
	var clone := RogueRunState.new()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(state.export_checkpoint()))
	_check(clone.import_checkpoint(parsed) == OK and typeof(clone.data.battle_difficulty) == TYPE_INT and typeof(clone.data.nodes[0].difficulty) == TYPE_INT and clone.data.battle_difficulty == 1, "checkpoint preserves independent difficulty fields and restores integers")
	parsed.battle_difficulty = 5
	parsed.nodes[0].difficulty = 3
	_check(clone.import_checkpoint(parsed) == OK and clone.data.floor == 1 and clone.data.battle_difficulty == 5 and clone.data.nodes[0].difficulty == 3, "difficulty one through five is stored independently of floor and node kind")
	for invalid: int in [0, 6]:
		var bad: Dictionary = state.export_checkpoint()
		bad.battle_difficulty = invalid
		_check(clone.import_checkpoint(bad) != OK, "out-of-range battle difficulty rejected")
		bad = state.export_checkpoint()
		bad.nodes[0].difficulty = invalid
		_check(clone.import_checkpoint(bad) != OK, "out-of-range node difficulty rejected")
	var fractional: Dictionary = state.export_checkpoint()
	fractional.battle_difficulty = 1.5
	_check(clone.import_checkpoint(fractional) != OK, "fractional battle difficulty rejected")
	state.data.ap = 1
	var next: int = int(state._neighbors(int(state.data.current_node))[0])
	state.node(next).completed = true
	state.node(next).resolved = true
	state.enter_node(next)
	_check(state.data.battle_difficulty == 1 and state.launch_battle() == OK and state.data.battle_difficulty == 1, "pending siege and launched siege retain configured difficulty one")
	var risk_unchanged: bool = is_equal_approx(float(RogueCatalog.EVENTS.mist_chest.risk_chance), 0.5)
	for entry: Dictionary in state.data.nodes:
		if entry.kind == "event":
			var node_rng := RandomNumberGenerator.new()
			node_rng.seed = int(entry.content_seed)
			risk_unchanged = risk_unchanged and bool(entry.risk_success) == (node_rng.randf() < 0.5)
	_check(risk_unchanged, "configurable mist chance preserves the existing seed stream and fifty-percent default")

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
	var before_gold: int = state.data.gold
	_check(state.resolve_battle(true) == OK and state.data.phase == "settlement", "victory enters explicit settlement")
	_check(state.data.gold == before_gold and state.data.xp == 0 and state.data.pending_recruits.is_empty(), "settlement preview grants nothing")
	var preview: String = JSON.stringify(state.data)
	_check(state.resolve_battle(true) != OK and JSON.stringify(state.data) == preview, "result cannot create a second settlement")
	_check(state.confirm_settlement() == OK and state.data.phase == "recruit_unit", "claim immediately requires coupon processing")
	_check(state.data.gold == 40 and state.data.bread == 5 and state.data.xp == 50 and state.data.pending_recruits.size() == 1, "normal reward grants once")
	var after: String = JSON.stringify(state.data)
	_check(state.confirm_settlement() != OK and JSON.stringify(state.data) == after, "claim cannot replay while recruit is pending")
	_check(state.leave_node() != OK, "recruit cannot be skipped by node exit")
	_discard_all(state)
	_check(state.data.phase == "map" and state.data.settlement.is_empty(), "final choice completes node settlement")
	_stage(state, "battle", 1)
	state.resolve_battle(true)
	_check(state.data.settlement.levels == 1 and state.data.settlement.bonus_bread == 1 and state.data.settlement.bonus_population == 5, "settlement previews level rewards before claim")
	state.confirm_settlement()
	_check(state.data.level == 2 and state.data.xp == 0 and state.data.bread == 8 and state.population_cap() == 25 and state.xp_required() == 150, "level grants bread and population once")
	_discard_all(state)
	_stage(state, "emergency")
	state.resolve_battle(true)
	_check(state.confirm_settlement() == OK and state.data.phase == "recruit_unit" and state.data.pending_choices.size() == 3, "emergency recruitment precedes its fixed relic choice")
	_check(state.data.gold == 90 and state.data.bread == 11 and state.data.xp == 80, "emergency economy")
	var selected_uid: int = int(state.data.roster[0].uid)
	_check(state.set_deployed(selected_uid, false) == OK and state.set_deployed(selected_uid, true) == OK, "army edits preserve pending rewards")
	_discard_all(state)
	_check(state.data.phase == "reward", "emergency waits for relic after coupon")
	var chosen: String = state.data.pending_choices[0]
	_check(state.choose_relic(chosen) == OK and state.data.phase == "map" and int(state.data.relics[chosen]) == 1, "emergency final relic exits node")
	_check(state.choose_relic(chosen) != OK, "relic reward cannot replay")
	state = _fresh()
	_check(state._grant_xp(600) == 3 and state.data.level == 4 and state.data.xp == 150 and state.data.bread == 6, "one large experience grant supports multiple levels")

func _test_recruitment_and_formation() -> void:
	var state: RogueRunState = _fresh("ranged", "steady", 721, true)
	var initial: Dictionary = state.pending_recruit()
	_check(state.enter_node(state._neighbors(int(state.data.current_node))[0]) != OK and state.launch_battle() != OK, "initial coupon blocks exploration and battle")
	_check(state.recruit(int(initial.uid), initial.candidates[0], 1) != OK, "legacy recruit cannot skip first selection")
	for _index: int in 100: state._add_ticket()
	for ticket: Dictionary in state.data.pending_recruits:
		var unique: Dictionary = {}
		var cheap: bool = false
		for kind: String in ticket.candidates:
			unique[kind] = true
			cheap = cheap or int(RogueCatalog.RECRUIT[kind].bread) == 1
		_check(unique.size() == 3 and cheap, "each queued candidate is distinct and contains a low-price option")
	_check(state.discard_recruit(int(state.data.pending_recruits[1].uid)) != OK, "queued later coupon cannot be processed out of order")
	state.data.pending_recruits = [{"uid": 500, "candidates": ["swordsman", "heavy_cannon", "priest"]}]
	state.data.next_ticket_uid = 501
	var before: int = state.data.roster.size()
	_check(state.choose_recruit_unit(500, "heavy_cannon") == OK, "unit selection opens batch round")
	var fixed: String = JSON.stringify(state.data)
	_check(state.confirm_recruit_batches(500, 1) != OK and JSON.stringify(state.data) == fixed, "unaffordable batch cannot spend anything")
	_check(state.back_to_recruit_units() == OK and state.pending_recruit().candidates == ["swordsman", "heavy_cannon", "priest"], "back preserves all three candidates")
	state.choose_recruit_unit(500, "swordsman")
	_check(state.confirm_recruit_batches(500, 4) != OK and state.data.bread == 3 and state.data.roster.size() == before, "batch limit is atomic")
	_check(state.recruit(500, "priest", 1) != OK, "legacy recruit cannot replace selected kind")
	_check(state.confirm_recruit_batches(500, 3) == OK and state.data.bread == 0 and state.data.roster.size() == before + 9 and state.data.pending_recruits.is_empty(), "three batches consume one pending coupon atomically")
	_check(state.population() == 18 and state.data.phase == "map", "recruits remain in standby and completed initial choice unlocks map")
	_check(state.discard_recruit(500) != OK and state.confirm_recruit_batches(500, 3) != OK, "processed coupon cannot be reused")
	for kind: String in ["archer", "cannon"]:
		var batch_state: RogueRunState = _fresh("ranged", "steady", 721, true)
		batch_state.data.bread = 20
		batch_state.data.pending_recruits[0].candidates = ["archer", "cannon", "priest"]
		var coupon_uid: int = int(batch_state.pending_recruit().uid)
		var roster_size: int = batch_state.data.roster.size()
		batch_state.choose_recruit_unit(coupon_uid, kind)
		var unit_count: int = 9 if kind == "archer" else 3
		var bread_cost: int = 3 if kind == "archer" else 9
		_check(batch_state.confirm_recruit_batches(coupon_uid, 3) == OK and batch_state.data.roster.size() == roster_size + unit_count and batch_state.data.bread == 20 - bread_cost and batch_state.population() == 18, kind + " batches apply unit quantity and bread cost independently of population")
	state.data.roster.clear()
	for _index: int in 5: state._add_unit("heavy_cannon", false)
	var uids: Array = state.data.roster.map(func(unit: Dictionary): return int(unit.uid))
	_check(state.set_deployed_many(uids.slice(0, 4), true) == OK and state.population() == 20, "four heavy cannons deploy atomically with free positions in both maps")
	var before_failure: String = JSON.stringify(state.data)
	_check(state.set_deployed_many(uids, true) != OK and JSON.stringify(state.data) == before_failure, "fifth heavy cannon cannot partially change deployment")
	for _index: int in 100: state._add_unit("swordsman", false)
	_check(state.data.roster.size() == 105 and state.population() == 20, "standby roster has no population cap")
	var first_uid: int = uids[0]
	var second_uid: int = uids[1]
	var first_layout: Array = state._unit(first_uid).layouts.outpost.duplicate()
	var second_layout: Array = state._unit(second_uid).layouts.outpost.duplicate()
	_check(state.set_layout(first_uid, "siege", [0, 0, 0]) != OK, "central base cannot be occupied")
	_check(state.set_layout(first_uid, "outpost", [12, 0, 0]) != OK, "unit footprint must remain inside deployment area")
	_check(state.set_layout(first_uid, "outpost", second_layout) != OK, "single move rejects overlap")
	_check(state.set_layouts("outpost", [{"uid": first_uid, "layout": second_layout}, {"uid": second_uid, "layout": first_layout}]) == OK, "batch swaps use final positions instead of intermediate collisions")
	var group: Array = []
	for uid: int in [first_uid, second_uid]:
		var layout: Array = state._unit(uid).layouts.outpost.duplicate()
		layout[0] += 0.3
		group.append({"uid": uid, "layout": layout})
	_check(state.set_layouts("outpost", group) == OK, "group translation preserves relative spacing")
	before_failure = JSON.stringify(state.data)
	group[1].layout = [99, 0, 0]
	_check(state.set_layouts("outpost", group) != OK and JSON.stringify(state.data) == before_failure, "invalid group movement rolls back all members")
	_check(state.set_deployed_many([first_uid, first_uid], false) != OK, "duplicate group identifiers rejected")
	_check(state.checkpoint_error().is_empty(), "large standby roster and batch positions form a valid checkpoint")
	state = _fresh()
	state.data.level = 100
	state.data.roster.clear()
	for _index: int in 70: state._add_unit("heavy_cannon", false)
	uids = state.data.roster.map(func(unit: Dictionary): return int(unit.uid))
	before_failure = JSON.stringify(state.data)
	_check(state.set_deployed_many(uids, true) != OK and JSON.stringify(state.data) == before_failure, "lack of map space rolls back the entire two-map deployment")

func _test_nodes_and_siege() -> void:
	var state: RogueRunState = _fresh()
	var saved_start: Dictionary = state.export_checkpoint()
	var guard_event: Dictionary = {}
	for entry: Dictionary in state.data.nodes:
		if entry.kind == "event" and entry.event_id == "lost_guard": guard_event = entry
	state.data.current_node = guard_event.id
	state.data.active_node = guard_event.id
	state.data.phase = "node"
	_check(state.resolve_event(1) == OK and state.data.phase == "recruit_unit" and state.data.gold == 10, "event coupon immediately opens mandatory selection")
	var event_candidates: Dictionary = state.pending_recruit()
	_check(state.resolve_event(1) != OK and state.leave_node() != OK, "event coupon cannot be charged twice or postponed")
	var replay := RogueRunState.new()
	replay.import_checkpoint(saved_start)
	replay.data.current_node = guard_event.id
	replay.data.active_node = guard_event.id
	replay.data.phase = "node"
	replay.resolve_event(1)
	_check(replay.pending_recruit() == event_candidates, "returning to pre-node checkpoint reproduces the same event coupon")
	_discard_all(state)
	_check(state.data.phase == "node" and state.leave_node() == OK, "event coupon completes before ordinary node exit")
	state = _fresh()
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
	_check(state.resolve_battle(true) == OK and state.data.phase == "settlement" and state.confirm_settlement() == OK and state.data.phase == "intermission" and state.data.floor == 2 and state.data.ap == 12, "siege victory restores AP and reaches layer intermission")
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
	_check(session.save_checkpoint() == ERR_UNCONFIGURED, "unstarted run cannot save")
	session.state = _fresh("ranged", "steady", 721, true)
	_check(session.save_checkpoint() == OK, "initial forced candidates are checkpointed")
	var loaded: Dictionary = session._read_checkpoint(TEST_SAVE)
	_check(loaded.phase == "recruit_unit" and loaded.pending_recruits == session.state.data.pending_recruits, "reload restores compulsory fixed initial candidates")
	var ticket: Dictionary = session.state.pending_recruit()
	var cheap: String = ""
	for kind: String in ticket.candidates:
		if int(RogueCatalog.RECRUIT[kind].bread) == 1: cheap = kind
	_check(session.choose_recruit_unit(int(ticket.uid), cheap) == OK, "first selection persists safely outside a node")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.phase == "recruit_batch" and loaded.recruit_kind == cheap and loaded.pending_recruits[0].candidates == ticket.candidates, "reload restores exact second round without reroll")
	var emissions: Array = [0]
	var observer: Callable = func(): emissions[0] += 1
	session.changed.connect(observer)
	var before: String = JSON.stringify(session.state.data)
	var good_file: String = FileAccess.get_file_as_string(TEST_SAVE)
	session.save_path = TEST_SAVE + "/cannot_be_a_directory.json"
	_check(session.confirm_recruit_batches(int(ticket.uid), 1) != OK and JSON.stringify(session.state.data) == before and emissions[0] == 0, "failed recruitment save rolls back currency, roster and pending choice without changed")
	_check(FileAccess.get_file_as_string(TEST_SAVE) == good_file, "failed replacement retains checkpoint bytes")
	session.save_path = TEST_SAVE
	_check(session.confirm_recruit_batches(int(ticket.uid), 1) == OK and emissions[0] == 1, "retry successfully consumes once and publishes once")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.phase == "map" and loaded.pending_recruits.is_empty(), "processed initial coupon is absent after reload")
	before = JSON.stringify(session.state.data)
	_check(session.confirm_recruit_batches(int(ticket.uid), 1) != OK and JSON.stringify(session.state.data) == before and emissions[0] == 1, "repeat confirmation has no mutation or publication")
	var first: Dictionary = session.state.data.roster[0]
	var second: Dictionary = session.state.data.roster[1]
	var changes: Array = [{"uid": first.uid, "layout": second.layouts.outpost.duplicate()}, {"uid": second.uid, "layout": first.layouts.outpost.duplicate()}]
	session.save_path = TEST_SAVE + "/cannot_be_a_directory.json"
	_check(session.set_layouts("outpost", changes) != OK and JSON.stringify(session.state.data) == before and emissions[0] == 1, "failed batch save restores both positions and emits nothing")
	session.save_path = TEST_SAVE
	_check(session.set_layouts("outpost", changes) == OK and emissions[0] == 2, "successful batch publishes once and saves both positions")
	var saved_layout: Array = session._read_checkpoint(TEST_SAVE).roster[0].layouts.outpost
	var expected_layout: Array = changes[0].layout
	# JSON decimal roundtrips and wrapf can round the last bits of a heading.
	_check(Vector2(saved_layout[0], saved_layout[1]).is_equal_approx(Vector2(expected_layout[0], expected_layout[1])) and is_zero_approx(angle_difference(saved_layout[2], expected_layout[2])), "batch checkpoint contains final positions and heading")
	session.changed.disconnect(observer)
	# Convert an actual v1-shaped checkpoint without discarding its stock or RNG.
	var legacy_state: RogueRunState = _fresh("ranged", "steady", 721, true)
	legacy_state._add_ticket()
	legacy_state._add_ticket()
	var legacy: Dictionary = legacy_state.export_checkpoint()
	legacy.version = 1
	legacy.phase = "map"
	legacy.tickets = legacy.pending_recruits
	for key: String in ["pending_recruits", "recruit_kind", "recruit_return_phase", "settlement"]: legacy.erase(key)
	_write_envelope(legacy)
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.version == 2 and loaded.phase == "recruit_unit" and loaded.pending_recruits == legacy.tickets and loaded.rng_counter == legacy.rng_counter, "v1 coupons migrate in order with identical IDs, candidates and RNG")
	_check(JSON.parse_string(JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE)).snapshot).version == 1, "reading legacy checkpoint never deletes or rewrites the old file")
	var clone := RogueRunState.new()
	_check(clone.import_checkpoint(loaded) == OK, "migrated checkpoint validates")
	var next_ticket: Dictionary = clone.data.pending_recruits[1].duplicate(true)
	clone.discard_recruit(int(clone.pending_recruit().uid))
	_check(clone.pending_recruit() == next_ticket and clone.data.phase == "recruit_unit", "old coupon stock is sequential mandatory work")
	var bypass: Dictionary = loaded.duplicate(true)
	bypass.phase = "map"
	_check(clone.import_checkpoint(bypass) != OK, "checkpoint cannot hide queued coupons behind map phase")
	# Node-internal recruitment remains transient until the whole node exits.
	session.state = _fresh()
	session.save_checkpoint()
	good_file = FileAccess.get_file_as_string(TEST_SAVE)
	_stage(session.state, "shop")
	_check(session.purchase(3) == OK and session.state.data.phase == "recruit_unit", "buying a coupon immediately blocks the shop")
	_check(session.purchase(4) != OK and session.leave_node() != OK, "forced shop recruit blocks further purchases and exit")
	_check(session.save_checkpoint() == ERR_BUSY and FileAccess.get_file_as_string(TEST_SAVE) == good_file, "node-internal recruit cannot overwrite safe checkpoint")
	session.discard_recruit(int(session.state.pending_recruit().uid))
	_check(session.state.data.phase == "node" and session.leave_node() == OK, "discard returns to shop result and explicit exit commits")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.gold == 8 and loaded.pending_recruits.is_empty(), "shop exit retains payment without a storable coupon")
	# Last AP is held through settlement, recruitment and the emergency relic.
	good_file = FileAccess.get_file_as_string(TEST_SAVE)
	_stage(session.state, "emergency")
	session.state.data.ap = 0
	session.state.resolve_battle(true)
	_check(session.save_checkpoint() == ERR_BUSY and FileAccess.get_file_as_string(TEST_SAVE) == good_file, "victory preview does not save a half-node")
	_check(session.confirm_settlement() == OK and session.state.data.phase == "recruit_unit" and not session.state.data.pending_siege, "AP-zero claim waits for recruitment before siege")
	_check(FileAccess.get_file_as_string(TEST_SAVE) == good_file, "awarded but incomplete settlement remains transient")
	session.discard_recruit(int(session.state.pending_recruit().uid))
	_check(session.state.data.phase == "reward" and not session.state.data.pending_siege, "last AP still waits for emergency relic")
	_check(session.choose_relic(session.state.data.pending_choices[0]) == OK and session.state.data.phase == "siege_briefing", "last mandatory choice atomically exits and schedules siege")
	loaded = session._read_checkpoint(TEST_SAVE)
	_check(loaded.phase == "siege_briefing" and loaded.pending_siege and loaded.pending_recruits.is_empty() and loaded.settlement.is_empty(), "reload cannot bypass siege or reclaim rewards")
	for mutation: String in ["version", "kind", "edge", "layout"]:
		var bad: Dictionary = loaded.duplicate(true)
		match mutation:
			"version": bad.version = 999
			"kind": bad.roster[0].kind = "res://malicious.gd"
			"edge": bad.edges[0][1] = 33
			"layout": bad.roster[0].layouts.siege = [0,0,0]
		_check(clone.import_checkpoint(bad) != OK, "tampered checkpoint rejected: " + mutation)
	good_file = FileAccess.get_file_as_string(TEST_SAVE)
	var corrupt := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	corrupt.store_string(good_file.replace("sha256", "broken_digest"))
	corrupt.close()
	_check(session._read_checkpoint(TEST_SAVE).is_empty(), "corrupt checkpoint fails explicitly")
	_check(session.save_checkpoint() == OK and not FileAccess.file_exists(TEST_SAVE + ".tmp"), "atomic replacement recovers without leftover temporary files")
	session.state.data.phase = "game_over"
	good_file = FileAccess.get_file_as_string(TEST_SAVE)
	_check(session.save_checkpoint() == ERR_BUSY and FileAccess.get_file_as_string(TEST_SAVE) == good_file, "defeat preserves latest checkpoint")
	session.save_path = RogueSession.SAVE_PATH

func _write_envelope(snapshot: Dictionary) -> void:
	var payload: String = JSON.stringify(snapshot)
	var file := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	file.store_string(JSON.stringify({"format": 1, "snapshot": payload, "sha256": payload.sha256_text()}))
	file.close()

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
