extends SceneTree
## Independent native ENet sockets using real DTLS, room traffic and all channels.
## Test-only certificate/key are generated under ignored .local, never shipped.

const Relay := preload("res://server/war_relay_server.gd")
const Online := preload("res://scripts/network/war_online.gd")
const P := preload("res://scripts/network/war_protocol.gd")
const DIRECTORY := "res://.local/network-tests"
var server: Node
var clients: Array[Node] = []
var inbox: Array[Dictionary] = []
var cursors: Array[Dictionary] = []
var recoveries: Array[int] = []
var errors: Array[String] = []
var failures: Array[String] = []
var checks := 0
var test_content := "native-test-content"
var test_certificate := DIRECTORY + "/test-relay.crt"
var endpoint: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func until(predicate: Callable, description: String, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var passed: bool = predicate.call()
	check(passed, description)
	return passed

func pause(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _certificate() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var certificate := crypto.generate_self_signed_certificate(key, "CN=%s,O=Block Conquest Local Test,C=JP" % P.TLS_NAME, "20240101000000", "20400101000000")
	return key.save(DIRECTORY + "/test-relay.key") == OK and certificate.save(DIRECTORY + "/test-relay.crt") == OK

func client(name: String) -> Node:
	var value := Online.new()
	value.name = name
	value.content_hash = test_content
	value.certificate_path = test_certificate
	root.add_child(value)
	value.match_message.connect(func(sender: int, kind: String, payload: Dictionary): inbox.append({"client": name, "sender": sender, "kind": kind, "payload": payload}))
	value.cursor_received.connect(func(sender: int, payload: Dictionary): cursors.append({"client": name, "sender": sender, "payload": payload}))
	value.error_received.connect(func(message: String): errors.append(name + ": " + message))
	clients.append(value)
	return value

func _run() -> void:
	create_timer(75, true, false, true).timeout.connect(func():
		push_error("Native network test deadline exceeded")
		_cleanup()
		quit(3))
	var endpoint_file := OS.get_environment("BLOCK_CONQUEST_NETWORK_TEST_ENDPOINT")
	var port := 0
	if endpoint_file.is_empty():
		check(_certificate(), "local-only DTLS certificate created")
		server = Relay.new()
		server.model.content_hash = test_content
		root.add_child(server)
		check(server.start("127.0.0.1", 0, DIRECTORY + "/test-relay.key", DIRECTORY + "/test-relay.crt") == OK, "native encrypted relay binds an ephemeral UDP port")
		port = server.connection.get_local_port()
	else:
		endpoint = JSON.parse_string(FileAccess.get_file_as_string(endpoint_file))
		test_content = P.content_hash()
		test_certificate = "res://scripts/network/relay_trust.crt"
		port = int(endpoint.port)
	var host := client("Host")
	var ally := client("Ally")
	var enemy := client("Enemy")
	host.recovery_requested.connect(func(player: int): recoveries.append(player))
	for index: int in clients.size():
		var value: Node = clients[index]
		var client_port := int(endpoint.ports[index]) if endpoint.has("ports") else port
		check(value.connect_relay(str(endpoint.get("address", "127.0.0.1")), client_port) == OK, "native client initializes validated DTLS")
	if not await until(func(): return clients.all(func(value: Node): return value.connection_state == "connected"), "all independent DTLS connections complete content handshake", 25.0): return _finish()
	host.create_room("rivers", "持盾熊")
	if not await until(func(): return host.connection_state == "room", "Host receives secure room identity"): return _finish()
	var code: String = host.room.code
	host.move_to_slot(3)
	host.set_slot(0, "bot", "frog")
	await until(func(): return host.local_faction == 3 and host.room.slots[0].kind == "bot", "Host sits at nonzero seat and adds a bot at zero")
	ally.join_room(code, "同队兔")
	if not await until(func(): return ally.local_faction == 1, "human joins the first free fixed slot"): return _finish()
	enemy.join_room(code, "敌方松鼠")
	if not await until(func(): return enemy.local_faction == 2, "next human retains next fixed faction"): return _finish()
	host.choose_commander("bear")
	ally.choose_commander("rabbit")
	await until(func(): return enemy.room.slots[3].commander == "bear" and enemy.room.slots[1].commander == "rabbit", "per-human commanders propagate consistently")
	for value: Node in clients: value.set_ready(true)
	if not await until(func(): return host.room.slots[1].ready and host.room.slots[2].ready and host.room.slots[3].ready, "all humans ready after roster configuration"): return _finish()
	host.start_match()
	if not await until(func(): return clients.all(func(value: Node): return value.connection_state == "loading" and not value.match_config.is_empty()), "locked manifest delivered to every client before simulation"): return _finish()
	host.loaded()
	ally.loaded()
	await pause(0.2)
	check(clients.all(func(value: Node): return value.connection_state == "loading"), "real socket load barrier waits for final human")
	# Finish loading while the transport is down: this acknowledgement must be
	# remembered and resent after reconnection instead of timing out the room.
	enemy._lost(Time.get_ticks_msec())
	enemy.loaded()
	check(enemy._loaded_match_id == str(enemy.match_config.match_id), "offline load completion is retained for reconnect")
	if not await until(func(): return clients.all(func(value: Node): return value.connection_state == "match"), "loading reconnect resends acknowledgement and releases the same start barrier", 15.0): return _finish()
	check(enemy.room.slots[2].controller == "human", "a loading reconnect does not start in a stuck recovery controller")
	check(host.is_host and host.player_id != 0 and host.local_faction == 3 and not ally.is_host, "gameplay authority is stable player identity independent of ENet peer or seat zero")
	var ally_id: int = ally.player_id
	ally.send_command({"type": "dispatch", "source": 1, "target": 2, "percent": 0.5, "seq": 1, "control_epoch": ally.room.slots[1].control_epoch})
	await until(func(): return inbox.any(func(item: Dictionary): return item.client == "Host" and item.kind == "command" and item.sender == ally_id), "client command reaches Host with relay-bound sender")
	host.send_match("events", {"seq": 1, "transactions": [{"kind": "population", "count": 69}]})
	await until(func(): return inbox.filter(func(item: Dictionary): return item.kind == "events").size() == 2, "Host sends reliable battle facts to both remote mirrors")
	host.send_match("command_result", {"seq": 1, "accepted": true}, ally_id, 1, true)
	await until(func(): return inbox.any(func(item: Dictionary): return item.client == "Ally" and item.kind == "command_result"), "private command result uses reliable command channel")
	check(not inbox.any(func(item: Dictionary): return item.client == "Enemy" and item.kind == "command_result"), "private result is absent from enemy transport")
	for index: int in 8:
		host.send_match("anchors", {"tick": 5 + index, "units": []}, -1, 4, false)
		await pause(0.05)
	await until(func(): return inbox.any(func(item: Dictionary): return item.client == "Ally" and item.kind == "anchors") and inbox.any(func(item: Dictionary): return item.client == "Enemy" and item.kind == "anchors"), "repeated unsequenced anchors tolerate a lost correction and reach both clients")
	host.send_match("snapshot_begin", {"id": 1, "count": 4}, ally_id, 5, true)
	for index: int in 4: host.send_match("snapshot_chunk", {"id": 1, "index": index, "data": "x".repeat(1024)}, ally_id, 5, true)
	host.send_match("snapshot_end", {"id": 1}, ally_id, 5, true)
	await until(func(): return inbox.filter(func(item: Dictionary): return item.kind.begins_with("snapshot_")).size() == 6, "paced reliable recovery channel transfers every snapshot part")
	var chunks := inbox.filter(func(item: Dictionary): return item.kind == "snapshot_chunk")
	check(chunks.size() == 4 and int(chunks[0].payload.index) == 0 and int(chunks[3].payload.index) == 3, "snapshot chunk sequence remains ordered within dedicated channel")
	ally.send_cursor({"cursor_seq": 1, "presence_epoch": 1, "world_x": 8.5, "world_z": -12.25, "visible": true, "pressed": true})
	await until(func(): return not cursors.is_empty(), "teammate's real-world cursor reaches Host")
	check(cursors.size() == 1 and cursors[0].client == "Host" and cursors[0].payload.world_x == 8.5 and cursors[0].payload.pressed, "cursor world coordinates and press state reach only same team")
	ally.send_cursor({"cursor_seq": 2, "presence_epoch": 2, "world_x": 8.5, "world_z": -12.25, "visible": false, "pressed": false})
	await until(func(): return cursors.size() == 2 and not cursors[-1].payload.visible, "reliable hide presence clears pointer and pressed ring")
	check(not cursors.any(func(item: Dictionary): return item.client == "Enemy"), "opponent receives no cursor packet at all")
	var old_token: String = ally._token
	ally._lost(Time.get_ticks_msec())
	await until(func(): return ally.connection_state == "match" and ally._token != old_token and ally.room.slots[1].controller == "reconnecting", "abrupt native disconnect automatically resumes same player with rotated credential", 12.0)
	check(ally.player_id == ally_id and ally.local_faction == 1, "automatic reconnect preserves player and faction")
	await until(func(): return ally_id in recoveries, "Host is asked to reconstruct rejoining mirror")
	host.complete_recovery(ally_id, int(host.room.slots[1].control_epoch) - 1)
	await pause(0.15)
	check(ally.room.slots[1].controller == "reconnecting", "stale recovery epoch cannot unlock a new native connection")
	host.complete_recovery(ally_id, int(host.room.slots[1].control_epoch))
	await until(func(): return ally.room.slots[1].controller == "human", "Host catch-up confirmation restores human input")
	recoveries.clear()
	var host_token: String = host._token
	host._lost(Time.get_ticks_msec())
	await until(func(): return host.connection_state == "match" and host._token != host_token and recoveries.size() == 2, "fast native Host replacement requests fresh mirrors from every other human", 15.0)
	await until(func(): return ally.room.slots[1].controller == "reconnecting" and enemy.room.slots[2].controller == "reconnecting", "Host replacement revocation reaches every remote before their controls return")
	host.complete_recovery(ally.player_id, int(host.room.slots[1].control_epoch))
	host.complete_recovery(enemy.player_id, int(host.room.slots[2].control_epoch))
	await until(func(): return ally.room.slots[1].controller == "human" and enemy.room.slots[2].controller == "human", "remote controls return only after fresh Host recovery confirmations")
	host.confirm_surrender(ally.player_id)
	host.confirm_surrender(host.player_id)
	await until(func(): return clients.all(func(value: Node): return value.room.slots[1].controller == "spectator" and value.room.slots[3].controller == "spectator"), "Host and teammate surrender permissions reach every native peer")
	inbox.clear()
	cursors.clear()
	ally._send({"op": "command", "match_id": ally.match_config.match_id, "payload": {"type": "pause", "value": false}}, 1)
	ally._send({"op": "presence", "match_id": ally.match_config.match_id, "room_revision": ally.room.revision, "payload": {"cursor_seq": 5, "presence_epoch": 5, "world_x": 8.5, "world_z": -12.25, "visible": true, "pressed": true}})
	await pause(0.2)
	check(inbox.is_empty() and cursors.is_empty(), "raw spectator command and cursor packets cannot bypass native relay permissions")
	host.send_match("events", {"seq": 100, "spectator_test": true})
	await until(func(): return inbox.filter(func(item: Dictionary): return item.kind == "events").size() == 2, "surrendered Host continues authority broadcasts and surrendered ally keeps receiving")
	recoveries.clear()
	old_token = ally._token
	ally._lost(Time.get_ticks_msec())
	await until(func(): return ally.connection_state == "match" and ally._token != old_token and ally_id in recoveries, "spectator automatically reconnects and requests a new mirror", 12.0)
	check(ally.room.slots[1].surrendered and ally.room.slots[1].controller == "reconnecting", "native spectator recovery preserves surrender before baseline completion")
	host.complete_recovery(ally_id, int(host.room.slots[1].control_epoch))
	await until(func(): return ally.room.slots[1].controller == "spectator", "native recovery returns only spectator permissions")
	var departed_id: int = enemy.player_id
	enemy.leave_room()
	await until(func(): return enemy.room.is_empty() and host.room.slots[2].forfeit_requested, "native active LEAVE releases client and persists Host-side forfeit")
	check(host.room.slots[2].player_id == departed_id and host.room.slots[2].kind == "human" and not host.room.slots[2].connected, "Host retains departed faction identity until it commits surrender")
	host.confirm_surrender(departed_id)
	await until(func(): return host.room.slots[2].surrendered and not host.room.slots[2].forfeit_requested and host.room.slots[2].controller == "spectator" and host.room.slots[2].player_id == -1, "native authoritative forfeit acknowledgement releases the departed identity")
	host.return_to_room()
	await until(func(): return host.connection_state == "room" and ally.connection_state == "room" and host.match_config.is_empty() and ally.match_config.is_empty(), "return-to-room atomically clears match state for all remaining clients")
	check([host, ally].all(func(value: Node): return value.room.slots.all(func(slot: Dictionary): return not slot.surrendered and not slot.forfeit_requested)), "returning to lobby resets surrender and forfeits for the next match")
	host.set_slot(2, "open", "squirrel")
	await until(func(): return host.room.slots[2].kind == "open", "Host opens the completed forfeit slot in lobby")
	enemy.join_room(host.room.code, "敌方重入")
	await until(func(): return enemy.connection_state == "room" and enemy.player_id != departed_id, "departed native client can join anew without its revoked old identity")
	for value: Node in clients: value.set_ready(true)
	await until(func(): return host.room.slots.filter(func(slot: Dictionary): return slot.kind == "human").all(func(slot: Dictionary): return slot.ready), "native rematch waits for fresh readiness after forfeits")
	host.start_match()
	await until(func(): return clients.all(func(value: Node): return value.connection_state == "loading"), "native rematch enters a new all-human loading barrier")
	host.loaded()
	ally.loaded()
	host.auto_reconnect = false
	host._peer.peer_disconnect()
	host._connection.flush()
	await until(func(): return ally.connection_state == "host_lost" and enemy.connection_state == "host_lost", "native Host disconnect suspends the loading barrier before the last guest finishes")
	enemy.loaded()
	await pause(2.0)
	check(ally.connection_state == "host_lost" and enemy.connection_state == "host_lost", "guest loading acknowledgement cannot start a native match without its Host")
	host.auto_reconnect = true
	check(host._open() == OK, "same Host instance reopens its authenticated loading transport")
	await until(func(): return clients.all(func(value: Node): return value.connection_state == "match"), "native Host restoration consumes the guest acknowledgement saved during its absence", 15.0)
	host.return_to_room()
	await until(func(): return clients.all(func(value: Node): return value.connection_state == "room"), "second native match returns every peer to the lobby")
	ally.leave_room()
	await until(func(): return host.room.slots[1].kind == "open" and ally.room.is_empty(), "graceful leave frees only that lobby seat")
	host.abort_connection("验证同步终止")
	await until(func(): return enemy.room.is_empty() and host.room.is_empty(), "Host departure reliably closes remaining room")
	check(host.connection_state == "disconnected", "public abort closes transport and tells Session to return to room")
	check(errors.all(func(message: String): return message.contains("房主已离开") or message.contains("验证同步终止")), "no protocol or transport errors during complete encrypted session")
	_finish()

func _finish() -> void:
	_cleanup()
	print("BLOCK_WAR_NATIVE_NETWORK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _cleanup() -> void:
	for value: Node in clients:
		value.disconnect_relay()
		value.free()
	clients.clear()
	if server != null:
		server.stop()
		server.free()
		server = null
