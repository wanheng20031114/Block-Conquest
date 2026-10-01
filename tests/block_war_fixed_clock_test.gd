extends "res://tests/block_war_replication_test.gd"
## Exercise the real Host accumulator with the same input timeline and five AIs.
## Native receive-time/RTT and GPU frames are deliberately outside this rule test.
const DURATION := 20
const TOTAL_TICKS := DURATION * 30

class ScheduledAuthority extends "res://scripts/network/war_network_match.gd":
	var checkpoints: Dictionary = {}
	var command_sequence := 0
	var peak_host_morale := 0.0
	var saw_host_construction := false
	var saw_host_completion := false
	var scheduled := {
		1: {"type": "upgrade", "building": 5},
		2: {"type": "skill_building", "skill": 0, "target": 5},
		61: {"type": "dispatch", "source": 5, "target": 11, "percent": 50},
		450: {"type": "dispatch", "source": 5, "target": 17, "percent": 50},
		570: {"type": "dispatch", "source": 2, "target": 11, "percent": 50},
	}
	func _drain_commands() -> void:
		# Accepted input is tied to an authoritative tick, never a render frame.
		# Use the production receive/validation/queue path before its real drain.
		if scheduled.has(_tick):
			command_sequence += 1
			_receive_command(105, {"seq": command_sequence, "epoch": 1, "command": scheduled[_tick]})
		super._drain_commands()
	func _publish_step(delta: float) -> void:
		super._publish_step(delta)
		# Coverage is historical: the paid upgrade's morale can legitimately
		# decay back to zero before this twenty-second run ends.
		peak_host_morale = maxf(peak_host_morale, game.morale.points(5))
		saw_host_construction = saw_host_construction or game.by_id[5].is_constructing
		saw_host_completion = saw_host_completion or game.by_id[5].level > 1
		if _tick % 30 == 0:
			checkpoints[_tick] = rule_digest()
	func rule_digest() -> String:
		var state := codec.capture(game, _tick)
		# Decision clocks are not part of a client snapshot, but must also agree
		# before the next AI turn; otherwise equal visible states can later split.
		state["ai_clock"] = game.ai_clock
		state["ai"] = {}
		for faction: int in game._bot_factions:
			var brain: RefCounted = game._ai_by_faction[faction]
			var economy: RefCounted = brain._economy
			var spending: Array = []
			for payment: Vector2 in economy._recent_spending:
				spending.append([payment.x, payment.y])
			state.ai[str(faction)] = {"next_attack": brain._next_attack_at,
				"next_expansion": brain._next_expansion_at, "next_skill": brain._skills.next_decision,
				"economy": [economy._observed_since, economy._last_observed_at,
					economy._last_energy_low, economy._low_energy_seconds, spending]}
		return Snapshot.digest(state)

func configuration() -> Dictionary:
	var value := super.configuration()
	value.match_id = "fixed-clock-test"
	for faction: int in 6:
		var slot: Dictionary = value.slots[faction]
		slot.kind = "human" if faction == 5 else "bot"
		slot.controller = slot.kind
		slot.player_id = 105 if faction == 5 else -1
		slot.commander = ["squirrel", "rabbit", "frog", "bear", "rabbit", "bear"][faction]
	return value

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	var baseline: Dictionary = await run_case("30fps", 30)
	for scenario: Array in [["10fps", 10], ["120fps", 120], ["long_frame", 30], ["local_menu", 30], ["disconnect", 30]]:
		var result: Dictionary = await run_case(scenario[0], scenario[1])
		check(result.final == baseline.final, str(scenario[0]) + " final complete rule state and AI clocks equal 30fps")
		check(result.commands == baseline.commands, str(scenario[0]) + " command decisions occur on identical authoritative ticks")
		for tick: int in baseline.checkpoints:
			check(result.checkpoints.get(tick) == baseline.checkpoints[tick], "%s canonical checkpoint at tick %d" % [scenario[0], tick])
	print("FIXED_CLOCK checks=", checks, " failures=", failures.size(), " factions=6 bots=5 target_tick=", TOTAL_TICKS, " frame_rates=[10,30,120]")
	quit(0 if failures.is_empty() else 1)

