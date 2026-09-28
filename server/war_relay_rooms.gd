extends RefCounted
## Transport-independent room authority. No gameplay state, map loading or AI.
## All identities are bound to authenticated DTLS connections, never packet fields.

signal outgoing(peer_id: int, message: Dictionary, channel: int, reliable: bool)
signal disconnect_peer(peer_id: int)

const P := preload("res://scripts/network/war_protocol.gd")
const HOST_GRACE_MS := 30000
const BOT_GRACE_MS := 10000
const REJOIN_GRACE_MS := 120000
const LOAD_GRACE_MS := 60000
const LOBBY_IDLE_MS := 900000
const HANDSHAKE_MS := 15000
const HEARTBEAT_MS := 8000

var content_hash: String = ""
var max_rooms := 32
var rooms: Dictionary = {}
var connections: Dictionary = {}
var players: Dictionary = {}
var _tokens: Dictionary = {}
var _next_player := 1
var _crypto := Crypto.new()

func connected(peer: int, now: int) -> void:
	connections[peer] = {"player": -1, "hello": false, "last": now, "created": now, "strikes": 0, "buckets": {}}

func receive(peer: int, message: Dictionary, channel: int, size: int, now: int) -> void:
	if not connections.has(peer): return
	var state: Dictionary = connections[peer]
	var host := _is_host(int(state.player))
	if not _budget(state, "wire", float(size), 1048576.0 if host else 32768.0, 3.0, now) or not _budget(state, "packets", 1, 1000.0 if host else 120.0, 3.0, now):
		_reject(peer, "发送频率超过限制", true)
		return
	if message.is_empty() or not message.get("op") is String:
		_reject(peer, "无效网络消息")
		return
	var op: String = message.op
	if not state.hello:
		if op != "hello" or channel != P.ROOM_CHANNEL or size > P.MAX_CONTROL_BYTES:
			_reject(peer, "请先完成版本握手", true)
			return
		_hello(peer, message, now)
		return
	if op in ["command", "match", "cursor", "presence"]:
		if channel == P.ANCHOR_CHANNEL and size > P.MAX_DATAGRAM_BYTES:
			_reject(peer, "校正包超过无分片大小限制")
			return
		if op != "match" and size > (P.MAX_CURSOR_BYTES if op in ["cursor", "presence"] else P.MAX_CONTROL_BYTES):
			_reject(peer, "消息过大")
			return
	else:
		if channel != P.ROOM_CHANNEL or size > P.MAX_CONTROL_BYTES or not _budget(state, "room", 1, 15.0, 4.0, now):
			_reject(peer, "房间请求无效或过于频繁")
			return
	state.last = now
	if op == "ping":
		_send(peer, {"op": "pong"})
		return
	if op in ["create", "join"]:
		if int(state.player) >= 0:
			_notice(peer, "已在房间中，请先离开")
		elif op == "create": _create(peer, message, now)
		else: _join(peer, message, now)
		return
	var player := int(state.player)
	if not players.has(player):
		_notice(peer, "请先进入房间")
		return
	var session: Dictionary = players[player]
	var room: Dictionary = rooms[session.code]
	if op == "member_ack":
		if message.get("token") == session.token and not str(session.previous_token).is_empty():
			_tokens.erase(session.previous_token)
			session.previous_token = ""
		return
	if op == "leave":
		_leave(player, now)
		return
	if op == "return":
		if player != int(room.host_player_id):
			_notice(peer, "由房主带领大家返回房间")
		elif room.phase in ["match", "finished"]:
			_back_to_lobby(room, now)
		return
	if op == "loaded":
		_loaded(peer, message, room, session, now)
		return
	if op == "recovered":
		_recovered(peer, message, room, now)
		return
	if op == "surrendered":
		_surrendered(peer, message, room, now)
		return
	if op in ["command", "match", "cursor", "presence"]:
		_route(peer, player, message, channel, room, now)
		return
	if room.phase != "room":
		_notice(peer, "战局已锁定，暂时不能修改房间")
		return
	match op:
		"map": _set_map(peer, message, room, now)
		"slot": _set_slot(peer, message, room, now)
		"move": _move(peer, message, room, now)
		"commander": _commander(peer, message, room, now)
		"ready":
			if not message.get("ready") is bool: _reject(peer, "准备状态无效")
			else:
				P.slot_for_player(room, player).ready = message.ready
				_changed(room, now)
		"start": _start(peer, room, now)
		_: _reject(peer, "未知房间请求")

