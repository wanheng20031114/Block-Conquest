extends RefCounted
## Transport-independent Host authority and a read-only client rule mirror.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
const STEP := 1.0 / 30.0
const ANCHOR_INTERVAL := 0.5
const CHUNK_BYTES := 720
const MAX_BLOB_BYTES := 8 * 1024 * 1024
const MAX_PENDING_EVENTS := 2048
const MAX_PENDING_ANCHOR_ROWS := Snapshot.MAX_RECORDS
const BULK_BYTES_PER_SECOND := 131072.0
const MAX_OUTBOX_BYTES := 48 * 1024 * 1024
const RECORD_TIME_INDEX := {"buildings": 11, "factions": 8, "units": 12}
var game: Node
var online: Node
var codec := Snapshot.new()
var _started := false
var _accumulator := 0.0
var _tick := 0
var _seq := 0
var _command_seq := 0
var _commands: Array[Dictionary] = []
var _forfeit_factions: Dictionary = {}
var _command_results: Dictionary = {}
var _last_commands: Dictionary = {}
var _previous: Dictionary = {}
var _published: Dictionary = {}
var _mirror: Dictionary = {}
var _view: Dictionary = {}
var _view_dirty := false
var _queued_visuals: Array[Dictionary] = []
var _finish_pending: Dictionary = {}
var _host_time := 0.0
var _host_received_ms := 0
var _host_tick := -1
var _snapshot_tick := -1
var _snapshot_sent_at: Dictionary = {}
var _recovery_baselines: Dictionary = {}
var _surrender_announced: Dictionary = {}
var _account_sent: Dictionary = {}
var _account: Array = []
var _account_tick := -1
var _account_base := 0
var _applied := 0
var _pending: Dictionary = {}
var _outbox: Array[Dictionary] = []
var _outbox_bytes := 0
var _bulk_tokens := 32768.0
var _snapshot_transfers: Dictionary = {}
var _recovery_waiting := false
var _recovery_target := 0
var _recovery_epoch := -1
var _aborted := false
var _anchor_outbox: Array[Dictionary] = []
var _anchor_tokens := 16.0
var _blobs: Dictionary = {}
var _blob_serial := 0
var _since_anchor := 0.0
var _since_digest := 0.0
var _since_time := 0.0
var _silence := 0.0
var _gap_age := 0.0
var _gap_transfer: Dictionary = {}
var _last_resync_ms := -10000
var _snapshot_loading := true
var _result_sent := false
var _presentation: Array[Dictionary] = []
var _time_requests: Dictionary = {}
var rtt_ms := 0.0
var _rtt_sample_at_ms := -1
var sent_rule_bytes := 0
var received_rule_bytes := 0
var resync_count := 0
var resync_reasons: Dictionary = {}

func diagnostics() -> Dictionary:
	var remote_clock_valid: bool = not online.is_host and _started and not _aborted and _host_received_ms > 0 and online.connection_state in ["match", "finished"]
	var rtt_valid := remote_clock_valid and _rtt_sample_at_ms >= 0 and Time.get_ticks_msec() - _rtt_sample_at_ms <= 6000
	return {
		"ready": _started and not _aborted, "is_host": online.is_host,
		"host_rtt_ms": rtt_ms if rtt_valid and is_finite(rtt_ms) else -1.0,
		"authority_age_ms": Time.get_ticks_msec() - _host_received_ms if remote_clock_valid else -1,
		"snapshot_loading": _snapshot_loading, "recovery_waiting": _recovery_waiting,
		"applied_seq": _applied, "pending_events": _pending.size(),
		"outbox_bytes": _outbox_bytes, "resync_count": resync_count,
	}

func setup(battle: Node, transport: Node) -> void:
	game = battle; online = transport
	online.match_started.connect(_on_started)
	online.match_message.connect(_on_message)
	online.room_changed.connect(_on_room)
	online.state_changed.connect(_on_connection)
	online.recovery_requested.connect(_on_recovery)
	game.presentation_event.connect(_on_presentation)
	game.get_node("TeammateCursors").configure(game, online)
	_snapshot_loading = not online.is_host
	game.simulation_paused = true
	game.hud.set_network_status("正在集结", "等待所有玩家加载战场…")
	online.loaded()
	if online.room.get("phase") == "match": _on_started(online.match_config)

func _on_started(config: Dictionary) -> void:
	if str(config.get("match_id", "")) != str(online.match_config.get("match_id", "")): return
	if _started: return
	_started = true
	game.simulation_paused = false
	if online.is_host:
		_previous = Snapshot.for_player(codec.capture(game, _tick), -1)
		_published = _previous.duplicate(true)
		_snapshot_loading = false
		for slot: Dictionary in online.room.slots:
			if _remote_human(slot): _send_snapshot(int(slot.player_id))
	else:
		_request_resync()
	if online.is_host: game.hud.set_network_status("")

func _on_connection(state: String) -> void:
	if game._closing: return
	if state in ["connecting", "reconnecting", "disconnected", "host_lost"]:
		_rtt_sample_at_ms = -1
		if online.is_host:
			# Native transport teardown loses its unsent reliable stream. Fresh
			# per-peer snapshots on recovery supersede all pre-disconnect facts.
			_outbox.clear(); _outbox_bytes = 0
			_snapshot_transfers.clear(); _snapshot_sent_at.clear()
			_recovery_baselines.clear(); _anchor_outbox.clear()
			_surrender_announced.clear()
		_set_transport_paused(true)
		game.hud.set_network_status("连接中断，正在恢复", "战场已暂停显示 · 请稍候")
	elif state == "match" and _started:
		_set_transport_paused(_snapshot_loading or _recovery_waiting)
		_sync_surrenders()
		if not online.is_host: _request_resync()

func _set_transport_paused(value: bool) -> void:
	if game.simulation_paused == value: return
	game.simulation_paused = value
	game.sync_match_control_presentation()

func _sync_surrenders() -> void:
	if not online.is_host or online.connection_state not in ["match", "finished"]: return
	for slot: Dictionary in online.room.get("slots", []):
		if slot.kind != "human": continue
		# Simultaneous departures can end the match on the first surrender. The
		# other authenticated departures still need their detached identities retired.
		if int(slot.faction_id) not in game.surrendered_factions and not (game.finished and slot.get("forfeit_requested", false)): continue
		var player := int(slot.player_id)
		if slot.get("surrendered", false) or _surrender_announced.has(player): continue
		_surrender_announced[player] = true
		online.confirm_surrender(player)

