extends CanvasLayer
## Ephemeral world-space presence. It never participates in battle simulation.

const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const PROTOCOL := preload("res://scripts/network/war_protocol.gd")
const SEND_INTERVAL := 1.0 / 30.0
const KEEPALIVE := 0.5
const EXPIRY := 1.5
var game: Node3D
var online: Node
var _peers: Dictionary = {}
var _clock := 0.0
var _send_clock := 0.0
var _idle_clock := 0.0
var _sequence := 0
var _presence_epoch := 0
var _last_visible := false
var _last_pressed := false
var _last_point := Vector2.INF
var _mouse_inside := true

func configure(battle: Node3D, connection: Node) -> void:
	game = battle
	online = connection
	online.cursor_received.connect(_receive)
	online.room_changed.connect(_refresh)
	online.state_changed.connect(_state_changed)
	get_window().focus_exited.connect(_hide_local)
	get_window().mouse_exited.connect(_mouse_exited)
	get_window().mouse_entered.connect(func(): _mouse_inside = true)
	_refresh(online.room)

func _refresh(room: Dictionary) -> void:
	var own := _local_slot(room)
	var active: Array[int] = []
	for pointer: Control in $Pointers.get_children():
		pointer.hide()
	if own.is_empty():
		_peers.clear()
		return
	for slot: Dictionary in room.slots:
		var player := int(slot.player_id)
		if str(slot.kind) != "human" or player == online.player_id or int(slot.team_id) != int(own.team_id) or not bool(slot.connected) or str(slot.controller) != "human" or int(slot.faction_id) in game.surrendered_factions:
			continue
		active.append(player)
		var pointer: Control = $Pointers.get_child(int(slot.slot_id))
		pointer.setup(str(slot.name), FACTIONS.COLORS[int(slot.faction_id)])
		if not _peers.has(player):
			_peers[player] = {"seq": -1, "epoch": -1, "received": -EXPIRY, "point": Vector3.ZERO, "target": Vector3.ZERO, "visible": false, "pressed": false}
		_peers[player].pointer = pointer
		_peers[player].faction = int(slot.faction_id)
	for player: int in _peers.keys():
		if player not in active:
			_peers.erase(player)

func _local_slot(room: Dictionary) -> Dictionary:
	for slot: Dictionary in room.get("slots", []):
		if str(slot.kind) == "human" and int(slot.player_id) == online.player_id:
			return slot
	return {}

func _state_changed(state: String) -> void:
	if state != "match":
		_hide_local()
		for peer: Dictionary in _peers.values():
			peer.visible = false
			peer.pointer.hide()

func _mouse_exited() -> void:
	_mouse_inside = false
	_hide_local()

func _hide_local() -> void:
	if online != null and _last_visible:
		_publish(Vector2.ZERO, false, false)

func tick(delta: float) -> void:
	if online == null:
		return
	_clock += delta
	_send_clock += delta
	_idle_clock += delta
	var active: bool = online.connection_state == "match" and not game.finished
	var own := _local_slot(online.room)
	var can_share: bool = not own.is_empty() and bool(own.connected) and str(own.controller) == "human" and int(own.faction_id) not in game.surrendered_factions
	var view_size := get_viewport().get_visible_rect().size
	for peer: Dictionary in _peers.values():
		var pointer: Control = peer.pointer
		if int(peer.faction) in game.surrendered_factions:
			peer.visible = false
		if not active or not bool(peer.visible) or _clock - float(peer.received) > EXPIRY or game._local_menu:
			pointer.hide()
			continue
		peer.point = (peer.point as Vector3).lerp(peer.target, 1.0 - exp(-24.0 * delta))
		var world: Vector3 = peer.point
		if game.camera.is_position_behind(world):
			pointer.hide()
			continue
		var screen: Vector2 = game.camera.unproject_position(world)
		if not Rect2(Vector2.ZERO, view_size).has_point(screen) or game.hud.is_pointer_over_hud(screen):
			pointer.hide()
			continue
		pointer.show_at(screen, bool(peer.pressed), view_size)
	if _send_clock < SEND_INTERVAL:
		return
	_send_clock = fmod(_send_clock, SEND_INTERVAL)
	var screen := get_viewport().get_mouse_position()
	var present: bool = active and can_share and _mouse_inside and get_window().has_focus() and not game._local_menu and not game.hud.is_pointer_over_hud(screen) and Rect2(Vector2.ZERO, view_size).has_point(screen)
	var point := Vector2.ZERO
	if present:
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(game.camera.project_ray_origin(screen), game.camera.project_ray_normal(screen))
		present = hit != null
		if present:
			point = Vector2(hit.x, hit.z)
			var half_size: Vector2 = game.map.definition.half_size
			present = absf(point.x) <= half_size.x and absf(point.y) <= half_size.y
	var down: bool = present and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if present == _last_visible and down == _last_pressed and (not present or point.distance_squared_to(_last_point) < 0.0004) and _idle_clock < KEEPALIVE:
		return
	if active or _last_visible:
		_publish(point, present, down)

func _publish(point: Vector2, present: bool, down: bool) -> void:
	var own := _local_slot(online.room)
	if not own.is_empty() and int(own.faction_id) in game.surrendered_factions:
		present = false
		down = false
	_sequence += 1
	if present != _last_visible:
		_presence_epoch += 1
	_last_visible = present
	_last_pressed = down
	_last_point = point
	_idle_clock = 0.0
	online.send_cursor({"world_x": point.x, "world_z": point.y, "visible": present, "pressed": down, "cursor_seq": _sequence, "presence_epoch": _presence_epoch})

func _receive(sender: int, payload: Dictionary) -> void:
	if not _peers.has(sender) or online.connection_state != "match":
		return
	if not PROTOCOL.valid_cursor(payload):
		return
	var seq := int(payload.cursor_seq)
	var epoch := int(payload.presence_epoch)
	var peer: Dictionary = _peers[sender]
	if int(peer.faction) in game.surrendered_factions:
		return
	if seq <= int(peer.seq) or epoch < int(peer.epoch):
		return
	var point := Vector3(float(payload.world_x), 0.0, float(payload.world_z))
	var half_size: Vector2 = game.map.definition.half_size
	if not point.is_finite() or absf(point.x) > half_size.x or absf(point.z) > half_size.y:
		return
	var new_presence: bool = not bool(peer.visible) or _clock - float(peer.received) > EXPIRY or epoch > int(peer.epoch)
	peer.seq = seq
	peer.epoch = epoch
	peer.received = _clock
	peer.visible = bool(payload.visible)
	peer.pressed = bool(payload.pressed) and bool(payload.visible)
	peer.target = point
	if new_presence:
		peer.point = point
	if not bool(peer.visible):
		peer.pointer.hide()

func _exit_tree() -> void:
	_hide_local()
