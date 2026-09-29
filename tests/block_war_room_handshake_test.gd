extends SceneTree
## Exercise the real room UI around the synchronous welcome/state signal boundary.

const Rooms := preload("res://server/war_relay_rooms.gd")
const P := preload("res://scripts/network/war_protocol.gd")
const ROOM_SCENE := preload("res://scenes/network/war_room.tscn")
var failures: Array[String] = []
var checks := 0

class CapturedOnline:
	extends "res://scripts/network/war_online.gd"
	var sent: Array[Dictionary] = []
	func connect_relay(_endpoint: String = DEFAULT_ADDRESS, _port: int = P.PORT) -> Error:
		_set_state("connecting")
		return OK
	func _send(message: Dictionary, _channel: int = 0, _reliable: bool = true) -> void:
		sent.append(message.duplicate(true))

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var session: Node = root.get_node("Session")
	var original: Node = session.online
	for action: String in ["create", "join"]:
		_check_room_request(session, action, false)
		_check_room_request(session, action, true)
	_check_queued_request()
	session.online = original
	print("ROOM HANDSHAKE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_room_request(session: Node, action: String, reconnect: bool) -> void:
	var model := Rooms.new()
	model.content_hash = "room-handshake-test"
	var replies: Array[Dictionary] = []
	model.outgoing.connect(func(peer: int, message: Dictionary, _channel: int, _reliable: bool):
		if peer == 2: replies.append(message.duplicate(true)))
	if action == "join":
		_handshake(model, 1)
		model.receive(1, {"op": "create", "map_id": "rift", "name": "Host"}, 0, 100, 1)
	_handshake(model, 2)
	replies.clear()
	var online := CapturedOnline.new()
	online.content_hash = model.content_hash
	root.add_child(online)
	online.set_process(false)
	session.online = online
	var room: Control = ROOM_SCENE.instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process(false)
	room.get_node("%Nickname").text = "Guest"
	if action == "join": room.get_node("%RoomCode").text = str(model.rooms.keys()[0])
	room._request(action)
	check(online.sent.is_empty(), "%s waits for a welcome before sending membership" % action)
	online._receive({"op": "welcome"}, P.ROOM_CHANNEL, 2)
	# Lose the first request before it reaches Relay; Room and Online both retain
	# their intent while the new transport performs another welcome handshake.
	if reconnect:
		online.sent.clear()
		online._close_transport()
		online._set_state("reconnecting")
		online._receive({"op": "welcome"}, P.ROOM_CHANNEL, 2)
	var label := action + (" after reconnect" if reconnect else "")
	var requests := online.sent.duplicate(true)
	check(requests.size() == 1 and requests[0].op == action, "%s sends exactly one request after welcome" % label)
	for message: Dictionary in requests: model.receive(2, message, P.ROOM_CHANNEL, 100, 3)
	check(not replies.any(func(message: Dictionary): return message.op == "error"), "%s receives no duplicate-membership notice" % label)
	for message: Dictionary in replies: online._receive(message, P.ROOM_CHANNEL, 4)
	check(not online.room.is_empty() and room.get_node("%Room").visible, "%s enters the room" % action)
	check(room.get_node("%Message").text.is_empty(), "%s shows no error after successful entry" % label)
	check(not room.get_node("%Create").disabled and not room.get_node("%Join").disabled, "%s releases the entry controls" % action)
	room.free()
	online.free()

func _check_queued_request() -> void:
	var online := CapturedOnline.new()
	online.content_hash = "room-handshake-test"
	root.add_child(online)
	online.set_process(false)
	online.connection_state = "connecting"
	online.create_room("rift", "Queued")
	check(online.sent.is_empty(), "an API request before welcome remains queued")
	online._receive({"op": "welcome"}, P.ROOM_CHANNEL, 0)
	check(online.sent.size() == 1 and online.sent[0].op == "create", "welcome flushes a preexisting API request once")
	online.free()

func _handshake(model: RefCounted, peer: int) -> void:
	model.connected(peer, 0)
	model.receive(peer, {"op": "hello", "version": P.VERSION, "content_hash": model.content_hash, "token": ""}, P.ROOM_CHANNEL, 100, 0)
