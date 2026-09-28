extends "res://tests/block_war_replication_test.gd"
## Control facts cross the same ordered stream as units, independent of clock ticks.

func configuration() -> Dictionary:
	var value := super.configuration()
	value.match_id = "match-control-replication"
	for slot: Dictionary in value.slots:
		var human: bool = int(slot.faction_id) in [0, 2, 3, 5]
		slot.kind = "human" if human else "bot"
		slot.controller = slot.kind
		slot.player_id = 100 + int(slot.faction_id) if human else -1
	return value

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105); replica = make_game(102)
	host_wire = make_wire(105); client_wire = make_wire(102)
	authority = Coordinator.new(); client = Coordinator.new()
	authority.setup(host, host_wire); client.setup(replica, client_wire)
	host.network_match = authority; replica.network_match = client
	flush()
	client.process(0.0)
	_pause_reanchor_rules()
	host.by_id[2].population = 90.0
	host.by_id[0].kind = 3
	host.by_id[0].population = 60.0
	authority._publish_step(0.0); flush()
	check(client.submit({"type":"dispatch", "source":2, "target":8, "percent":100}).accepted, "remote dispatch enters authority stream")
	deliver(client_wire, authority); boundary(); flush()
	check(host.by_id[2].queued_population > 0, "pause fixture includes reserved soldiers")
	check(client.submit({"type":"pause", "paused":true}).accepted, "remote participant can request pause")
	deliver(client_wire, authority); boundary(); flush()
	check(host.match_paused and replica.match_paused, "pause is a reliable replicated fact")
	check(host.pause_faction == 2 and replica.pause_faction == 2, "pause initiator is shared")
	check(is_equal_approx(host.elapsed, replica.elapsed), "pause corrects both clocks to exact authority boundary")
	_forfeit_during_host_outage()
	var paused: Dictionary = authority.codec.capture(host, authority._tick)
	var resyncs: int = client.resync_count
	for i: int in 24: boundary(0.25)
	flush()
	check(Codec.digest(authority.codec.capture(host, authority._tick)) == Codec.digest(paused), "six paused seconds change no rule clock population energy or queue")
	check(client.resync_count == resyncs, "paused authority heartbeat prevents false silence recovery")
	check(is_equal_approx(host.elapsed, replica.elapsed), "paused client does not extrapolate")
	check(not host.execute_network_command(2, {"type":"upgrade", "building":2}).accepted, "battle orders cannot execute during pause")
	# Recover to the paused world, then let the opposite side resume from its menu.
	authority._snapshot_sent_at.clear(); authority._send_snapshot(102); flush()
	check(replica.match_paused and not client._recovery_waiting, "full reconnect baseline preserves manual pause")
	host.set_paused(true)
	check(host.submit_player_command({"type":"pause", "paused":false}).accepted, "local menu permits global resume request")
	boundary(); flush()
	check(not host.match_paused and not replica.match_paused, "other team can resume the same global pause")
	check(is_equal_approx(host.elapsed, float(paused.time)), "resume frame accrues no paused time debt")
	boundary(); flush()
	check(host.elapsed - float(paused.time) < 0.04, "next frame advances exactly one ordinary step")
	host.set_paused(false)
	# Only the current generation's snapshot ACK may restore control.
	var original_epoch: int = host_wire.room.slots[2].control_epoch
	authority._recovery_baselines[102] = {"seq":authority._seq, "epoch":original_epoch}
	host_wire.room.slots[2].control_epoch = original_epoch + 1
	host_wire.room.slots[2].controller = "reconnecting"
	var recovered_before := host_wire.recovered.size()
	authority._on_message(102, "ack", {"op":"recovered", "seq":authority._seq, "epoch":original_epoch})
	check(host_wire.recovered.size() == recovered_before, "late previous-generation ACK cannot return new connection control")
	client_wire.room.slots[2].control_epoch = original_epoch + 1
	client_wire.room.slots[2].controller = "reconnecting"
	authority._snapshot_sent_at.clear(); authority._send_snapshot(102); flush()
	check(host_wire.recovered.size() == recovered_before + 1, "matching recovery epoch is accepted")
	host_wire.room.slots[2].controller = "human"; client_wire.room.slots[2].controller = "human"
	# Keep the test synchronous: fake wire records room confirmations separately.
	check(authority.submit({"type":"pause", "paused":true}).accepted, "Host pauses before surrender")
	boundary(); flush()
	var source: WarBuilding = host.by_id[5]
	var garrison: float = source.population
	check(authority.submit({"type":"surrender"}).accepted, "Host may surrender while globally paused")
	boundary(); flush()
	check(host.has_surrendered(5) and replica.has_surrendered(5), "Host surrender survives public snapshot and delta")
	check(source.faction == 3 and is_equal_approx(source.population, garrison * 0.6), "Host assets transfer once to only eligible human teammate")
	check(host_wire.surrender_confirmations.count(105) == 1, "authority announces surrendered controller to Relay once")
	check(not authority.submit({"type":"pause", "paused":false}).accepted, "spectator Host cannot resume via transport coordinator")
	check(not host.execute_network_command(5, {"type":"dispatch", "source":5, "target":11, "percent":100}).accepted, "spectator cannot command former assets")
	check(client.submit({"type":"pause", "paused":false}).accepted, "still active opponent may unpause surrendered Host")
	deliver(client_wire, authority); boundary(); flush()
	var resumed: float = host.elapsed
	boundary(); flush()
	check(host.elapsed > resumed and host.is_authority(), "spectator Host continues authoritative simulation")
	authority._snapshot_sent_at.clear(); authority._send_snapshot(102); flush()
	check(replica.has_surrendered(5), "recovery never revives surrendered faction")
	var invalid: Dictionary = client._mirror.duplicate(true)
	invalid.match_control.surrendered = [1]
	check(not Codec.valid(invalid, replica), "bot cannot appear in surrendered humans")
	invalid.match_control.surrendered = [5, 5]
	check(not Codec.valid(invalid, replica), "duplicate surrender identities are rejected")
	invalid.match_control = {"paused":true, "by":false, "surrendered":[]}
	check(not Codec.valid(invalid, replica), "boolean pause actor is not coerced into a faction")
	# The last human actively leaving uses the same authority transaction as surrender.
	_mark_forfeit(3)
	boundary(); flush(); client._maybe_finish()
	if not (host.finished and replica.finished):
		print("FINAL_CONTROL_STATE ", {"host_finished":host.finished,"client_finished":replica.finished,"surrendered":host.surrendered_factions,"commands":authority._commands.size(),"host_seq":authority._seq,"client_seq":client._applied,"pending":client._pending.keys(),"outbox":authority._outbox.size(),"host_pause":host.match_paused,"finish_pending":client._finish_pending,"loading":client._snapshot_loading,"patch_valid":client._valid_patch(client._pending[authority._seq]),"host_valid":Codec.valid(authority._published,replica),"host_control":authority._published.match_control,"client_humans":replica.initial_human_factions})
	check(host.finished and replica.finished and host.winner_team == 0 and replica.winner_team == 0, "all human teammates surrendered ends both peers despite living computer assets")
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "final surrender transaction and result share one canonical digest")
	check(host_wire.surrender_confirmations.count(103) == 1, "last human departure is confirmed even after its transaction ends the match")
	# Another leave may already be in Relay's queue before it sees the result.
	_mark_forfeit(2)
	check(host_wire.surrender_confirmations.count(102) == 1 and host.winner_team == 0, "finished authority retires remaining departure identities without changing winner")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "all control recovery and result traffic satisfies channel contracts")
	print("MATCH_CONTROL_REPLICATION checks=", checks, " failures=", failures.size(), " resyncs=", client.resync_reasons)
	await host.prepare_shutdown(); await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()
	quit(0 if failures.is_empty() else 1)

