extends Control
## A room is a view of relay-owned seats. Never locally invent ready/occupant state.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const PROTOCOL := preload("res://scripts/network/war_protocol.gd")
var _online_maps: Array[Resource] = []
var _pending_action := ""
var _request_clock := 0.0
var _map_id := ""
var _displayed_room_code := ""
var _fill_queue: Array[int] = []
var _fill_waiting := -1
@onready var session: Node = get_node("/root/Session")
@onready var online: Node = session.online
@onready var _cards: Array[Node] = [%Seat0, %Seat1, %Seat2, %Seat3, %Seat4, %Seat5]

func _ready() -> void:
	get_tree().auto_accept_quit = true
	%Nickname.text = session.online_nickname
	for definition: Resource in CATALOG.MAPS:
		if not PROTOCOL.MAP_SEATS.has(definition.map_id):
			continue
		_online_maps.append(definition)
		%MapChoice.add_item("%s  ·  %s" % [definition.title, definition.mode_label()])
	%Create.pressed.connect(_request.bind("create"))
	%Join.pressed.connect(_request.bind("join"))
	%RoomCode.text_submitted.connect(func(_text: String): _request("join"))
	%MapChoice.item_selected.connect(_choose_map)
	%Ready.pressed.connect(_toggle_ready)
	%Start.pressed.connect(online.start_match)
	%Fill.pressed.connect(_fill_bots)
	%Copy.pressed.connect(_copy_code)
	%CopyFeedback.timeout.connect(_update_copy_label)
	%Leave.pressed.connect(_leave_room)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	%Preview.inspected.connect(func(text: String): %Inspection.text = text)
	for card: Node in _cards:
		card.move_requested.connect(online.move_to_slot)
		card.kind_requested.connect(online.set_slot)
		card.commander_requested.connect(_choose_commander)
	online.room_changed.connect(_refresh)
	online.state_changed.connect(_state_changed)
	online.error_received.connect(_error)
	session.load_failed.connect(_error)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	_refresh(online.room)
	_state_changed(online.connection_state)
	if not session.online_notice.is_empty():
		_error(session.online_notice)
		session.online_notice = ""
	if online.room.is_empty():
		%Nickname.grab_focus(true)
	else:
		%Ready.grab_focus(true)

func _request(action: String) -> void:
	if session.transition.busy or session.settings.is_open() or not _pending_action.is_empty():
		return
	var nickname: String = %Nickname.text.strip_edges()
	var code: String = %RoomCode.text.strip_edges().to_upper()
	if nickname.is_empty():
		_error("先为自己取一个名字。")
		%Nickname.grab_focus()
		return
	if action == "join" and code.length() != 6:
		_error("请输入完整的 6 位房间码。")
		%RoomCode.grab_focus()
		return
	session.online_nickname = nickname
	%RoomCode.text = code
	_pending_action = action
	_request_clock = 0.0
	%Message.text = "正在创建房间…" if action == "create" else "正在加入房间…"
	_set_entry_busy(true)
	if online.connection_state != "connected":
		var error: Error = online.connect_relay()
		if error != OK:
			_error("暂时无法连接联机服务，请稍后重试。")
			return
	# Queue once at the user action. Online owns handshake and reconnect retries.
	_send_pending()

func _send_pending() -> void:
	if _pending_action == "create":
		# A local campaign map is not necessarily part of the relay roster.
		# Start at the first room map when the previous local choice is absent.
		var selected: Resource = CATALOG.find_map(session.block_war_map_id)
		var index := maxi(0, _online_maps.find(selected))
		online.create_room(str(_online_maps[index].map_id), session.online_nickname)
	elif _pending_action == "join":
		online.join_room(%RoomCode.text, session.online_nickname)

func _set_entry_busy(value: bool) -> void:
	%Create.disabled = value
	%Join.disabled = value
	%Nickname.editable = not value
	%RoomCode.editable = not value

func _process(delta: float) -> void:
	if _pending_action.is_empty():
		return
	_request_clock += delta
	if _request_clock >= 15.0:
		online.disconnect_relay()
		_error("连接超时，请检查网络后重试。")

