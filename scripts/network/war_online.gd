extends Node
## Native encrypted Relay transport. Session owns this authored node across scenes.

signal room_changed(room: Dictionary)
signal match_preparing(config: Dictionary)
signal match_started(config: Dictionary)
signal match_message(sender_player: int, kind: String, payload: Dictionary)
signal cursor_received(sender_player: int, payload: Dictionary)
signal state_changed(state: String)
signal error_received(message: String)
signal recovery_requested(player_id: int)

const P := preload("res://scripts/network/war_protocol.gd")
const DEFAULT_ADDRESS := "8.211.149.193"
const CERTIFICATE_PATH := "res://scripts/network/relay_trust.crt"
const INITIAL_CONNECT_MS := 20000
const SILENCE_MS := 6000
const MAX_BULK_QUEUE_BYTES := 8388608
const BULK_BYTES_PER_SECOND := 262144.0
const BULK_BURST_BYTES := 65536.0

var room: Dictionary = {}
var match_config: Dictionary = {}
var player_id := -1
var local_faction := -1
var is_host := false
var connection_state := "disconnected"
var certificate_path := CERTIFICATE_PATH
var tls_name := P.TLS_NAME
var content_hash: String = ""
var auto_reconnect := true
var address := DEFAULT_ADDRESS
var port := P.PORT
var sent_bytes := 0
var received_bytes := 0

var _connection: ENetConnection
var _peer: ENetPacketPeer
var _closing: Array[Dictionary] = []
var _token := ""
var _intent: Dictionary = {}
var _hello := false
var _connecting_at := 0
var _last_received := 0
var _heartbeat_at := 0
var _retry_at := 0
var _reconnect_deadline := 0
var _bulk_queue: Array[PackedByteArray] = []
var _bulk_bytes := 0
var _bulk_tokens := BULK_BURST_BYTES
var _last_presence := -1
var _pending_recovery: Array[int] = []
var _loaded_match_id := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if content_hash.is_empty(): content_hash = P.content_hash()

func connect_relay(endpoint: String = DEFAULT_ADDRESS, endpoint_port: int = P.PORT) -> Error:
	disconnect_relay()
	address = endpoint.strip_edges()
	port = endpoint_port
	if address.is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if content_hash.is_empty(): content_hash = P.content_hash()
	if content_hash.is_empty():
		error_received.emit("缺少战斗内容清单，请重新安装当前版本")
		return ERR_FILE_NOT_FOUND
	_reconnect_deadline = Time.get_ticks_msec() + INITIAL_CONNECT_MS
	return _open()

func _open() -> Error:
	_close_transport()
	var certificate := X509Certificate.new()
	var result := certificate.load(certificate_path)
	if result != OK:
		_fail("无法读取受信中继证书")
		return result
	_connection = ENetConnection.new()
	result = _connection.create_host(1, P.CHANNEL_COUNT)
	if result == OK:
		result = _connection.dtls_client_setup(tls_name, TLSOptions.client(certificate, tls_name))
	if result != OK:
		_fail("无法创建加密网络连接")
		return result
	_peer = _connection.connect_to_host(address, port, P.CHANNEL_COUNT)
	if _peer == null:
		_fail("无法连接中继服务器")
		return ERR_CANT_CONNECT
	_peer.set_timeout(8, 2000, 5000)
	_peer.ping_interval(500)
	_connecting_at = Time.get_ticks_msec()
	_last_received = _connecting_at
	_hello = false
	_set_state("connecting" if _token.is_empty() else "reconnecting")
	return OK

func create_room(map_id: String, nickname: String) -> void:
	_intent = {"op": "create", "map_id": map_id, "name": P.nickname(nickname)}
	_flush_intent()

func join_room(code: String, nickname: String) -> void:
	_intent = {"op": "join", "code": code.strip_edges().to_upper(), "name": P.nickname(nickname)}
	_flush_intent()

func set_map(map_id: String) -> void:
	_send({"op": "map", "map_id": map_id})

func set_slot(slot: int, kind: String, commander: String) -> void:
	_send({"op": "slot", "slot": slot, "kind": kind, "commander": commander})

