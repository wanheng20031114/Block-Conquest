extends Node
## ENet owns reliability/congestion; DTLS authenticates/encrypts every hop.

const P := preload("res://scripts/network/war_protocol.gd")
const Rooms := preload("res://server/war_relay_rooms.gd")
var model := Rooms.new()
var connection: ENetConnection
var running := false
var _peers: Dictionary = {}
var _maintenance_at := 0
var _metrics_at := 0
var _received_packets := 0
var _received_bytes := 0
var _sent_packets := 0
var _sent_bytes := 0

func start(bind_address: String, port: int, key_path: String, certificate_path: String) -> Error:
	if running: return ERR_ALREADY_IN_USE
	var key := CryptoKey.new()
	var certificate := X509Certificate.new()
	if key.load(key_path) != OK or certificate.load(certificate_path) != OK: return ERR_CANT_OPEN
	if model.content_hash.is_empty(): model.content_hash = P.content_hash()
	if model.content_hash.is_empty(): return ERR_FILE_NOT_FOUND
	model.max_rooms = clampi(model.max_rooms, 1, 64)
	connection = ENetConnection.new()
	var result := connection.create_host_bound(bind_address, port, model.max_rooms * P.MAX_PLAYERS + 32, P.CHANNEL_COUNT)
	if result == OK: result = connection.dtls_server_setup(TLSOptions.server(key, certificate))
	if result != OK:
		stop()
		return result
	if not model.outgoing.is_connected(_send): model.outgoing.connect(_send)
	if not model.disconnect_peer.is_connected(_disconnect): model.disconnect_peer.connect(_disconnect)
	running = true
	return OK

func stop() -> void:
	running = false
	if connection != null: connection.destroy()
	connection = null
	_peers.clear()
	model.rooms.clear()
	model.players.clear()
	model.connections.clear()
	model._tokens.clear()

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	if not running: return
	for _index: int in 1024:
		var event := connection.service(0)
		var now := Time.get_ticks_msec()
		match int(event[0]):
			ENetConnection.EVENT_NONE: break
			ENetConnection.EVENT_CONNECT:
				var peer: ENetPacketPeer = event[1]
				peer.set_timeout(8, 2000, 5000)
				peer.ping_interval(500)
				peer.throttle_configure(500, 4, 1)
				_peers[peer.get_instance_id()] = peer
				model.connected(peer.get_instance_id(), now)
			ENetConnection.EVENT_RECEIVE:
				var peer: ENetPacketPeer = event[1]
				var packet := peer.get_packet()
				_received_packets += 1
				_received_bytes += packet.size()
				var channel := int(event[3])
				var identity: Dictionary = model.connections.get(peer.get_instance_id(), {})
				var host: bool = not identity.is_empty() and model._is_host(int(identity.player))
				# Reject oversize low-privilege data before JSON parsing. Host event
				# channels have a separate bounded allowance for replication batches.
				var limit := P.MAX_PACKET_BYTES if host and channel in [2, 4, 5] else P.MAX_CONTROL_BYTES
				var message := P.decode(packet) if packet.size() <= limit else {}
				model.receive(peer.get_instance_id(), message, channel, packet.size(), now)
				connection.flush()
			ENetConnection.EVENT_DISCONNECT:
				var peer: ENetPacketPeer = event[1]
				model.disconnected(peer.get_instance_id(), now)
				_peers.erase(peer.get_instance_id())
			ENetConnection.EVENT_ERROR:
				push_error("BLOCK_CONQUEST_RELAY_TRANSPORT_ERROR")
				stop()
				return
	var now := Time.get_ticks_msec()
	if now >= _maintenance_at:
		_maintenance_at = now + 100
		model.tick(now)
	if now >= _metrics_at:
		_metrics_at = now + 30000
		print("BLOCK_CONQUEST_RELAY_METRICS " + JSON.stringify({"rooms": model.rooms.size(), "connections": model.connections.size(), "received_packets": _received_packets, "received_bytes": _received_bytes, "sent_packets": _sent_packets, "sent_bytes": _sent_bytes}))
	connection.flush()

func _send(peer_id: int, message: Dictionary, channel: int, reliable: bool) -> void:
	if not _peers.has(peer_id): return
	var peer: ENetPacketPeer = _peers[peer_id]
	if not peer.is_active(): return
	var packet := P.encode(message)
	if packet.is_empty():
		push_error("BLOCK_CONQUEST_RELAY_ENCODING_ERROR")
		return
	if peer.send(channel, packet, ENetPacketPeer.FLAG_RELIABLE if reliable else ENetPacketPeer.FLAG_UNSEQUENCED) == OK:
		_sent_packets += 1
		_sent_bytes += packet.size()

func _disconnect(peer_id: int) -> void:
	if _peers.has(peer_id):
		_peers[peer_id].peer_disconnect_later()
		connection.flush()