func _on_room(room: Dictionary) -> void:
	if not is_instance_valid(game) or game._closing or room.is_empty(): return
	game.configure_controllers(room.slots)
	if online.is_host:
		for slot: Dictionary in room.slots:
			if slot.get("forfeit_requested", false): _forfeit_factions[int(slot.faction_id)] = true
	_try_recovery_ack()
	_sync_surrenders()
	var phase: String = room.get("phase", "room")
	if phase == "host_lost":
		_set_transport_paused(true)
		game.hud.set_network_status("等待房主恢复连接", "对局已暂停 · 30 秒内可恢复")
	elif phase == "match" and _started:
		_set_transport_paused(_snapshot_loading or _recovery_waiting)
		_sync_surrenders()
		if online.is_host: game.hud.set_network_status("")
		elif _local_slot().get("controller") == "reconnecting": _request_resync()

func process(delta: float) -> void:
	game.get_node("TeammateCursors").tick(delta)
	_flush_outbox(delta)
	_flush_anchors(delta)
	_silence += delta
	_expire_blobs()
	if not _started or _aborted: return
	if online.room.get("phase") == "host_lost" or online.connection_state in ["connecting", "reconnecting", "disconnected"]:
		_set_transport_paused(true)
		return
	if game.finished: return
	if online.is_host:
		_set_transport_paused(false)
		game.marches.begin_render_batch()
		if game.match_paused:
			# Control requests still run while paused; simulation, AI, cooldowns
			# and delayed departures do not accrue wall-clock debt.
			_accumulator = 0.0
			if not _commands.is_empty() or not _forfeit_factions.is_empty():
				_drain_commands()
				_publish_step(0.0)
		else:
			_accumulator += delta
			var count := 0
			while _accumulator + 0.0000001 >= STEP and count < 8 and not game.finished and not _aborted:
				_accumulator -= STEP; count += 1; _tick += 1
				_drain_commands()
				if game.match_paused or game.finished:
					_accumulator = 0.0
					_publish_step(0.0)
					break
				game.simulate(STEP)
				_publish_step(STEP)
		game.marches.end_render_batch()
		_since_time += delta
		if _since_time >= ANCHOR_INTERVAL:
			_since_time = 0.0
			online.send_match("time", {"time": game.elapsed, "tick": _tick, "seq": _seq})
		if game.finished and not _result_sent:
			_result_sent = true
			online.send_match("finished", {"winner": game.winner_team, "tick": _tick, "seq": _seq})
	else:
		if _snapshot_loading and _blobs.is_empty() and Time.get_ticks_msec() - _last_resync_ms > 4000: _request_resync()
		_since_time += delta
		if _since_time >= 1.0:
			_since_time = 0.0
			var stamp := Time.get_ticks_msec()
			_time_requests[stamp] = true
			online.send_match("ack", {"op": "time", "stamp": stamp}, -1, 1, true)
			for key: int in _time_requests.keys():
				if stamp - key > 10000: _time_requests.erase(key)
		_check_event_gap(delta, Time.get_ticks_msec())
		if _silence > 2.0:
			_set_transport_paused(true)
			_request_resync("authority_silence")
			return
		if not _snapshot_loading and not _mirror.is_empty():
			var presentation_begun: int = game.debug_metrics.begin()
			_set_transport_paused(_recovery_waiting)
			game.hud.set_network_status("正在追上战况" if _recovery_waiting else "", "等待后续战斗事件确认" if _recovery_waiting else "")
			_apply_view(true)
			codec.present(game, _view, _presentation_step(delta))
			_apply_account()
			_maybe_finish()
			game.debug_metrics.end(&"presentation", presentation_begun)

func submit(command: Dictionary) -> Dictionary:
	if not _started or _snapshot_loading or _recovery_waiting or game.finished or game.simulation_paused or _aborted:
		return {"accepted": false, "reason": "正在同步，请稍候"}
	var slot: Dictionary = _local_slot()
	if slot.is_empty() or slot.get("controller") != "human" or not slot.get("connected", false):
		return {"accepted": false, "reason": "尚未恢复控制权"}
	if game.local_faction in game.surrendered_factions:
		return {"accepted": false, "reason": "你已投降，正在观战"}
	_command_seq += 1
	var envelope := {"seq": _command_seq, "epoch": int(slot.control_epoch), "command": command}
	if online.is_host: _receive_command(online.player_id, envelope)
	else: online.send_command(envelope)
	return {"accepted": true, "pending": true, "reason": ""}

func _local_slot() -> Dictionary:
	for slot: Dictionary in online.room.get("slots", []):
		if slot.player_id == online.player_id: return slot
	return {}

func _slot_for(player: int) -> Dictionary:
	for slot: Dictionary in online.room.get("slots", []):
		if slot.kind == "human" and slot.player_id == player: return slot
	return {}

func _remote_human(slot: Dictionary) -> bool:
	return slot.kind == "human" and slot.player_id != online.player_id and slot.get("connected", false)

func _receive_command(player: int, payload: Dictionary) -> void:
	var slot := _slot_for(player)
	if slot.is_empty() or slot.get("controller") != "human" or not slot.get("connected", false): return
	if not Snapshot._integer(payload.get("seq"), 1, 2147483647) or not Snapshot._integer(payload.get("epoch"), 0, 2147483647) or not payload.get("command") is Dictionary: return
	if int(payload.epoch) != int(slot.control_epoch): return
	var key := "%d:%d:%d" % [player, int(payload.epoch), int(payload.seq)]
	if _command_results.has(key):
		_reply(player, _command_results[key]); return
	var controller := "%d:%d" % [player, int(payload.epoch)]
	if int(payload.seq) <= int(_last_commands.get(controller, 0)): return
	_last_commands[controller] = int(payload.seq)
	_commands.append({"player": player, "faction": int(slot.faction_id), "epoch": int(payload.epoch), "seq": int(payload.seq), "key": key, "command": payload.command})