func move_to_slot(slot: int) -> void:
	_send({"op": "move", "slot": slot})

func choose_commander(commander: String) -> void:
	_send({"op": "commander", "commander": commander})

func set_ready(value: bool) -> void:
	_send({"op": "ready", "ready": value})

func start_match() -> void:
	_send({"op": "start"})

func loaded() -> void:
	if not match_config.is_empty():
		_loaded_match_id = str(match_config.match_id)
		_send({"op": "loaded", "match_id": match_config.match_id, "content_hash": content_hash})
	# Recovery requests can arrive in the same service batch as a scene change.
	# Deliver once the gameplay coordinator has installed its signal listeners.
	for player: int in _pending_recovery: recovery_requested.emit(player)
	_pending_recovery.clear()

func leave_room() -> void:
	_intent.clear()
	_send({"op": "leave"})
	if _connection != null: _connection.flush()
	_clear_membership()
	_set_state("connected" if _hello else "disconnected")

func return_to_room() -> void:
	_send({"op": "return"})

func send_command(payload: Dictionary) -> void:
	if connection_state != "match" or match_config.is_empty(): return
	var slot := P.slot_for_player(room, player_id)
	if slot.is_empty() or slot.controller != "human" or slot.surrendered: return
	_send({"op": "command", "match_id": match_config.match_id, "payload": payload}, P.COMMAND_CHANNEL)

func send_match(kind: String, payload: Dictionary, to_player: int = -1, channel: int = P.EVENT_CHANNEL, reliable: bool = true) -> void:
	if match_config.is_empty() or connection_state not in ["match", "finished"]: return
	if (is_host and kind not in P.HOST_KINDS) or (not is_host and kind not in P.CLIENT_KINDS):
		error_received.emit("战斗消息权限无效")
		return
	if not P.valid_match_channel(kind, channel, reliable):
		error_received.emit("战斗消息通道无效：%s" % kind)
		return
	var message := {"op": "match", "match_id": match_config.match_id, "kind": kind, "payload": payload, "to": to_player, "reliable": reliable}
	_send(message, channel, reliable)

func send_cursor(payload: Dictionary) -> void:
	if connection_state != "match" or match_config.is_empty() or not P.valid_cursor(payload): return
	var slot := P.slot_for_player(room, player_id)
	if slot.is_empty() or slot.controller != "human" or slot.surrendered: return
	var changed := int(payload.presence_epoch) != _last_presence
	_last_presence = int(payload.presence_epoch)
	_send({"op": "presence" if changed else "cursor", "match_id": match_config.match_id, "room_revision": room.revision, "payload": payload}, P.ROOM_CHANNEL if changed else P.CURSOR_CHANNEL, changed)

func complete_recovery(player: int, recovery_epoch: int) -> void:
	if not is_host or match_config.is_empty(): return
	_send({"op": "recovered", "match_id": match_config.match_id, "player_id": player, "epoch": recovery_epoch})

func confirm_surrender(player: int) -> void:
	if not is_host or match_config.is_empty(): return
	_send({"op": "surrendered", "match_id": match_config.match_id, "player_id": player})

func disconnect_relay() -> void:
	if _peer != null and _hello:
		_send({"op": "leave"})
		_connection.flush()
		_peer.peer_disconnect_later()
		_closing.append({"connection": _connection, "deadline": Time.get_ticks_msec() + 3000})
		_connection = null
		_peer = null
	else: _close_transport()
	_clear_membership()
	_intent.clear()
	_retry_at = 0
	_reconnect_deadline = 0
	_hello = false
	_set_state("disconnected")

func abort_connection(reason: String) -> void:
	# Finish the reliable LEAVE handshake so a local replication-budget failure
	# does not strand the other players in a needless Host reconnect timeout.
	disconnect_relay()
	room_changed.emit(room)
	error_received.emit(reason)