func run_case(label: String, fps: int) -> Dictionary:
	seed(740219)
	host = make_game(105)
	# This timing fixture completes a paid upgrade on tick two; fund that cast
	# explicitly instead of depending on a commander's opening energy balance.
	host.faction_skills[5].energy = host.SKILL_RULES.BEAR_COSTS[0]
	host.ai_enabled = true
	host_wire = make_wire(105)
	var clock := ScheduledAuthority.new()
	clock.setup(host, host_wire)
	check(host._bot_factions == [0, 1, 2, 3, 4], label + " drives all five non-host seats with independent commander AIs")
	var elapsed_frames := 0
	if label == "long_frame":
		clock.process(2.0)
		check(clock._tick == 8 and absf(clock._accumulator - (2.0 - 8.0 * Coordinator.STEP)) < 0.000001, "long frame obeys eight-step cap and retains every unprocessed second")
		var drain_frames := 0
		while clock._accumulator + 0.0000001 >= Coordinator.STEP and drain_frames < 20:
			var before: int = clock._tick
			clock.process(0.0)
			check(clock._tick - before > 0 and clock._tick - before <= 8, "zero-delta drain consumes only existing bounded backlog")
			drain_frames += 1
		check(clock._tick == 60 and absf(clock._accumulator) < 0.000001, "long frame eventually accounts for exactly sixty ticks without dropping time")
		elapsed_frames = 2 * fps
	for frame: int in range(elapsed_frames, DURATION * fps):
		if label == "local_menu" and frame == 7 * fps:
			host.set_paused(true)
			check(host._local_menu and not host.is_rule_paused(), "Host local menu is not a rule pause")
		if label == "local_menu" and frame == 14 * fps:
			check(clock._tick == 420 and not host.simulation_paused, "AI and authoritative ticks continue for seven seconds behind Host menu")
			host.set_paused(false)
		var frame_delta := 1.0 / float(fps)
		if label == "disconnect" and frame == 4 * fps:
			frame_delta -= check_disconnection(clock)
		clock.process(frame_delta)
		if label == "disconnect" and frame == 4 * fps:
			check(clock._tick == 121 and absf(clock._accumulator) < 0.000001, "first resumed half-frame completes precisely the saved fractional tick")
		# Transport storage and wall-clock chunk pacing are irrelevant to the
		# Host's rule clock; still run the real serialization path on every send.
		host_wire.sent.clear()
	check(clock._tick == TOTAL_TICKS, label + " reaches precisely 600 authoritative ticks")
	check(absf(host.elapsed - float(DURATION)) < 0.000001, label + " simulates exactly twenty seconds")
	check(absf(clock._accumulator) < 0.000001, label + " retains no whole or fractional tick after exact frame total")
	check(not host.finished and clock.checkpoints.size() == DURATION, label + " completes all twenty active-battle checkpoints")
	check(clock._command_results.size() == 5, label + " applies every scripted command exactly once")
	var accepted := 0
	for result: Dictionary in clock._command_results.values(): accepted += int(result.accepted)
	check(accepted == 4, label + " accepts four legal actions and rejects foreign-seat dispatch")
	check(host_wire.invalid_packets == 0, label + " emits valid wire messages throughout AI play")
	check(host.marches._next_order_id > 4 and clock.peak_host_morale > 0.0 and clock.saw_host_construction and clock.saw_host_completion,
		label + " actually exercises AI marches, paid construction, completion and morale during the run")
	var economy: RefCounted = host._ai_by_faction[0]._economy
	check(economy._last_observed_at > economy._observed_since and economy._observed_since >= 0.0,
		label + " samples evolving AI energy demand history")
	var before_history := clock.rule_digest()
	var low_energy_seconds: float = economy._low_energy_seconds
	economy._low_energy_seconds += 0.5
	check(clock.rule_digest() != before_history, label + " digest detects a future investment decision changing without visible state changes")
	economy._low_energy_seconds = low_energy_seconds
	var result := {"final": clock.rule_digest(), "commands": Codec.digest(clock._command_results), "checkpoints": clock.checkpoints.duplicate()}
	print("FIXED_CLOCK_CASE mode=", label, " tick=", clock._tick, " simulation_seconds=", host.elapsed, " commands=", clock._command_results.size(), " orders=", host.marches._next_order_id - 1, " peak_morale=", clock.peak_host_morale, " final_morale=", host.morale.points(5), " digest=", result.final)
	await host.prepare_shutdown()
	host.free()
	host_wire.free()
	return result

func check_disconnection(clock: ScheduledAuthority) -> float:
	# Begin a partial frame, then simulate actual Online state/room signals.
	# A disconnected wall-clock interval must neither grow nor consume it.
	clock.process(Coordinator.STEP * 0.5)
	var tick: int = clock._tick
	var elapsed: float = host.elapsed
	var debt: float = clock._accumulator
	var before: String = clock.rule_digest()
	for state: String in ["connecting", "reconnecting", "disconnected"]:
		host_wire.connection_state = state
		host_wire.state_changed.emit(state)
		clock.process(5.0)
		check(clock._tick == tick and host.elapsed == elapsed and clock._accumulator == debt and clock.rule_digest() == before, state + " pauses all rules and preserves only pre-disconnection fraction")
	host_wire.connection_state = "match"
	host_wire.room.phase = "host_lost"
	host_wire.room_changed.emit(host_wire.room)
	clock.process(5.0)
	check(clock._tick == tick and clock._accumulator == debt and clock.rule_digest() == before, "relay host_lost phase pauses simulation even with transport connected")
	host_wire.room.phase = "match"
	host_wire.room_changed.emit(host_wire.room)
	host_wire.state_changed.emit("match")
	# The remainder of the current render frame is supplied by the caller.
	# No negative delta or direct accumulator mutation is used in this fixture.
	clock.process(0.0)
	check(clock._tick == tick and clock._accumulator == debt, "resume never catches up twenty seconds of network outage")
	return Coordinator.STEP * 0.5