func _drain_commands() -> void:
	# A voluntary leave is authenticated and retained by Relay until the Host
	# commits its normal surrender transaction, even if the Host was absent.
	for faction: int in _forfeit_factions.keys():
		_forfeit_factions.erase(faction)
		for slot: Dictionary in online.room.get("slots", []):
			if int(slot.faction_id) == faction and slot.kind == "human" and slot.get("forfeit_requested", false):
				if not game.has_surrendered(faction): game.surrender_faction(faction)
				break
	var queue := _commands
	_commands = []
	for entry: Dictionary in queue:
		var slot := _slot_for(entry.player)
		var result := {"accepted": false, "reason": "控制权已改变"}
		if not slot.is_empty() and slot.get("controller") == "human" and slot.get("connected", false) and int(slot.control_epoch) == entry.epoch:
			result = game.execute_network_command(entry.faction, entry.command)
		result["command_seq"] = entry.seq; result["epoch"] = entry.epoch; result["tick"] = _tick
		_command_results[entry.key] = result
		_reply(entry.player, result)
	while _command_results.size() > 2048: _command_results.erase(_command_results.keys()[0])

func _reply(player: int, result: Dictionary) -> void:
	if player == online.player_id:
		if not result.accepted: game.audio.play_ui(&"war_denied")
	else: online.send_match("command_result", result, player, 1, true)

func _publish_step(delta: float) -> void:
	var replication_begun: int = game.debug_metrics.begin()
	var complete := codec.capture(game, _tick)
	var current := Snapshot.for_player(complete, -1)
	_since_anchor += delta; _since_digest += delta
	var anchor := _since_anchor + 0.000001 >= ANCHOR_INTERVAL
	if anchor: _since_anchor = 0.0
	# Only discrete facts use reliable event traffic. A regular checkpoint also
	# repairs continuous values; motion anchors are independent replaceable data.
	var patch := Snapshot.diff(_previous, current)
	_previous = current
	if not patch.set.is_empty() or not patch.remove.is_empty() or not _presentation.is_empty() or current.finished != _published.finished or current.match_control != _published.match_control:
		_seq += 1
		patch["seq"] = _seq
		patch["visuals"] = _presentation
		_presentation = []
		Snapshot.apply_delta(_published, patch)
		_send_payload("events", patch)
	_sync_surrenders()
	if anchor:
		_send_anchors(current)
		_send_accounts(complete)
	else:
		_send_accounts(complete, true)
	if _since_digest >= 2.0:
		_since_digest = 0.0
		# Hash the reliable committed mirror, not independently delivered anchors.
		online.send_match("digest", {"seq": _seq, "hash": Snapshot.digest(_published)})
	game.debug_metrics.end(&"replication", replication_begun)

func _send_accounts(state: Dictionary, only_change: bool = false) -> void:
	for slot: Dictionary in online.room.get("slots", []):
		if not _remote_human(slot): continue
		var key := "account:%d" % int(slot.player_id)
		var row: Array = state.factions[str(int(slot.faction_id))]
		var before: Array = _account_sent.get(key, [])
		if only_change and not before.is_empty() and not Snapshot._discrete_changed("factions", before, row): continue
		_account_sent[key] = row
		online.send_match("events", {"account": row, "faction": int(slot.faction_id), "tick": _tick, "base": _seq}, int(slot.player_id))

func _send_anchors(state: Dictionary) -> void:
	# Each record is an absolute atomic field group; no packet depends on another
	# unreliable packet. Structural changes are ONLY installed from reliable facts.
	# Spread optional packets over frames. A slow Host finishes the current
	# sweep before starting another, so no tail of the army can starve.
	if not _anchor_outbox.is_empty(): return
	for group: String in ["buildings", "factions", "units"]:
		var rows: Dictionary = {}
		for key: String in state[group]:
			# Millimetre precision is well below a rendered soldier pixel. Share the
			# clock per packet; persistent flags/routes stay on the reliable stream.
			rows[key] = roundi(float(state.units[key][1]) * 1000.0) if group == "units" else state[group][key]
			if rows.size() >= (32 if group == "units" else 2):
				_anchor_outbox.append({"group": group, "rows": rows, "time": state.time, "tick": _tick, "base": _seq})
				rows = {}
		if not rows.is_empty(): _anchor_outbox.append({"group": group, "rows": rows, "time": state.time, "tick": _tick, "base": _seq})

func _flush_anchors(delta: float) -> void:
	if not online.is_host or online.connection_state != "match": return
	_anchor_tokens = minf(32.0, _anchor_tokens + maxf(0.0, delta) * 400.0)
	while not _anchor_outbox.is_empty() and _anchor_tokens >= 1.0:
		_anchor_tokens -= 1.0
		online.send_match("anchors", _anchor_outbox.pop_front(), -1, 4, false)

func _on_message(sender: int, kind: String, payload: Dictionary) -> void:
	# Delivery is called from Online's process callback, outside the battle frame.
	# Keep all early-return paths inside the measured handler.
	var replication_begun: int = game.debug_metrics.begin()
	_handle_message(sender, kind, payload)
	game.debug_metrics.end(&"replication", replication_begun)

