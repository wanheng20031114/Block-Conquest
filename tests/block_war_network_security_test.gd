extends SceneTree
## Negative DTLS tests intentionally produce native certificate handshake errors.
const Relay := preload("res://server/war_relay_server.gd")
const Online := preload("res://scripts/network/war_online.gd")
var server: Node
var clients: Array[Node] = []
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(label)

func client(hash: String = "security-fixture") -> Node:
	var value := Online.new()
	value.content_hash = hash
	value.auto_reconnect = false
	root.add_child(value)
	clients.append(value)
	return value

func _run() -> void:
	server = Relay.new()
	server.model.content_hash = "security-fixture"
	root.add_child(server)
	check(server.start("127.0.0.1", 0, "res://.local/network/relay-private.key", "res://scripts/network/relay_trust.crt") == OK, "trusted relay starts")
	var port: int = server.connection.get_local_port()
	var wrong_name := client()
	wrong_name.tls_name = "not-the-configured-relay"
	wrong_name.connect_relay("127.0.0.1", port)
	wrong_name.create_room("rift", "名称不匹配")
	var crypto := Crypto.new()
	var private := crypto.generate_rsa(2048)
	var certificate := crypto.generate_self_signed_certificate(private, "CN=block-conquest-relay,O=Wrong Local Authority,C=JP", "20240101000000", "20400101000000")
	certificate.save("res://.local/network-tests/untrusted.crt")
	var wrong_ca := client()
	wrong_ca.certificate_path = "res://.local/network-tests/untrusted.crt"
	wrong_ca.connect_relay("127.0.0.1", port)
	wrong_ca.create_room("rift", "错误信任")
	await create_timer(2.0, true, false, true).timeout
	check(wrong_name.player_id == -1 and wrong_name.room.is_empty() and not wrong_name._hello, "TLS hostname mismatch cannot obtain room identity or send intent")
	check(wrong_ca.player_id == -1 and wrong_ca.room.is_empty() and not wrong_ca._hello, "untrusted authority with matching CN cannot obtain room identity")
	check(server.model.rooms.is_empty() and server.model.players.is_empty(), "failed TLS peers never reach application membership")
	wrong_name.disconnect_relay()
	wrong_ca.disconnect_relay()
	var wrong_content := client("old-content")
	var rejected := [false]
	wrong_content.error_received.connect(func(message: String): rejected[0] = message.contains("内容不一致"))
	wrong_content.connect_relay("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 5000
	while not rejected[0] and Time.get_ticks_msec() < deadline: await process_frame
	check(rejected[0] and wrong_content.player_id == -1, "valid DTLS but wrong content gets an explicit authenticated rejection")
	var valid := client()
	valid.connect_relay("127.0.0.1", port)
	valid.create_room("rift", "合法玩家")
	deadline = Time.get_ticks_msec() + 5000
	while valid.room.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(valid.player_id > 0 and not valid.room.is_empty() and valid.is_host, "valid client still connects after invalid peers; no global DTLS failure")
	for value: Node in clients:
		value.disconnect_relay()
		value.free()
	clients.clear()
	server.stop()
	server.free()
	print("BLOCK_WAR_NETWORK_SECURITY checks=%d failures=%d expected_native_tls_rejections=2" % [checks, failures])
	quit(0 if failures == 0 else 1)