func _refresh(room: Dictionary) -> void:
	var in_room := not room.is_empty()
	%RoomLabel.visible = not in_room
	%Entry.visible = not in_room
	%Room.visible = in_room
	%RoomFooter.visible = in_room
	%Leave.visible = in_room
	if not in_room:
		%Copy.hide()
		%CopyFeedback.stop()
		_displayed_room_code = ""
		%RoomHeading.text = "与伙伴并肩，或一决高下。"
		%RoomLabel.text = "创建房间，或输入朋友分享的房间码。"
		_clear_fill()
		return
	_pending_action = ""
	_set_entry_busy(false)
	var host: bool = online.is_host
	var editable: bool = str(room.phase) == "room" and online.connection_state == "room"
	%RoomHeading.text = "战前集结"
	if _displayed_room_code != str(room.code):
		%CopyFeedback.stop()
		_displayed_room_code = str(room.code)
	_update_copy_label()
	%Copy.visible = true
	%MapChoice.disabled = not host or not editable
	%Fill.visible = host
	%Fill.disabled = not editable or _fill_waiting >= 0
	%Start.visible = host
	var open_count := 0
	var pending_count := 0
	var own: Dictionary = {}
	var seat_names: Dictionary = {}
	for card: Node in _cards:
		card.hide()
	for slot: Dictionary in room.slots:
		var card: Node = _cards[int(slot.slot_id)]
		card.show()
		card.refresh(slot, online.player_id, int(room.host_player_id), editable)
		seat_names[int(slot.faction_id)] = "位置 %d · %s" % [int(slot.slot_id) + 1, "空位" if str(slot.kind) == "open" else str(slot.name)]
		if str(slot.kind) == "open":
			open_count += 1
		if str(slot.kind) == "human":
			if not bool(slot.ready) or not bool(slot.connected):
				pending_count += 1
			if int(slot.player_id) == online.player_id:
				own = slot
	%Ready.disabled = not editable or own.is_empty()
	%Preview.seat_names = seat_names
	%Preview.local_faction = int(own.get("faction_id", -1))
	%Preview.queue_redraw()
	%Ready.text = "取消准备" if bool(own.get("ready", false)) else "准备就绪"
	%Start.disabled = not editable or open_count > 0 or pending_count > 0
	%Fill.disabled = %Fill.disabled or open_count == 0
	%RoomHint.text = "所有人已准备好，等待房主开始。"
	if not editable:
		%RoomHint.text = "正在载入战场，请等待所有指挥官就绪…"
	elif open_count > 0:
		%RoomHint.text = "还有 %d 个空位 · 邀请朋友，或由房主补入电脑。" % open_count
	elif pending_count > 0:
		%RoomHint.text = "等待 %d 位指挥官准备 · 换地图、位置或角色后需要重新准备。" % pending_count
	var selected: Resource = CATALOG.find_map(str(room.map_id))
	%MapChoice.select(_online_maps.find(selected))
	if _map_id != str(room.map_id):
		_map_id = str(room.map_id)
		%Preview.show_map(selected)
		%MapDescription.text = selected.description
		%MapFacts.text = "%s  ·  %d 座据点\n出生点编号与右侧位置一一对应" % [selected.mode_label(), selected.building_positions.size()]
		UIMotion.reveal_menu(%Preview, Vector2.ZERO)
	%Message.text = ""
	_advance_fill(room)

func _choose_map(index: int) -> void:
	_clear_fill()
	online.set_map(str(_online_maps[index].map_id))

func _choose_commander(slot_id: int, commander: String) -> void:
	for slot: Dictionary in online.room.slots:
		if int(slot.slot_id) == slot_id:
			if str(slot.kind) == "human":
				online.choose_commander(commander)
			else:
				online.set_slot(slot_id, "bot", commander)
			return

func _toggle_ready() -> void:
	for slot: Dictionary in online.room.slots:
		if str(slot.kind) == "human" and int(slot.player_id) == online.player_id:
			online.set_ready(not bool(slot.ready))
			return

func _fill_bots() -> void:
	# Every room edit advances revision. Wait for the accepted room before the next.
	_clear_fill()
	for slot: Dictionary in online.room.slots:
		if str(slot.kind) == "open":
			_fill_queue.append(int(slot.slot_id))
	_advance_fill(online.room)

func _advance_fill(room: Dictionary) -> void:
	if _fill_waiting >= 0:
		for slot: Dictionary in room.slots:
			if int(slot.slot_id) == _fill_waiting and str(slot.kind) == "open":
				return
		_fill_waiting = -1
	while not _fill_queue.is_empty():
		var next: int = _fill_queue.pop_front()
		for slot: Dictionary in room.slots:
			if int(slot.slot_id) == next and str(slot.kind) == "open":
				_fill_waiting = next
				%Fill.disabled = true
				online.set_slot(next, "bot", str(slot.commander))
				return

func _clear_fill() -> void:
	_fill_queue.clear()
	_fill_waiting = -1

func _copy_code() -> void:
	if not online.room.is_empty():
		DisplayServer.clipboard_set(str(online.room.code))
		%CopyFeedback.start()
		_update_copy_label()

func _update_copy_label() -> void:
	%Copy.text = "房间号  %s    %s" % [_displayed_room_code, "复制" if %CopyFeedback.is_stopped() else "已复制"]

func _state_changed(state: String) -> void:
	var labels := {"disconnected": "尚未连接", "connecting": "连接中…", "connected": "联机服务已连接", "room": "已连接", "loading": "载入战场…", "match": "对局进行中", "host_lost": "等待房主重连…", "reconnecting": "正在重新连接…"}
	%Connection.text = str(labels.get(state, "连接中…"))
	if state in ["reconnecting", "host_lost", "disconnected"] and not online.room.is_empty():
		_refresh(online.room)
		%RoomHint.text = "连接中断，正在尝试恢复。请稍候…"

func _error(message: String) -> void:
	_pending_action = ""
	_clear_fill()
	_set_entry_busy(false)
	if not online.room.is_empty():
		_refresh(online.room)
	%Message.text = message
	UIMotion.reveal_menu(%Message)

func _leave_room() -> void:
	_clear_fill()
	online.leave_room()
	_refresh(online.room)
	%Copy.hide()

func _back() -> void:
	if not session.settings.is_open() and not session.transition.busy:
		session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if not session.settings.is_open() and event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