func _handle_message(sender: int, kind: String, payload: Dictionary) -> void:
	if game._closing: return
	if online.is_host:
		match kind:
			"command": _receive_command(sender, payload)
			"resync": _send_snapshot(sender)
			"ack":
				if payload.get("op") == "recovered" and _recovery_baselines.has(sender) and Snapshot._integer(payload.get("seq"), int(_recovery_baselines[sender].seq), _seq) and Snapshot._integer(payload.get("epoch"), 0, 2147483647) and payload.epoch == _recovery_baselines[sender].epoch and _slot_for(sender).get("control_epoch") == _recovery_baselines[sender].epoch:
					online.complete_recovery(sender, int(_recovery_baselines[sender].epoch))
					_recovery_baselines.erase(sender)
				elif payload.get("op") == "time" and Snapshot._integer(payload.get("stamp"), 0, 9007199254740991):
					online.send_match("time", {"stamp": payload.stamp, "time": game.elapsed, "tick": _tick, "seq": _seq}, sender, 2, true)
		return
	if sender != int(online.match_config.get("host_player_id", -2)): return
	_silence = 0.0
	match kind:
		"snapshot_begin", "snapshot_chunk", "snapshot_end": _receive_blob(kind, payload)
		"events":
			if payload.has("account"):
				if payload.get("faction") == game.local_faction and Snapshot.valid_account(payload.account, game) and Snapshot._integer(payload.get("tick"), 0, 2147483647) and Snapshot._integer(payload.get("base"), 0, 2147483647) and (int(payload.tick) > _account_tick or (int(payload.tick) == _account_tick and int(payload.base) > _account_base)):
					_account = payload.account; _account_tick = int(payload.tick); _account_base = int(payload.base)
					_apply_account()
			else: _receive_events(payload)
		"anchors": _receive_anchor(payload)
		"digest":
			if not _snapshot_loading and payload.get("seq") == _applied and Snapshot.digest(_mirror) != payload.get("hash", ""):
				_request_resync("checksum")
		"command_result":
			if payload.get("accepted") == false: game.audio.play_ui(&"war_denied")
		"time":
			if not Snapshot._integer(payload.get("tick"), 0, 2147483647) or not Snapshot._number(payload.get("time")): return
			var stamp := int(payload.get("stamp", -1)) if Snapshot._integer(payload.get("stamp"), 0, 9007199254740991) else -1
			if _time_requests.has(stamp):
				var sample := float(Time.get_ticks_msec() - stamp)
				rtt_ms = sample if rtt_ms <= 0.0 else lerpf(rtt_ms, sample, 0.125)
				_rtt_sample_at_ms = Time.get_ticks_msec()
				_time_requests.erase(stamp)
			_set_clock(float(payload.time), int(payload.tick))
		"finished":
			if Snapshot._integer(payload.get("winner"), -1, 1) and Snapshot._integer(payload.get("seq"), 0, 2147483647):
				_finish_pending = payload

func _receive_events(payload: Dictionary) -> void:
	if not Snapshot._integer(payload.get("seq"), 1, 2147483647): return
	var seq := int(payload.seq)
	if seq <= _applied: return
	if _pending.size() >= MAX_PENDING_EVENTS:
		_pending.clear(); _request_resync(); return
	_pending[seq] = payload
	_drain_events()

func _check_event_gap(delta: float, now: int) -> void:
	if _snapshot_loading or _pending.is_empty():
		_gap_age = 0.0
		_gap_transfer.clear()
		return
	_gap_age += delta
	if _gap_age <= 2.0: return
	# Later small facts can overtake an event blob on the bulk stream. Allow
	# one already-active transfer its existing deadline, never a rolling timeout
	# extended by unrelated blobs. Completing it must advance the missing seq.
	if _gap_transfer.is_empty():
		for id: String in _blobs:
			var blob: Dictionary = _blobs[id]
			if blob.meta.purpose != "events": continue
			if _gap_transfer.is_empty() or int(blob.deadline) < int(_gap_transfer.deadline):
				_gap_transfer = {"id": id, "deadline": int(blob.deadline)}
	if not _gap_transfer.is_empty() and _blobs.has(_gap_transfer.id) and now < int(_gap_transfer.deadline): return
	_request_resync("event_gap")

func _drain_events() -> void:
	if _snapshot_loading or _mirror.is_empty(): return
	while _pending.has(_applied + 1):
		var payload: Dictionary = _pending[_applied + 1]
		if not _valid_patch(payload):
			_request_resync("invalid_patch"); return
		# Rows are immutable protocol values. Copy only dictionaries written by
		# this transaction rather than cloning every soldier for one tower hit.
		var candidate := _mirror.duplicate(false)
		for group: String in Snapshot.GROUPS:
			if payload.set.has(group) or payload.remove.has(group): candidate[group] = _mirror[group].duplicate(false)
		Snapshot.apply_delta(candidate, payload)
		if not Snapshot.valid(candidate, game):
			_request_resync("invalid_state"); return
		_pending.erase(_applied + 1); _applied += 1
		_gap_age = 0.0
		_gap_transfer.clear()
		_mirror = candidate
		_set_clock(float(payload.time), int(payload.tick))
		_view_dirty = true
		for visual: Variant in payload.get("visuals", []):
			if visual is Dictionary and _queued_visuals.size() < 4096: _queued_visuals.append(visual)
	_replay_pending_anchors()
	_try_recovery_ack()

func _valid_patch(payload: Dictionary) -> bool:
	if not payload.get("set") is Dictionary or not payload.get("remove") is Dictionary or not Snapshot._number(payload.get("time")) or not Snapshot._integer(payload.get("tick"), 0, 2147483647) or not payload.get("finished") is bool or not Snapshot._integer(payload.get("winner"), -2, 1) or not Snapshot._row(payload.get("counters"), Snapshot.COUNTER_SIZE): return false
	if not Snapshot.valid_match_control(payload.get("match_control"), game): return false
	for faction: int in _mirror.match_control.surrendered:
		if not payload.match_control.surrendered.any(func(value: Variant): return int(value) == faction): return false
	if float(payload.time) < float(_mirror.time) or int(payload.tick) < int(_mirror.tick): return false
	if payload.has("visuals") and not payload.visuals is Array: return false
	for group: Variant in payload.set:
		if group not in Snapshot.GROUPS or not payload.set[group] is Dictionary: return false
	for group: Variant in payload.remove:
		if group not in Snapshot.GROUPS or not payload.remove[group] is Array: return false
		for key: Variant in payload.remove[group]:
			if not key is String: return false
	return true

var _anchor_versions: Dictionary = {}
var _anchor_state: Dictionary = {}
var _pending_anchors: Dictionary = {}