func _exit_tree() -> void:
	_close_transport()
	for closing: Dictionary in _closing: closing.connection.destroy()
	_closing.clear()

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for index: int in range(_closing.size() - 1, -1, -1):
		var closing: Dictionary = _closing[index]
		for _packet: int in 32:
			if int(closing.connection.service(0)[0]) == ENetConnection.EVENT_NONE: break
		closing.connection.flush()
		if now >= int(closing.deadline) or closing.connection.get_peers().is_empty():
			closing.connection.destroy()
			_closing.remove_at(index)
	if _connection != null:
		for _index: int in 512:
			var event := _connection.service(0)
			match int(event[0]):
				ENetConnection.EVENT_NONE: break
				ENetConnection.EVENT_CONNECT:
					_peer.throttle_configure(500, 4, 1)
					_send({"op": "hello", "version": P.VERSION, "content_hash": content_hash, "token": _token})
				ENetConnection.EVENT_RECEIVE:
					var bytes: PackedByteArray = _peer.get_packet()
					received_bytes += bytes.size()
					_receive(P.decode(bytes), int(event[3]), now)
				ENetConnection.EVENT_DISCONNECT, ENetConnection.EVENT_ERROR:
					_lost(now)
			if _connection == null: break
		if _connection != null:
			if now - _last_received > SILENCE_MS: _lost(now)
			elif _hello:
				if now >= _heartbeat_at:
					_heartbeat_at = now + 1000
					_send({"op": "ping"})
				_bulk_tokens = minf(BULK_BURST_BYTES, _bulk_tokens + maxf(0.0, delta) * BULK_BYTES_PER_SECOND)
				while _connection != null and not _bulk_queue.is_empty() and _bulk_tokens >= _bulk_queue[0].size():
					var packet: PackedByteArray = _bulk_queue.pop_front()
					_bulk_bytes -= packet.size()
					_bulk_tokens -= packet.size()
					_send_packet(packet, P.SNAPSHOT_CHANNEL, true)
				if _connection != null: _connection.flush()
	if _retry_at != 0 and now >= _retry_at:
		_retry_at = 0
		if now >= _reconnect_deadline:
			_fail("重连窗口已结束，房间可能已经关闭")
		else: _open()

func _receive(message: Dictionary, channel: int, now: int) -> void:
	if message.is_empty():
		_fail("中继返回了无效消息")
		return
	_last_received = now
	var op: String = str(message.get("op", ""))
	if op in ["welcome", "member", "room", "preparing", "started", "recovery", "error", "closed", "left", "pong"] and channel != P.ROOM_CHANNEL:
		_fail("中继控制通道无效")
		return
	match op:
		"welcome":
			_hello = true
			_reconnect_deadline = 0
			_set_state("connected")
			_flush_intent()
		"member":
			_hello = true
			_token = message.token
			player_id = int(message.player_id)
			_send({"op": "member_ack", "token": _token})
			_reconnect_deadline = 0
			_intent.clear()
			var previous_match := str(match_config.get("match_id", ""))
			match_config = message.config
			_install_room(message.room)
			if not match_config.is_empty() and previous_match != str(match_config.match_id):
				match_preparing.emit(match_config)
			elif room.get("phase") == "loading" and not match_config.is_empty() and _loaded_match_id == str(match_config.match_id):
				loaded()
		"room": _install_room(message.room)
		"preparing":
			match_config = message.config
			_loaded_match_id = ""
			_last_presence = -1
			match_preparing.emit(match_config)
		"started":
			match_config = message.config
			_set_state("match")
			match_started.emit(match_config)
		"recovery":
			var player := int(message.player_id)
			if recovery_requested.get_connections().is_empty():
				if player not in _pending_recovery: _pending_recovery.append(player)
			else: recovery_requested.emit(player)
		"match":
			if match_config.is_empty() or message.get("match_id") != match_config.match_id: return
			var sender := int(message.get("sender", -1))
			var kind := str(message.get("kind", ""))
			if channel != (P.COMMAND_CHANNEL if kind == "command" else P.match_channel(kind)): return
			if kind in P.HOST_KINDS and sender != int(room.host_player_id): return
			if kind not in P.HOST_KINDS and (not is_host or kind not in P.CLIENT_KINDS + ["command"]): return
			if message.get("payload") is Dictionary: match_message.emit(sender, kind, message.payload)
		"cursor":
			if channel not in [P.ROOM_CHANNEL, P.CURSOR_CHANNEL] or match_config.is_empty() or message.get("match_id") != match_config.match_id or message.get("room_revision") != room.revision: return
			var sender := int(message.get("sender", -1))
			var other := P.slot_for_player(room, sender)
			var own := P.slot_for_player(room, player_id)
			if other.is_empty() or own.is_empty() or other.team_id != own.team_id or sender == player_id or not other.connected or other.controller != "human" or other.surrendered or not P.valid_cursor(message.get("payload")): return
			var payload: Dictionary = message.payload.duplicate()
			payload.room_revision = room.revision
			cursor_received.emit(sender, payload)
		"closed":
			_clear_membership()
			_set_state("connected")
			room_changed.emit(room)
			error_received.emit(str(message.message))
		"left":
			_clear_membership()
			_set_state("connected")
			room_changed.emit(room)
		"error":
			if message.get("fatal") == true: _fail(str(message.message))
			else: error_received.emit(str(message.message))