func _hello(peer: int, message: Dictionary, now: int) -> void:
	if not P.integer(message.get("version"), P.VERSION, P.VERSION) or message.get("content_hash") != content_hash or content_hash.is_empty():
		_reject(peer, "客户端与服务器版本或战斗内容不一致，请更新游戏", true)
		return
	var token: Variant = message.get("token", "")
	if not token is String or token.length() > 64:
		_reject(peer, "重连身份无效", true)
		return
	connections[peer].hello = true
	connections[peer].last = now
	if token.is_empty():
		_send(peer, {"op": "welcome", "version": P.VERSION})
		return
	if not _tokens.has(token):
		_reject(peer, "原房间已关闭或重连凭证已失效", true)
		return
	var player := int(_tokens[token])
	var session: Dictionary = players[player]
	var room: Dictionary = rooms[session.code]
	var host := player == int(room.host_player_id)
	if int(session.disconnected_at) >= 0 and now - int(session.disconnected_at) >= (HOST_GRACE_MS if host else REJOIN_GRACE_MS):
		_reject(peer, "重连窗口已结束", true)
		return
	# Replacing an older native connection immediately revokes it; its late
	# DISCONNECT event must not detach the new connection or its control epoch.
	var old_peer := int(session.peer)
	if old_peer != 0 and connections.has(old_peer):
		connections.erase(old_peer)
		disconnect_peer.emit(old_peer)
	# Keep the presented credential valid until the client acknowledges receiving
	# its replacement. If the connection drops before MEMBER arrives, rotating
	# without this acknowledgement would permanently lock out a valid player.
	if not str(session.previous_token).is_empty() and session.previous_token != token:
		_tokens.erase(session.previous_token)
	if session.token != token: _tokens.erase(session.token)
	session.previous_token = token
	session.token = _token()
	_tokens[session.token] = player
	session.peer = peer
	session.disconnected_at = -1
	connections[peer].player = player
	var slot := P.slot_for_player(room, player)
	slot.connected = true
	slot.control_epoch += 1
	var before_battle: bool = _effective_phase(room) in ["room", "loading"]
	slot.controller = "human" if before_battle or host else "reconnecting"
	if host and slot.surrendered: slot.controller = "spectator"
	if host and room.phase == "host_lost":
		room.phase = room.resume_phase
		if room.phase == "loading": room.load_deadline = now + LOAD_GRACE_MS
	# A fast reconnect can replace the old ENet connection before its disconnect
	# timeout fires. It needs the same recovery barrier as an observed Host loss.
	if host and room.phase in ["match", "finished"]:
		for other: Dictionary in room.slots:
			if other.kind == "human" and other.connected and int(other.player_id) != player:
				other.controller = "reconnecting"
				other.control_epoch += 1
	_changed(room, now)
	_member(peer, session, room, true)
	if room.phase == "loading": _check_loaded(room, now)
	if room.phase in ["match", "finished"]:
		if host:
			for other: Dictionary in room.slots:
				if other.kind == "human" and other.connected and int(other.player_id) != player:
					_send(peer, {"op": "recovery", "player_id": other.player_id})
		else: _to_host(room, {"op": "recovery", "player_id": player})

func _create(peer: int, message: Dictionary, now: int) -> void:
	if message.get("map_id") not in P.MAP_SEATS:
		_reject(peer, "地图无效")
		return
	if rooms.size() >= max_rooms:
		_notice(peer, "服务器房间已满，请稍后重试")
		return
	var code := _room_code()
	var session := _new_player(peer, code, message.get("name"))
	var slots: Array[Dictionary] = []
	for index: int in P.MAP_SEATS[message.map_id]: slots.append(_empty_slot(index))
	_fill_human(slots[0], session)
	var room := {"code": code, "revision": 1, "phase": "room", "map_id": message.map_id, "host_player_id": session.player_id, "slots": slots, "updated": now, "match_id": "", "loaded": {}, "load_deadline": 0, "resume_phase": "room"}
	rooms[code] = room
	_member(peer, session, room, false)
	_broadcast_room(room)