func _receive_anchor(payload: Dictionary) -> void:
	if _snapshot_loading or _mirror.is_empty() or not Snapshot._integer(payload.get("base"), 0, 2147483647): return
	if payload.get("group") not in ["buildings", "factions", "units"] or not payload.get("rows") is Dictionary or not Snapshot._integer(payload.get("tick"), 0, 2147483647) or not Snapshot._number(payload.get("time")): return
	var group: String = payload.group
	if payload.rows.size() > 32: return
	if int(payload.base) > _applied:
		_queue_future_anchor(payload)
		return
	if not _anchor_state.has(group): _anchor_state[group] = {}
	var accepted := false
	for key: Variant in payload.rows:
		if not key is String or not _mirror[group].has(key): continue
		var stamp: String = group + ":" + str(key)
		if int(payload.tick) <= int(_anchor_versions.get(stamp, -1)): continue
		var row: Variant = payload.rows[key]
		if group == "units":
			if not Snapshot._integer(row, -10000000, 10000000): continue
			# Compact rows carry no order ID. A later same-time transaction may
			# have redirected this soldier, so an earlier base cannot identify it.
			if int(payload.base) < _applied and float(payload.time) <= _record_time(group, _mirror.units[key]): continue
			var distance: float = float(row) / 1000.0
			row = _mirror.units[key].duplicate(false)
			row[13] = float(row[13]) + maxf(0.0, distance - float(row[1])) * 7.0
			row[1] = distance
			# Reliable entry/exit facts distinguish a refreshing aura from its
			# fixed tail. Compact motion anchors share the aura's new sample time.
			if Snapshot.slow_is_refreshing(row):
				row[14] = float(payload.time) + Snapshot.RULES.BEAR_SLOW_LINGER
			if Snapshot.haste_is_refreshing(row):
				row[15] = float(payload.time) + Snapshot.RULES.HASTE_LINGER
			row[12] = float(payload.time)
		if not Snapshot.valid_record(group, row, game): continue
		# Do not let an old anchor replace a newer reliable structural transition.
		if _record_time(group, row) < _record_time(group, _mirror[group][key]): continue
		if not Snapshot.same_structure(group, _mirror[group][key], row): continue
		_anchor_versions[stamp] = int(payload.tick)
		_anchor_state[group][key] = row
		_view_dirty = true
		accepted = true
	if accepted: _set_clock(float(payload.time), int(payload.tick))

func _queue_future_anchor(payload: Dictionary) -> void:
	if not Snapshot._nonnegative(payload.time): return
	var group: String = payload.group
	for key: Variant in payload.rows:
		if not key is String: continue
		var row: Variant = payload.rows[key]
		if group == "units":
			if not Snapshot._integer(row, -10000000, 10000000): continue
		elif not Snapshot.valid_record(group, row, game): continue
		var stamp: String = group + ":" + key
		if int(payload.tick) <= int(_anchor_versions.get(stamp, -1)): continue
		if _pending_anchors.has(stamp) and int(payload.tick) <= int(_pending_anchors[stamp].tick): continue
		_pending_anchors.erase(stamp)
		if _pending_anchors.size() >= MAX_PENDING_ANCHOR_ROWS:
			# These optional absolute rows can be replaced or dropped. Evict in
			# batches so overflowing traffic does not allocate all keys per row.
			var oldest: Array = _pending_anchors.keys()
			for index: int in ceili(MAX_PENDING_ANCHOR_ROWS / 4.0):
				_pending_anchors.erase(oldest[index])
		_pending_anchors[stamp] = {"group": group, "rows": {key: row}, "base": payload.base, "tick": payload.tick, "time": payload.time}

func _replay_pending_anchors() -> void:
	for stamp: String in _pending_anchors.keys():
		var payload: Dictionary = _pending_anchors[stamp]
		if int(payload.base) > _applied: continue
		_pending_anchors.erase(stamp)
		# Re-run existence, version, structure and timestamp checks against the
		# committed state; queuing alone never changes the view or Host clock.
		_receive_anchor(payload)

func _apply_view(defer_render: bool = false) -> void:
	if not _view_dirty: return
	# A network service pass may deliver hundreds of small absolute anchors.
	# Compose and install once per frame, never once per packet or soldier.
	_view = _mirror.duplicate(false)
	for name: String in ["buildings", "factions", "units"]:
		_view[name] = _mirror[name].duplicate(false)
		var records: Dictionary = _anchor_state.get(name, {})
		for key: String in records.keys():
			if not _view[name].has(key) or _record_time(name, records[key]) < _record_time(name, _view[name][key]) or not Snapshot.same_structure(name, _view[name][key], records[key]):
				records.erase(key)
				_anchor_versions.erase(name + ":" + key)
			else: _view[name][key] = records[key]
	# Ordinary facts must not jump the display clock: unchanged soldiers retain
	# their local poses, and present() is responsible for advancing all of them.
	# Only explicit pause/resume boundaries (and snapshot installation) align it.
	var control_boundary: bool = game.match_paused != _mirror.match_control.paused
	var now: float = float(_mirror.time) if control_boundary or _mirror.match_control.paused else game.elapsed
	var control_changed: bool = codec.install(game, _view, now, true, defer_render)
	_view_dirty = false
	_apply_account()
	# HUD ready/cooldown edges must only observe the complete public + private
	# state, never the redacted zeros carried by a public snapshot or anchor.
	if control_changed: game.sync_match_control_presentation()
	else: game.update_hud()
	for event: Dictionary in _queued_visuals: _play_presentation(event)
	_queued_visuals.clear()

func _set_clock(time: float, tick: int) -> void:
	# Repeated heartbeats for the same tick must not restart extrapolation age.
	if tick < _host_tick or time < 0.0 or (tick == _host_tick and time <= _host_time): return
	_host_tick = tick
	_host_time = time
	_host_received_ms = Time.get_ticks_msec()

func _presentation_step(delta: float) -> float:
	if delta <= 0.0 or game.is_rule_paused(): return 0.0
	var age := maxf(0.0, float(Time.get_ticks_msec() - _host_received_ms) / 1000.0)
	var limit := _host_time + 0.5 + rtt_ms / 2000.0
	var target := _host_time + minf(0.5, age) + rtt_ms / 2000.0 - 0.1
	# Ease clock error through speed, never alternating zero-time frames and
	# jumps on packet arrival. A stale authority still has a finite prediction cap.
	var rate := clampf(1.0 + (target - game.elapsed - delta) * 2.0, 0.9, 1.1)
	return minf(delta * rate, maxf(0.0, limit - game.elapsed))

func _maybe_finish() -> void:
	if _finish_pending.is_empty() or _snapshot_loading or int(_finish_pending.seq) > _applied: return
	if not _mirror.get("finished", false): return
	game._finish_match(int(_finish_pending.winner))
	_finish_pending.clear()

func _record_time(group: String, row: Variant) -> float:
	var index: int = RECORD_TIME_INDEX[group]
	return float(row[index]) if row is Array and row.size() > index and Snapshot._number(row[index]) else -1.0