func _install_room(value: Dictionary) -> void:
	if player_id < 0: return
	if not room.is_empty() and room.code == value.code and int(value.revision) < int(room.revision): return
	room = value
	is_host = player_id == int(room.host_player_id)
	var slot := P.slot_for_player(room, player_id)
	local_faction = int(slot.faction_id) if not slot.is_empty() else -1
	if room.phase == "room":
		match_config = {}
		_loaded_match_id = ""
		_bulk_queue.clear()
		_bulk_bytes = 0
		_last_presence = -1
	elif not match_config.is_empty():
		match_config.slots = room.slots.duplicate(true)
		match_config.revision = room.revision
		match_config.phase = room.phase
	_set_state(str(room.phase))
	room_changed.emit(room)

func _flush_intent() -> void:
	if _hello and not _intent.is_empty() and player_id < 0:
		_send(_intent)

func _send(message: Dictionary, channel: int = P.ROOM_CHANNEL, reliable: bool = true) -> void:
	if _peer == null or not _peer.is_active() or _peer.get_state() != ENetPacketPeer.STATE_CONNECTED: return
	var packet := P.encode(message)
	if packet.is_empty():
		error_received.emit("网络消息超出安全大小或包含无效内容")
		return
	if not reliable and packet.size() > P.MAX_DATAGRAM_BYTES:
		error_received.emit("不可靠网络消息超过1200字节，请拆分校正数据")
		return
	if channel == P.SNAPSHOT_CHANNEL:
		if _bulk_bytes + packet.size() > MAX_BULK_QUEUE_BYTES:
			_fail("恢复数据积压超限，请重新连接")
			return
		_bulk_queue.append(packet)
		_bulk_bytes += packet.size()
	else: _send_packet(packet, channel, reliable)

func _send_packet(packet: PackedByteArray, channel: int, reliable: bool) -> void:
	var result := _peer.send(channel, packet, ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED)
	if result == OK: sent_bytes += packet.size()
	elif reliable: _lost(Time.get_ticks_msec())

func _lost(now: int) -> void:
	_close_transport()
	if not auto_reconnect:
		_set_state("disconnected")
		return
	if _reconnect_deadline == 0:
		_reconnect_deadline = now + (30000 if is_host else (120000 if not _token.is_empty() else INITIAL_CONNECT_MS))
	if now >= _reconnect_deadline:
		_fail("连接中断，重连窗口已结束")
		return
	_retry_at = now + 750
	_set_state("reconnecting")

func _fail(message: String) -> void:
	_close_transport()
	_clear_membership()
	_retry_at = 0
	_reconnect_deadline = 0
	_set_state("disconnected")
	room_changed.emit(room)
	error_received.emit(message)

func _clear_membership() -> void:
	_token = ""
	room = {}
	match_config = {}
	player_id = -1
	local_faction = -1
	is_host = false
	_bulk_queue.clear()
	_bulk_bytes = 0
	_last_presence = -1
	_pending_recovery.clear()
	_loaded_match_id = ""

func _close_transport() -> void:
	if _connection != null: _connection.destroy()
	_connection = null
	_peer = null
	_hello = false
	_bulk_queue.clear()
	_bulk_bytes = 0

func _set_state(value: String) -> void:
	if connection_state == value: return
	connection_state = value
	state_changed.emit(value)