func _join(peer: int, message: Dictionary, now: int) -> void:
	if not P.valid_code(message.get("code")) or not rooms.has(message.code):
		_notice(peer, "找不到该房间，请检查六位房间码")
		return
	var room: Dictionary = rooms[message.code]
	if room.phase != "room":
		_notice(peer, "此房间正在对局，仅支持原玩家重连")
		return
	for slot: Dictionary in room.slots:
		if slot.kind == "open":
			var session := _new_player(peer, room.code, message.get("name"))
			_fill_human(slot, session)
			_reset_ready(room)
			_changed(room, now)
			_member(peer, session, room, false)
			return
	_notice(peer, "房间已满，请让房主腾出一个位置")

func _set_map(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	if not _host_only(peer, room): return
	if message.get("map_id") not in P.MAP_SEATS:
		_reject(peer, "地图无效")
		return
	var count: int = P.MAP_SEATS[message.map_id]
	for slot: Dictionary in room.slots:
		if int(slot.slot_id) >= count and slot.kind == "human":
			_notice(peer, "请先让超出新地图的位置中的玩家换位或离开")
			return
	if room.map_id == message.map_id: return
	room.map_id = message.map_id
	while room.slots.size() > count: room.slots.pop_back()
	while room.slots.size() < count: room.slots.append(_empty_slot(room.slots.size()))
	_reset_ready(room)
	_changed(room, now)

func _set_slot(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	if not _host_only(peer, room): return
	if not P.integer(message.get("slot"), 0, room.slots.size() - 1) or message.get("kind") not in ["bot", "open"] or message.get("commander") not in P.COMMANDERS:
		_reject(peer, "位置或角色无效")
		return
	var index := int(message.slot)
	if room.slots[index].kind == "human":
		_notice(peer, "不能覆盖真人的位置")
		return
	room.slots[index] = _empty_slot(index)
	var slot: Dictionary = room.slots[index]
	slot.kind = message.kind
	slot.commander = message.commander
	slot.name = "电脑" if message.kind == "bot" else "空位"
	slot.controller = "bot" if message.kind == "bot" else "open"
	slot.ready = message.kind == "bot"
	_reset_ready(room)
	_changed(room, now)

func _move(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	if not P.integer(message.get("slot"), 0, room.slots.size() - 1):
		_reject(peer, "位置无效")
		return
	var index := int(message.slot)
	var player := int(connections[peer].player)
	var source := P.slot_for_player(room, player)
	if int(source.slot_id) == index: return
	if room.slots[index].kind == "human":
		_notice(peer, "该位置已有玩家")
		return
	# Swapping with a bot is explicit and retains the bot's commander. No
	# player identity depends on seat zero or changes when moving seats.
	var destination: Dictionary = room.slots[index]
	var old_index := int(source.slot_id)
	room.slots[index] = source
	room.slots[old_index] = destination
	_seat(source, index)
	_seat(destination, old_index)
	_reset_ready(room)
	_changed(room, now)

func _commander(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	if message.get("commander") not in P.COMMANDERS:
		_reject(peer, "角色无效")
		return
	P.slot_for_player(room, int(connections[peer].player)).commander = message.commander
	_reset_ready(room)
	_changed(room, now)

func _start(peer: int, room: Dictionary, now: int) -> void:
	if not _host_only(peer, room): return
	for slot: Dictionary in room.slots:
		if slot.kind == "open":
			_notice(peer, "请先用玩家或电脑填满所有位置")
			return
		if slot.kind == "human" and (not slot.ready or not slot.connected):
			_notice(peer, "请等待所有玩家准备，包括房主")
			return
	room.phase = "loading"
	room.match_id = _token().left(32)
	room.loaded = {}
	room.load_deadline = now + LOAD_GRACE_MS
	for slot: Dictionary in room.slots:
		slot.control_epoch += 1
		slot.surrendered = false
		slot.forfeit_requested = false
		if slot.kind == "human":
			slot.controller = "human"
			var session: Dictionary = players[int(slot.player_id)]
			session.cursor_epoch = -1
			session.cursor_seq = -1
			session.cursor_visible = false
	_changed(room, now)
	_broadcast(room, {"op": "preparing", "config": _config(room)})

func _loaded(peer: int, message: Dictionary, room: Dictionary, session: Dictionary, now: int) -> void:
	if _effective_phase(room) != "loading" or message.get("match_id") != room.match_id or message.get("content_hash") != content_hash: return
	room.loaded[session.player_id] = true
	# A client may finish loading while Host is offline. Persist that one-shot
	# acknowledgement, but only the Host's return may release the barrier.
	if room.phase == "loading": _check_loaded(room, now)

func _check_loaded(room: Dictionary, now: int) -> void:
	for slot: Dictionary in room.slots:
		if slot.kind == "human" and (not slot.connected or not room.loaded.has(slot.player_id)): return
	room.phase = "match"
	_changed(room, now)
	_broadcast(room, {"op": "started", "config": _config(room)})

func _recovered(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	if not _host_only(peer, room) or room.phase not in ["match", "finished"] or message.get("match_id") != room.match_id: return
	if not P.integer(message.get("player_id"), 1) or not P.integer(message.get("epoch"), 0): return
	var slot := P.slot_for_player(room, int(message.player_id))
	if slot.is_empty() or not slot.connected or slot.controller != "reconnecting" or message.epoch != slot.control_epoch: return
	slot.controller = "spectator" if slot.surrendered else "human"
	slot.control_epoch += 1
	_changed(room, now)

func _surrendered(peer: int, message: Dictionary, room: Dictionary, now: int) -> void:
	# Host commits the game rule first. Relay only persists the resulting loss of
	# input permission; it never decides transfers, penalties or victory.
	if not _host_only(peer, room) or room.phase not in ["match", "finished"] or message.get("match_id") != room.match_id: return
	if not P.integer(message.get("player_id"), 1): return
	var slot := P.slot_for_player(room, int(message.player_id))
	if slot.is_empty() or slot.surrendered: return
	slot.surrendered = true
	players[int(slot.player_id)].cursor_visible = false
	# A recovering peer already has no control. Preserve its baseline epoch so
	# restoring this permission flag cannot invalidate an in-flight snapshot.
	if slot.controller != "reconnecting":
		slot.controller = "spectator"
		slot.control_epoch += 1
	if slot.forfeit_requested:
		_remove_player(int(slot.player_id))
		_replace_departed(slot, true)
	_changed(room, now)

func _route(peer: int, player: int, message: Dictionary, channel: int, room: Dictionary, now: int) -> void:
	if message.get("match_id") != room.match_id or room.match_id.is_empty(): return
	if room.phase not in ["match", "finished"]: return
	var slot := P.slot_for_player(room, player)
	var op: String = message.op
	if op in ["cursor", "presence"]:
		_cursor(peer, player, message, channel, room, slot, now)
		return
	if op == "command":
		if channel != P.COMMAND_CHANNEL or not message.get("payload") is Dictionary:
			_reject(peer, "指令通道或内容无效")
			return
		if slot.controller != "human" or slot.surrendered or room.phase != "match": return
		if not _budget(connections[peer], "command", 1, 40.0, 4.0, now):
			_notice(peer, "操作过于频繁，请稍后重试")
			return
		_to_host(room, {"op": "match", "match_id": room.match_id, "sender": player, "kind": "command", "payload": message.payload}, P.COMMAND_CHANNEL)
		return
	var kind: Variant = message.get("kind")
	if not kind is String or not message.get("payload") is Dictionary or not message.get("reliable") is bool or not P.valid_match_channel(kind, channel, message.reliable):
		_reject(peer, "战斗消息格式或通道无效")
		return
	var forwarded := {"op": "match", "match_id": room.match_id, "sender": player, "kind": kind, "payload": message.payload}
	if player != int(room.host_player_id):
		if kind not in P.CLIENT_KINDS:
			_reject(peer, "仅房主可发送战斗结果")
			return
		if not _budget(connections[peer], "ack", 1, 30.0, 4.0, now): return
		_to_host(room, forwarded, channel)
		return
	if kind not in P.HOST_KINDS or not P.integer(message.get("to"), -1):
		_reject(peer, "战斗消息类型或目标无效")
		return
	var target := int(message.to)
	if target == -1:
		_broadcast(room, forwarded, channel, message.reliable, player)
	else:
		var destination := P.slot_for_player(room, target)
		if not destination.is_empty() and destination.connected and target != player:
			_send(int(players[target].peer), forwarded, channel, message.reliable)
	if kind == "finished" and room.phase == "match":
		room.phase = "finished"
		_changed(room, now)

func _cursor(peer: int, player: int, message: Dictionary, channel: int, room: Dictionary, slot: Dictionary, now: int) -> void:
	var presence: bool = message.op == "presence"
	if channel != (P.ROOM_CHANNEL if presence else P.CURSOR_CHANNEL) or not P.valid_cursor(message.get("payload")):
		_reject(peer, "鼠标消息无效")
		return
	if room.phase != "match" or message.get("room_revision") != room.revision or slot.controller != "human" or slot.surrendered: return
	if not _budget(connections[peer], "cursor", 1, 40.0, 3.0, now): return
	var payload: Dictionary = message.payload
	var session: Dictionary = players[player]
	var epoch := int(payload.presence_epoch)
	var sequence := int(payload.cursor_seq)
	if epoch < int(session.cursor_epoch) or (epoch == int(session.cursor_epoch) and sequence <= int(session.cursor_seq)): return
	# A newer unreliable move must never preempt a reliable hide of the same
	# epoch. Presence changes increment epoch at the sender and lock visibility.
	if epoch == int(session.cursor_epoch) and session.cursor_visible != payload.visible: return
	session.cursor_epoch = epoch
	session.cursor_seq = sequence
	session.cursor_visible = payload.visible
	var forwarded := {"op": "cursor", "match_id": room.match_id, "room_revision": room.revision, "sender": player, "payload": payload}
	for destination: Dictionary in room.slots:
		if destination.kind == "human" and destination.connected and int(destination.player_id) != player and destination.team_id == slot.team_id:
			_send(int(players[int(destination.player_id)].peer), forwarded, P.ROOM_CHANNEL if presence else P.CURSOR_CHANNEL, presence)

func disconnected(peer: int, now: int) -> void:
	if not connections.has(peer): return
	var player := int(connections[peer].player)
	connections.erase(peer)
	if not players.has(player) or int(players[player].peer) != peer: return
	var session: Dictionary = players[player]
	session.peer = 0
	session.disconnected_at = now
	var room: Dictionary = rooms[session.code]
	var slot := P.slot_for_player(room, player)
	slot.connected = false
	slot.ready = false
	slot.controller = "reconnecting"
	slot.control_epoch += 1
	if player == int(room.host_player_id):
		room.resume_phase = room.phase
		room.phase = "host_lost"
	_changed(room, now)

func tick(now: int) -> void:
	for peer: int in connections.keys():
		var state: Dictionary = connections[peer]
		if (not state.hello and now - int(state.created) >= HANDSHAKE_MS) or (state.hello and now - int(state.last) >= HEARTBEAT_MS):
			disconnected(peer, now)
			disconnect_peer.emit(peer)
	for code: String in rooms.keys():
		var room: Dictionary = rooms[code]
		var host: Dictionary = players[int(room.host_player_id)]
		if int(host.disconnected_at) >= 0 and now - int(host.disconnected_at) >= HOST_GRACE_MS:
			_close_room(room, "房主未在30秒内恢复连接，对局已结束")
			continue
		if room.phase == "room" and now - int(room.updated) >= LOBBY_IDLE_MS:
			_close_room(room, "房间长时间未操作，已关闭")
			continue
		if room.phase == "loading" and now >= int(room.load_deadline):
			_broadcast(room, {"op": "error", "message": "有玩家未能在60秒内加载完成，已返回房间", "fatal": false})
			_back_to_lobby(room, now)
		for slot: Dictionary in room.slots:
			if slot.kind != "human" or slot.connected or int(slot.player_id) == int(room.host_player_id): continue
			# LEAVE is a durable Host-side forfeit, not a disconnected participant.
			# Its identity survives until the authority commits that game rule.
			if slot.forfeit_requested: continue
			var session: Dictionary = players[int(slot.player_id)]
			var age := now - int(session.disconnected_at)
			if age >= REJOIN_GRACE_MS:
				_remove_player(int(slot.player_id))
				_replace_departed(slot, _effective_phase(room) != "room")
				_changed(room, now)
			elif age >= BOT_GRACE_MS and not slot.surrendered and slot.controller != "bot" and _effective_phase(room) == "match":
				slot.controller = "bot"
				slot.control_epoch += 1
				_changed(room, now)

func _leave(player: int, now: int) -> void:
	var session: Dictionary = players[player]
	var room: Dictionary = rooms[session.code]
	if player == int(room.host_player_id):
		_close_room(room, "房主已离开，房间已关闭")
		return
	var peer := int(session.peer)
	var slot := P.slot_for_player(room, player)
	var active_battle := _effective_phase(room) == "match"
	if active_battle and not slot.surrendered:
		# A player can close this transport or enter another room immediately,
		# while the old match retains a durable request for its authority.
		_detach_player(session)
		slot.forfeit_requested = true
		slot.connected = false
		slot.ready = false
		slot.controller = "spectator"
		slot.control_epoch += 1
		_changed(room, now)
		_send(peer, {"op": "left"})
		return
	_remove_player(player)
	_replace_departed(slot, _effective_phase(room) != "room")
	_reset_ready(room)
	_changed(room, now)
	_send(peer, {"op": "left"})
	if room.phase == "loading":
		# Recheck the barrier after replacing a voluntarily departed human.
		_check_loaded(room, now)

func _back_to_lobby(room: Dictionary, now: int) -> void:
	room.phase = "room"
	room.match_id = ""
	room.loaded = {}
	for slot: Dictionary in room.slots:
		if slot.forfeit_requested:
			_remove_player(int(slot.player_id))
			_replace_departed(slot, true)
		slot.control_epoch += 1
		slot.surrendered = false
		slot.forfeit_requested = false
		if slot.kind == "human": slot.controller = "human" if slot.connected else "reconnecting"
		else:
			slot.controller = slot.kind
			slot.name = "电脑" if slot.kind == "bot" else "空位"
	_reset_ready(room)
	_changed(room, now)

func _effective_phase(room: Dictionary) -> String:
	# Host loss wraps lobby, loading, battle and results alike. Lifecycle rules
	# must use the suspended phase rather than treating every wrapper as battle.
	return room.resume_phase if room.phase == "host_lost" else room.phase

func _close_room(room: Dictionary, reason: String) -> void:
	_broadcast(room, {"op": "closed", "message": reason})
	for slot: Dictionary in room.slots:
		if slot.kind == "human": _remove_player(int(slot.player_id))
	rooms.erase(room.code)

func _new_player(peer: int, code: String, name: Variant) -> Dictionary:
	var session := {"player_id": _next_player, "peer": peer, "code": code, "name": P.nickname(name), "token": _token(), "previous_token": "", "disconnected_at": -1, "cursor_epoch": -1, "cursor_seq": -1, "cursor_visible": false}
	_next_player += 1
	players[session.player_id] = session
	_tokens[session.token] = session.player_id
	connections[peer].player = session.player_id
	return session

func _remove_player(player: int) -> void:
	var session: Dictionary = players[player]
	_detach_player(session)
	players.erase(player)

func _detach_player(session: Dictionary) -> void:
	if connections.has(int(session.peer)): connections[int(session.peer)].player = -1
	_tokens.erase(session.token)
	if not str(session.previous_token).is_empty(): _tokens.erase(session.previous_token)
	session.peer = 0
	session.token = ""
	session.previous_token = ""
	session.disconnected_at = -1
	session.cursor_visible = false

func _member(peer: int, session: Dictionary, room: Dictionary, resumed: bool) -> void:
	_send(peer, {"op": "member", "player_id": session.player_id, "token": session.token, "room": _public_room(room), "config": _config(room) if not room.match_id.is_empty() else {}, "resumed": resumed})

func _empty_slot(index: int) -> Dictionary:
	return {"slot_id": index, "faction_id": index, "team_id": index % 2, "player_id": -1, "kind": "open", "commander": "squirrel", "name": "空位", "ready": false, "connected": false, "controller": "open", "control_epoch": 0, "surrendered": false, "forfeit_requested": false}

func _seat(slot: Dictionary, index: int) -> void:
	slot.slot_id = index
	slot.faction_id = index
	slot.team_id = index % 2
	slot.control_epoch += 1

func _fill_human(slot: Dictionary, session: Dictionary) -> void:
	slot.player_id = session.player_id
	slot.kind = "human"
	slot.name = session.name
	slot.connected = true
	slot.controller = "human"
	slot.surrendered = false
	slot.forfeit_requested = false
	slot.control_epoch += 1

func _replace_departed(slot: Dictionary, bot: bool) -> void:
	slot.kind = "bot" if bot else "open"
	# Expiry/LEAVE releases the identity, never resurrecting a surrendered army.
	slot.surrendered = slot.surrendered and bot
	slot.forfeit_requested = false
	slot.controller = "spectator" if slot.surrendered else slot.kind
	slot.name = "已投降" if slot.surrendered else ("电脑" if bot else "空位")
	slot.player_id = -1
	slot.connected = false
	slot.ready = bot
	slot.control_epoch += 1

func _reset_ready(room: Dictionary) -> void:
	for slot: Dictionary in room.slots:
		if slot.kind == "human": slot.ready = false

func _changed(room: Dictionary, now: int) -> void:
	room.revision += 1
	room.updated = now
	_broadcast_room(room)

func _public_room(room: Dictionary) -> Dictionary:
	return {"code": room.code, "revision": room.revision, "phase": room.phase, "map_id": room.map_id, "host_player_id": room.host_player_id, "slots": room.slots.duplicate(true)}

func _config(room: Dictionary) -> Dictionary:
	var config := _public_room(room)
	config.match_id = room.match_id
	config.content_hash = content_hash
	return config

func _broadcast_room(room: Dictionary) -> void:
	_broadcast(room, {"op": "room", "room": _public_room(room)})

func _broadcast(room: Dictionary, message: Dictionary, channel: int = 0, reliable: bool = true, except_player: int = -1) -> void:
	for slot: Dictionary in room.slots:
		if slot.kind == "human" and slot.connected and int(slot.player_id) != except_player:
			_send(int(players[int(slot.player_id)].peer), message, channel, reliable)

func _to_host(room: Dictionary, message: Dictionary, channel: int = 0) -> void:
	var host: Dictionary = players[int(room.host_player_id)]
	if int(host.peer) != 0: _send(int(host.peer), message, channel)

func _host_only(peer: int, room: Dictionary) -> bool:
	if int(connections[peer].player) == int(room.host_player_id): return true
	_reject(peer, "只有房主能执行此操作")
	return false

func _is_host(player: int) -> bool:
	return players.has(player) and int(rooms[players[player].code].host_player_id) == player

func _send(peer: int, message: Dictionary, channel: int = 0, reliable: bool = true) -> void:
	if peer != 0: outgoing.emit(peer, message, channel, reliable)

func _notice(peer: int, message: String) -> void:
	_send(peer, {"op": "error", "message": message, "fatal": false})

func _reject(peer: int, message: String, fatal: bool = false) -> void:
	connections[peer].strikes += 1
	fatal = fatal or int(connections[peer].strikes) >= 8
	_send(peer, {"op": "error", "message": message, "fatal": fatal})
	if fatal:
		disconnected(peer, Time.get_ticks_msec())
		disconnect_peer.emit(peer)

func _budget(state: Dictionary, name: String, amount: float, rate: float, burst_seconds: float, now: int) -> bool:
	var buckets: Dictionary = state.buckets
	var bucket: Dictionary = buckets.get(name, {"tokens": rate * burst_seconds, "at": now})
	bucket.tokens = minf(rate * burst_seconds, float(bucket.tokens) + maxf(0.0, float(now - int(bucket.at))) * rate / 1000.0)
	bucket.at = now
	buckets[name] = bucket
	if float(bucket.tokens) < amount: return false
	bucket.tokens -= amount
	return true

func _token() -> String:
	return _crypto.generate_random_bytes(32).hex_encode()

func _room_code() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	while true:
		var code := ""
		for byte: int in _crypto.generate_random_bytes(6): code += ALPHABET[byte % ALPHABET.length()]
		if not rooms.has(code): return code
	return ""