func _apply_account() -> void:
	if _account.is_empty() or _account_base > _applied: return
	var skill: RefCounted = game.faction_skills[game.local_faction]
	if not Snapshot.valid_account(_account, game): return
	skill.energy = Snapshot.energy_at(_account, game.elapsed)
	for i: int in 4: skill.cooldowns[i] = Snapshot.remaining(_account[2][i], game.elapsed)

func _send_snapshot(player: int) -> void:
	if not online.is_host or _slot_for(player).is_empty(): return
	var now := Time.get_ticks_msec()
	if now - int(_snapshot_sent_at.get(player, -10000)) < 1500: return
	if _snapshot_transfers.has(player):
		var transfer: Dictionary = _snapshot_transfers[player]
		if transfer.started: return
		# Replace a snapshot that has not entered the native stream yet. Already
		# transmitted snapshots finish normally; reliable facts are never dropped.
		_cancel_snapshot(player)
	_snapshot_sent_at[player] = now
	if _published.is_empty(): return
	var complete := codec.capture(game, _tick)
	# Hashes refer only to reliable committed facts. Fresh continuous values
	# travel as a separate display baseline so they cannot cause resync loops.
	var view := Snapshot.for_player(complete, -1)
	var account: Array = complete.factions[str(int(_slot_for(player).faction_id))]
	var epoch := int(_slot_for(player).control_epoch)
	_recovery_baselines[player] = {"seq": _seq, "epoch": epoch}
	_send_blob("snapshot", {"state": _published, "view": view, "seq": _seq, "epoch": epoch, "account": account, "winner": game.winner_team}, player)

func _on_recovery(player: int) -> void:
	if not _started or not online.is_host: return
	# A new authenticated transport cannot complete a blob whose prefix was
	# sent to the previous native peer. Ordinary resync requests do not cancel it.
	_cancel_snapshot(player)
	_snapshot_sent_at.erase(player)
	_surrender_announced.erase(player)
	_sync_surrenders()
	_send_snapshot(player)

func _cancel_snapshot(player: int) -> void:
	if not _snapshot_transfers.has(player): return
	var id: String = _snapshot_transfers[player].id
	for index: int in range(_outbox.size() - 1, -1, -1):
		if _outbox[index].payload.id == id:
			_outbox_bytes -= int(_outbox[index].bytes)
			_outbox.remove_at(index)
	_snapshot_transfers.erase(player)

func _send_payload(kind: String, payload: Dictionary, target: int = -1) -> void:
	var bytes := JSON.stringify(payload, "", true, true).to_utf8_buffer()
	sent_rule_bytes += bytes.size()
	if bytes.size() <= 12000: online.send_match(kind, payload, target)
	else: _send_blob_bytes(kind, bytes, target)

func _send_blob(purpose: String, payload: Dictionary, target: int) -> void:
	var raw := JSON.stringify(payload, "", true, true).to_utf8_buffer()
	_send_blob_bytes(purpose, raw, target)

func _send_blob_bytes(purpose: String, raw: PackedByteArray, target: int) -> void:
	if raw.size() > MAX_BLOB_BYTES:
		_abort_sync("对局同步数据超过容量上限，房间已结束"); return
	var bytes := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if _outbox_bytes + bytes.size() * 2 + 2048 > MAX_OUTBOX_BYTES:
		_abort_sync("网络同步持续积压，房间已结束，请检查房主上行网络"); return
	_blob_serial += 1
	var id := "%d:%d" % [_tick, _blob_serial]
	if purpose == "snapshot": _snapshot_transfers[target] = {"id": id, "started": false}
	var parts := ceili(float(bytes.size()) / CHUNK_BYTES)
	_queue("snapshot_begin", {"id": id, "purpose": purpose, "size": bytes.size(), "raw_size": raw.size(), "parts": parts, "hash": bytes.hex_encode().sha256_text()}, target)
	for index: int in parts:
		_queue("snapshot_chunk", {"id": id, "index": index, "data": Marshalls.raw_to_base64(bytes.slice(index * CHUNK_BYTES, mini(bytes.size(), (index + 1) * CHUNK_BYTES)))}, target)
	_queue("snapshot_end", {"id": id, "purpose": purpose}, target)

func _queue(kind: String, payload: Dictionary, target: int) -> void:
	var size := JSON.stringify(payload, "", true, true).to_utf8_buffer().size() + 160
	_outbox_bytes += size
	_outbox.append({"kind": kind, "payload": payload, "target": target, "bytes": size})

func _flush_outbox(delta: float = 0.0) -> void:
	if online.connection_state in ["reconnecting", "disconnected", "connecting"]: return
	_bulk_tokens = minf(32768.0, _bulk_tokens + maxf(0.0, delta) * BULK_BYTES_PER_SECOND)
	while not _outbox.is_empty() and _bulk_tokens >= int(_outbox[0].bytes):
		var entry: Dictionary = _outbox.pop_front()
		_bulk_tokens -= int(entry.bytes)
		_outbox_bytes -= int(entry.bytes)
		if entry.kind == "snapshot_begin" and entry.payload.purpose == "snapshot":
			_snapshot_transfers[entry.target].started = true
		elif entry.kind == "snapshot_end" and entry.payload.purpose == "snapshot":
			# A recovery must catch all facts created while its baseline travelled.
			entry.payload.through = _seq
			_recovery_baselines[entry.target].seq = _seq
			_snapshot_transfers.erase(entry.target)
		# Manifest/chunks/end share the same reliable native stream; battle events
		# can arrive meanwhile and are protected by their explicit baseline.
		online.send_match(entry.kind, entry.payload, entry.target, 5, true)

func _abort_sync(reason: String) -> void:
	_aborted = true
	game.simulation_paused = true
	_outbox.clear(); _outbox_bytes = 0
	online.abort_connection(reason)

