extends SceneTree
## Negative DTLS tests intentionally produce native certificate handshake errors.
const Relay := preload("res://server/war_relay_server.gd")
const Online := preload("res://scripts/network/war_online.gd")
const TLSFixture := preload("res://tests/network_tls_fixture.gd")
var tls := TLSFixture.new()
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
	value.certificate_path = tls.certificate_path
	value.content_hash = hash
	value.auto_reconnect = false
	root.add_child(value)
	clients.append(value)
	return value

func _run() -> void:
	create_timer(25, true, false, true).timeout.connect(func(): _finish(3))
	var certificate_error := tls.create("security")
	check(certificate_error == OK, "security test creates its own local DTLS identity")
	if certificate_error != OK: return _finish()
	server = Relay.new()
	server.model.content_hash = "security-fixture"
	root.add_child(server)
	var start_error: Error = server.start("127.0.0.1", 0, tls.key_path, tls.certificate_path)
	check(start_error == OK, "trusted relay starts")
	if start_error != OK: return _finish()
	var port: int = server.connection.get_local_port()
	var wrong_name := client()
	wrong_name.tls_name = "not-the-configured-relay"
	wrong_name.connect_relay("127.0.0.1", port)
	wrong_name.create_room("rift", "名称不匹配")
	var untrusted_error := tls.create_untrusted_certificate()
	check(untrusted_error == OK, "same-name untrusted authority is created independently")
	if untrusted_error != OK: return _finish()
	var wrong_ca := client()
	wrong_ca.certificate_path = tls.untrusted_certificate_path
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
	_finish()

func _finish(code: int = -1) -> void:
	for value: Node in clients:
		value.disconnect_relay()
		value.free()
	clients.clear()
	if server != null:
		server.stop()
		server.free()
		server = null
	check(tls.cleanup() == OK, "security test removes its local TLS files after shutdown")
	print("BLOCK_WAR_NETWORK_SECURITY checks=%d failures=%d expected_native_tls_rejections=2" % [checks, failures])
	quit(code if code >= 0 else (0 if failures == 0 else 1))
