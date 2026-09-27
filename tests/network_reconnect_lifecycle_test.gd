extends SceneTree
## Real Game/RelayClient lifecycle, with separate authority and human counters.
## Socket delivery order is injected explicitly to cover independent ENet channels.

const MATCH_ID := "00000000000000000000000000000000"
var checks: int = 0
var failures: Array[String] = []
var game: Node3D
var relay: RelayClient
var config: Dictionary
var resumed_states: Array[Dictionary] = []

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	var session: Node = root.get_node("Session")
	relay = session.relay
	relay.owner_id = 0
	relay.is_host = true
	relay.connection_state = "match"
	relay.room = {"slots": [{"kind": "human"}, {"kind": "human"}]}
	config = {"mode": "1v1", "map_id": "duel", "match_id": MATCH_ID, "players": [
		{"owner_id": 0, "team_id": 0, "controller": "human", "name": "Host"},
		{"owner_id": 1, "team_id": 1, "controller": "human", "name": "Guest"}]}
	relay._match = config.duplicate(true)
	session.start_online(config)
	await scene_changed
	game = current_scene
	while not game._match_ready:
		await process_frame
	while session.transition.busy:
		await process_frame
	game.tests_running = true
	game.set_physics_process(false)
	game.get_node("IncomeTimer").stop()
	game.get_node("EnemyTimer").stop()
	for unit: BattleUnit in get_nodes_in_group("units"):
		unit.stop()
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	for building: BattleBuilding in get_nodes_in_group("buildings"):
		building.set_physics_process(false)
		building.production.set_physics_process(false)
	relay.connection_state_changed.connect(_record_resumed_state)
	_sequences()
	_roster()
	_event_order()
	await game.prepare_shutdown()
	relay.disconnect_relay()
	current_scene = null
	game.queue_free()
	await process_frame
	await process_frame
	print("NETWORK_RECONNECT_LIFECYCLE_RESULTS " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _sequences() -> void:
	var guest_bus := MatchCommands.new(game)
	var guest_unit: BattleUnit = game.owned_entities(1, "units")[0]
	var host_unit: BattleUnit = game.owned_entities(0, "units")[0]
	var first := {"kind": "hold", "seq": guest_bus.next_sequence(1), "units": [guest_unit.entity_id]}
	_deliver_command(first)
	check(game.command_bus.pending.size() == 1, "first_human_command_accepted")
	game.command_bus.tick()
	check(guest_unit.order == BattleUnit.Order.HOLD, "first_human_command_executes")
	_deliver_event("bot_takeover", 1)
	var takeover_bot: SkirmishBot = game.bots[1]
	for index in range(5):
		check(takeover_bot._submit({"kind": "hold", "units": [guest_unit.entity_id]}), "takeover_bot_command_%d" % index)
	game.command_bus.tick()
	check(game.command_bus._accepted[1] == 1 and game.command_bus._bot_accepted[1] == 5, "bot_keeps_independent_accepted_sequence")
	_deliver_command(first)
	check(game.command_bus.pending.is_empty(), "old_human_duplicate_rejected_during_takeover")
	_deliver_event("player_reconnected", 1)
	check(game.get_player(1).controller == "human" and not game.bots.has(1), "reconnect_removes_bot")
	var resumed := {"kind": "stop", "seq": guest_bus.next_sequence(1), "units": [guest_unit.entity_id]}
	check(resumed.seq == 2, "guest_counter_remains_independent")
	_deliver_command(resumed)
	check(game.command_bus.pending.size() == 1, "first_resumed_command_immediately_accepted")
	game.command_bus.tick()
	check(guest_unit.order == BattleUnit.Order.IDLE, "first_resumed_command_executes")
	_deliver_command(first)
	_deliver_command(resumed)
	var forged := first.duplicate(true)
	forged["from_bot"] = true
	forged["owner"] = 0
	_deliver_command(forged)
	check(game.command_bus.pending.is_empty(), "old_or_forged_bot_stream_replays_remain_rejected")
	check(not takeover_bot._submit({"kind": "hold"}), "retired_bot_cannot_issue_after_control_returned")
	_deliver_event("bot_takeover", 1)
	check(game.bots[1]._submit({"kind": "hold"}), "second_takeover_can_continue_bot_stream")
	check(not game.command_bus.submit({"kind": "hold", "seq": 5}, 1, true).ok, "bot_stream_keeps_own_duplicate_protection")
	game.command_bus.tick()
	# A new command on the control channel can precede player_reconnected on
	# the event channel. It still belongs to the human stream bound by the relay.
	var early := {"kind": "hold", "seq": guest_bus.next_sequence(1), "units": [guest_unit.entity_id]}
	_deliver_command(early)
	check(game.command_bus.pending.size() == 1, "resumed_command_can_precede_controller_event")
	_deliver_event("player_reconnected", 1)
	game.command_bus.tick()
	check(guest_unit.order == BattleUnit.Order.HOLD, "early_resumed_command_executes")
	guest_bus.next_sequence(1)
	var next := {"kind": "stop", "seq": guest_bus.next_sequence(1), "units": [guest_unit.entity_id]}
	_deliver_command(next)
	check(game.command_bus.pending.size() == 1, "lost_unsent_human_command_does_not_require_sequence_reset")
	game.command_bus.tick()
	var foreign := {"kind": "hold", "seq": guest_bus.next_sequence(1), "units": [host_unit.entity_id], "from_bot": true, "owner": 0}
	_deliver_command(foreign)
	game.command_bus.tick()
	check(host_unit.order == BattleUnit.Order.IDLE, "payload_origin_cannot_take_foreign_unit")
	check(not game.command_bus.submit({"kind": "hold", "seq": 20000}, 1).ok, "human_sequence_jump_remains_bounded")
	check(not game.command_bus.submit({"kind": "hold", "seq": 1}, -1, true).ok, "invalid_bot_owner_rejected")

func _roster() -> void:
	var accepted: int = game.command_bus._accepted[1]
	_resume("bot")
	check(game.get_player(1).controller == "bot" and game.bots.has(1), "host_recovers_missed_bot_takeover")
	check(resumed_states.back() == {"controller": "bot", "bot": true}, "bot_roster_applied_before_match_state_signal")
	var previous_bot: SkirmishBot = game.bots[1]
	_resume("bot")
	check(game.bots[1] == previous_bot, "unchanged_roster_preserves_existing_bot_state")
	_resume("human")
	check(game.get_player(1).controller == "human" and not game.bots.has(1), "host_recovers_missed_player_return")
	check(resumed_states.back() == {"controller": "human", "bot": false}, "human_roster_applied_before_match_state_signal")
	check(current_scene == game and game.command_bus._accepted[1] == accepted, "resume_preserves_scene_and_duplicate_history")
	check(not paused, "host_resumes_only_after_roster_restored")
	game.get_player(1).eliminated = true
	_resume("bot")
	check(not game.bots.has(1), "eliminated_owner_gets_no_bot")
	game.get_player(1).eliminated = false
	_resume("human")

func _event_order() -> void:
	relay._set_state("reconnecting")
	_deliver_event("host_resumed", 0)
	check(paused and relay.connection_state == "reconnecting", "early_host_resumed_cannot_unpause_stale_roster")
	_deliver_start("bot")
	check(not paused and game.bots.has(1), "early_host_resumed_runs_after_roster")
	relay._set_state("reconnecting")
	relay._receive({"op": "joined", "token": "test-only", "owner": 0, "host": true, "command_sequence": 0})
	_deliver_event("player_reconnected", 1)
	_deliver_start("bot")
	check(game.get_player(1).controller == "human" and not game.bots.has(1), "newer_reconnect_event_wins_over_earlier_start_roster")
	relay._set_state("reconnecting")
	_deliver_event("bot_takeover", 1)
	_deliver_start("human")
	check(game.bots.has(1), "newer_takeover_event_wins_over_earlier_start_roster")
	relay._set_state("reconnecting")
	for index in range(100):
		_deliver_event("bot_takeover" if index % 2 == 0 else "player_reconnected", 1)
		_deliver_event("host_resumed" if index % 2 == 0 else "host_paused", 0)
	check(relay._pending_resume_events.size() == 2, "early_events_coalesce_to_bounded_latest_states")
	_deliver_start("bot")
	check(not game.bots.has(1) and paused and relay.connection_state == "host_paused", "latest_control_and_pause_survive_start")
	check(relay._pending_resume_events.is_empty(), "resume_consumes_buffer")
	_deliver_event("host_resumed", 0)
	relay._set_state("reconnecting")
	_deliver_event("bot_takeover", 1)
	relay._lost(Time.get_ticks_msec())
	relay._retry_at = 0
	check(relay._pending_resume_events.is_empty(), "new_disconnect_discards_previous_connection_events")
	_deliver_start("human")
	check(not game.bots.has(1) and not paused, "discarded_old_takeover_cannot_override_new_connection_roster")

func _resume(controller: String) -> void:
	relay._set_state("reconnecting")
	_deliver_start(controller)

func _deliver_start(controller: String) -> void:
	var resumed := config.duplicate(true)
	resumed.players[1].controller = controller
	relay._receive(NetworkProtocol.decode(NetworkProtocol.encode({"op": "start", "config": resumed})))

func _deliver_event(kind: String, owner: int) -> void:
	relay._receive({"op": "event", "match": MATCH_ID, "payload": {"kind": kind, "owner": owner}})

func _deliver_command(command: Dictionary) -> void:
	relay._receive(NetworkProtocol.decode(NetworkProtocol.encode({"op": "command", "match": MATCH_ID, "owner": 1, "payload": command})))

func _record_resumed_state(state: String) -> void:
	if state == "match":
		resumed_states.append({"controller": game.get_player(1).controller, "bot": game.bots.has(1)})

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