func _receive_blob(kind: String, payload: Dictionary) -> void:
	var id: Variant = payload.get("id")
	if not id is String or id.length() > 64: return
	if kind == "snapshot_begin":
		if payload.get("purpose") not in ["snapshot", "events"] or not Snapshot._integer(payload.get("size"), 1, MAX_BLOB_BYTES) or not Snapshot._integer(payload.get("raw_size"), 1, MAX_BLOB_BYTES) or not Snapshot._integer(payload.get("parts"), 1, ceili(float(MAX_BLOB_BYTES) / CHUNK_BYTES)): return
		if int(payload.parts) != ceili(float(payload.size) / CHUNK_BYTES) or not payload.get("hash") is String or payload.hash.length() != 64: return
		if payload.purpose == "snapshot":
			for previous: String in _blobs.keys():
				if _blobs[previous].meta.purpose == "snapshot": _blobs.erase(previous)
		if _blobs.size() >= 8: _blobs.clear(); _request_resync(); return
		var transfer_seconds := maxf(15.0, float(payload.size) * 2.0 / BULK_BYTES_PER_SECOND + 15.0)
		_blobs[id] = {"meta": payload, "chunks": {}, "deadline": Time.get_ticks_msec() + ceili(transfer_seconds * 1000.0)}
	elif kind == "snapshot_chunk":
		if not _blobs.has(id) or not payload.get("data") is String or payload.data.length() > 1024 or not Snapshot._integer(payload.get("index"), 0, int(_blobs[id].meta.parts) - 1): return
		_blobs[id].chunks[int(payload.index)] = Marshalls.base64_to_raw(payload.data)
	elif kind == "snapshot_end":
		if not _blobs.has(id): return
		var blob: Dictionary = _blobs[id]; _blobs.erase(id)
		if blob.chunks.size() != int(blob.meta.parts): _request_resync(); return
		var bytes := PackedByteArray()
		for index: int in int(blob.meta.parts): bytes.append_array(blob.chunks[index])
		if bytes.size() != int(blob.meta.size) or bytes.hex_encode().sha256_text() != blob.meta.get("hash"): _request_resync(); return
		var raw := bytes.decompress(int(blob.meta.raw_size), FileAccess.COMPRESSION_ZSTD)
		if raw.size() != int(blob.meta.raw_size): _request_resync(); return
		var result: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if not result is Dictionary: _request_resync(); return
		received_rule_bytes += raw.size()
		if blob.meta.purpose == "events": _receive_events(result)
		else:
			if not Snapshot._integer(result.get("seq"), 0, 2147483647): _request_resync(); return
			if not Snapshot._integer(payload.get("through"), int(result.get("seq", 0)), 2147483647): _request_resync(); return
			result.through = int(payload.through)
			_install_snapshot(result)

func _install_snapshot(payload: Dictionary) -> void:
	if not payload.get("state") is Dictionary or not Snapshot._integer(payload.get("seq"), 0, 2147483647) or not Snapshot.valid(payload.state, game): _request_resync(); return
	if not payload.get("view") is Dictionary or not Snapshot.valid(payload.view, game) or not Snapshot.valid_account(payload.get("account"), game): _request_resync(); return
	if not Snapshot._integer(payload.get("through"), int(payload.seq), 2147483647): _request_resync(); return
	if not Snapshot._integer(payload.get("epoch"), 0, 2147483647): _request_resync(); return
	if int(payload.epoch) < int(_local_slot().get("control_epoch", -1)): _request_resync("stale_recovery_epoch"); return
	if int(payload.seq) < _applied or int(payload.view.tick) < _snapshot_tick: return
	if not Snapshot.same_match_control(payload.state.match_control, payload.view.match_control): _request_resync(); return
	# The display baseline must contain exactly the same live entities/facts.
	for group: String in Snapshot.GROUPS:
		if payload.state[group].size() != payload.view[group].size(): _request_resync(); return
		for key: String in payload.state[group]:
			if not payload.view[group].has(key): _request_resync(); return
	_mirror = payload.state
	_queued_visuals.clear()
	_applied = int(payload.seq)
	_recovery_waiting = true
	_recovery_target = int(payload.through)
	_recovery_epoch = int(payload.epoch)
	_snapshot_tick = int(payload.view.tick)
	codec = Snapshot.new()
	_anchor_state.clear(); _anchor_versions.clear()
	_pending_anchors.clear()
	for group: String in ["buildings", "factions", "units"]:
		_anchor_state[group] = payload.view[group].duplicate(false)
		for key: String in _anchor_state[group]: _anchor_versions[group + ":" + key] = _snapshot_tick
	_view_dirty = true
	game.elapsed = float(payload.view.time)
	_host_tick = -1
	# Multiple control transactions can change energy income at one paused tick.
	# A recovery baseline must not replace a newer private account from that tick.
	if _snapshot_tick > _account_tick or (_snapshot_tick == _account_tick and _applied >= _account_base):
		_account = payload.account; _account_tick = _snapshot_tick; _account_base = _applied
	_set_clock(float(payload.view.time), _snapshot_tick)
	_snapshot_loading = false; _gap_age = 0.0
	_gap_transfer.clear()
	for seq: int in _pending.keys():
		if seq <= _applied: _pending.erase(seq)
	_drain_events()
	_apply_view()
	if _mirror.finished and Snapshot._integer(payload.get("winner"), -1, 1):
		_finish_pending = {"winner": payload.winner, "seq": _applied}
	_maybe_finish()
	_try_recovery_ack()

func _try_recovery_ack() -> void:
	if not _recovery_waiting or _snapshot_loading or _applied < _recovery_target: return
	var epoch := int(_local_slot().get("control_epoch", -1))
	if _recovery_epoch < epoch:
		_request_resync("stale_recovery_epoch")
		return
	# The room channel can arrive after the bulk channel. Only acknowledge the
	# exact connection generation represented by this fully installed baseline.
	if _recovery_epoch != epoch: return
	_recovery_waiting = false
	online.send_match("ack", {"op": "recovered", "seq": _applied, "epoch": _recovery_epoch}, -1, 1, true)

func _request_resync(reason: String = "recovery") -> void:
	var now := Time.get_ticks_msec()
	if online.is_host or now - _last_resync_ms < 2000: return
	_last_resync_ms = now; resync_count += 1
	resync_reasons[reason] = int(resync_reasons.get(reason, 0)) + 1
	_snapshot_loading = true
	_queued_visuals.clear()
	game.simulation_paused = true
	game.hud.set_network_status("正在同步战场", "恢复部队、建筑与技能状态…")
	online.send_match("resync", {"seq": _applied}, -1, 1, true)