func _mark_forfeit(faction: int) -> void:
	for wire: FakeOnline in [host_wire, client_wire]:
		wire.room.slots[faction].forfeit_requested = true
		wire.room.slots[faction].connected = false
		wire.room.slots[faction].controller = "spectator"
		wire.room.slots[faction].control_epoch += 1
	authority._on_room(host_wire.room)
	client._on_room(client_wire.room)

func _forfeit_during_host_outage() -> void:
	var old_account: Array = client._account.duplicate(true)
	var tick: int = authority._tick
	var old_base: int = client._applied
	host_wire.connection_state = "reconnecting"
	authority._on_connection("reconnecting")
	_mark_forfeit(0)
	authority.process(0.25)
	check(not host.has_surrendered(0) and authority._forfeit_factions.has(0), "leave waits reliably while Host transport is unavailable")
	host_wire.connection_state = "match"
	authority._on_connection("match")
	boundary(0.0); flush()
	check(host.has_surrendered(0) and replica.has_surrendered(0) and not host.finished, "Host recovery resolves authenticated leave while manual pause remains")
	check(host.by_id[0].faction == 2 and is_equal_approx(host.by_id[0].population, 36.0), "disconnected quitter transfers energy tower with exactly forty percent garrison loss")
	check(authority._tick == tick and float(client._account[9]) == host.energy_regen_for(2) and float(client._account[9]) > float(old_account[9]), "same paused tick accepts newer private energy income by event base")
	# A stale same-tick account must not replace the newer private income.
	var latest_account: Array = client._account
	var latest_base: int = client._account_base
	client._on_message(105, "events", {"faction":2, "account":old_account, "tick":tick, "base":old_base})
	check(client._account == latest_account and client._account_base == latest_base, "old same-tick account cannot overwrite transferred energy income")
	# Repeat room notifications and the pending departure are both idempotent.
	authority._on_room(host_wire.room)
	boundary(0.0); flush()
	check(is_equal_approx(host.by_id[0].population, 36.0) and host_wire.surrender_confirmations.count(100) == 1, "repeated leave notification cannot transfer or penalize assets twice")
	host_wire.room.slots[0].surrendered = true
	client_wire.room.slots[0].surrendered = true

func _pause_reanchor_rules() -> void:
	# No authority time passes between the movement fact and the pause fact.
	# A client's same-row cache must still rewind its already predicted unit.
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	host.marches.send(2, 1, 2, 1, route)
	var soldier: WarMarches.MarchUnit = host.marches._units[0]
	soldier.rush_remaining = 4.0
	authority._publish_step(0.0); flush()
	client.codec.present(replica, client._view, 0.2)
	var predicted: WarMarches.MarchUnit = replica.marches._units[0]
	check(predicted.distance > soldier.distance and predicted.rush_remaining < soldier.rush_remaining, "pause fixture has already extrapolated movement and rush time")
	var tick: int = authority._tick
	host.set_match_paused(true, 2)
	authority._publish_step(0.0); flush()
	check(authority._tick == tick and is_equal_approx(replica.elapsed, host.elapsed), "same-tick pause restores the exact authority clock")
	check(is_equal_approx(predicted.distance, soldier.distance) and predicted.position.is_equal_approx(soldier.position), "same-row pause rewinds predicted unit distance and pose")
	check(is_equal_approx(predicted.rush_remaining, soldier.rush_remaining) and predicted.presentation_offset == Vector3.ZERO, "same-row pause restores buff time and removes correction drift")
	host.set_match_paused(false, 2)
	host.marches.clear()
	authority._publish_step(0.0); flush()