func _expire_blobs() -> void:
	var now := Time.get_ticks_msec()
	for id: String in _blobs.keys():
		if now > int(_blobs[id].deadline):
			_blobs.erase(id); _request_resync()

func _on_presentation(kind: String, payload: Dictionary) -> void:
	if online.is_host: _presentation.append({"kind": kind, "payload": payload})

func _play_presentation(event: Dictionary) -> void:
	# Visual-only event implementations are shared with the authority's authored
	# effects. Persistent fields/wards/cloak already come from the rule mirror.
	if not event.get("payload") is Dictionary: return
	var payload: Dictionary = event.payload
	var at := Snapshot.vector(payload.at) if Snapshot._vector(payload.get("at")) else Vector3.ZERO
	match event.get("kind", ""):
		"skill":
			if not Snapshot._integer(payload.get("faction"), 0, game.faction_count - 1) or not Snapshot._integer(payload.get("skill"), 0, 3) or not payload.get("commander") is String or not Snapshot._vector(payload.get("at")): return
			var faction := int(payload.faction); var skill := int(payload.skill)
			var commander: String = payload.get("commander", "")
			if commander == "rabbit":
				if skill == 0: game.world_effects.get_node("Rabbit").start_rush(faction, at, game.SKILL_RULES.RABBIT_RUSH_RADIUS)
				elif skill == 2: game.world_effects.get_node("Rabbit").start_recall(faction, at, game.SKILL_RULES.RECALL_RADIUS)
			elif commander == "bear":
				if skill == 0: game.world_effects.get_node("Bear").toolbox(faction, at)
				elif skill == 1: game.world_effects.get_node("Bear").lock(faction, at)
			elif commander == "frog": game.world_effects.get_node("Frog").release(skill, faction, at)
			elif commander == "fox":
				if skill != 2 and (not Snapshot._integer(payload.get("target"), 0, 2147483647) or not game.by_id.has(int(payload.target))): return
				game.world_effects.get_node("Fox").release(skill, faction, at, int(payload.get("target", -1)))
			var audio_names := {"squirrel": ["war_skill_command", "war_skill_drum", "war_skill_shield", "war_skill_breach"], "rabbit": ["war_rabbit_dash", "war_rabbit_seal", "war_rabbit_recall", "war_rabbit_burrow"], "bear": ["war_bear_toolbox", "war_bear_stomp", "war_bear_link", "war_bear_ward"], "frog": ["war_frog_mist", "war_frog_float", "war_frog_cloak", "war_frog_strike"], "fox": ["war_fox_bomb", "war_fox_steal", "war_fox_convert", "war_fox_panic"], "pig": game.pig.CAST_SOUNDS}
			if audio_names.has(commander): game.audio.play_world(StringName(audio_names[commander][skill]), at)
		"pig_impact":
			if Snapshot._vector(payload.get("at")): game.audio.play_world(game.pig.IMPACT_SOUND, at)
		"tunnel":
			if not Snapshot._integer(payload.get("faction"), 0, game.faction_count - 1) or not Snapshot._integer(payload.get("count"), 1, 50) or not Snapshot._number(payload.get("dig_duration")): return
			for name: String in ["entrance", "exit", "direction"]:
				if not Snapshot._vector(payload.get(name)): return
			game.world_effects.get_node("Rabbit").start_tunnel(int(payload.faction), Snapshot.vector(payload.entrance), Snapshot.vector(payload.exit), Snapshot.vector(payload.direction), int(payload.count), float(payload.dig_duration))
		"capture", "construction", "construction_complete":
			if not Snapshot._integer(payload.get("building"), 0, 2147483647) or not game.by_id.has(int(payload.building)): return
			if event.kind == "capture" and (not Snapshot._number(payload.get("energy_bonus")) or float(payload.energy_bonus) < 0.0 or float(payload.energy_bonus) > game.SKILL_RULES.ENERGY_CAPTURE_REWARD): return
			var building: WarBuilding = game.by_id[int(payload.building)]
			if event.kind == "construction": game.audio.play_world(&"war_rebuild", building.global_position)
			else:
				building.pulse_capture()
				if event.kind == "construction_complete":
					building.get_node("Construction/Complete").show()
					building.get_node("Construction/Complete").restart()
					game.audio.play_world(&"war_upgrade", building.global_position)
				else:
					game.add_effect(building.global_position, game.faction_color(building.faction), "capture", 1.1)
					if payload.get("faction") == game.local_faction:
						game.audio.play_ui(&"war_capture")
					elif payload.get("previous_faction") == game.local_faction: game.audio.play_ui(&"war_lost")
		"dispatch":
			if Snapshot._integer(payload.get("faction"), 0, game.faction_count - 1) and Snapshot._integer(payload.get("target"), 0, 2147483647) and game.by_id.has(int(payload.target)):
				game.present_dispatch(int(payload.faction), game.by_id[int(payload.target)])
		"garrison_blast":
			if not Snapshot._vector(payload.get("at")) or not Snapshot._integer(payload.get("faction"), -1, game.faction_count - 1) or not Snapshot._integer(payload.get("count"), 1, game.world_effects.get_node("BlastCasualties").MAX_BURST): return
			if not Snapshot._number(payload.get("delay")) or float(payload.delay) < 0.0 or float(payload.delay) > 0.18: return
			game.world_effects.get_node("BlastCasualties").burst(at, int(payload.faction), int(payload.count), float(payload.delay))
		"casualty":
			if Snapshot._vector(payload.get("at")) and Snapshot._vector(payload.get("heading")) and Snapshot._vector(payload.get("impulse")) and Snapshot._integer(payload.get("faction"), 0, game.faction_count - 1) and payload.get("burning") is bool:
				game.world_effects.casualty(at, Snapshot.vector(payload.heading), int(payload.faction), Snapshot.vector(payload.impulse), payload.burning)
		"tower_volley":
			if not Snapshot._building_id(payload.get("building"), game) or not Snapshot._vector(payload.get("aim")): return
			var building: WarBuilding = game.by_id[int(payload.building)]
			if building.kind != 1: return
			game.present_tower_volley(building, Snapshot.vector(payload.aim))
		"bear_shot":
			if Snapshot._vector(payload.get("at")): game.world_effects.get_node("Bear").spark(at)
