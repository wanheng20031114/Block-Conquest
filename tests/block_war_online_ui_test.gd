extends SceneTree
## Room permissions, authoritative updates, cursor privacy and native layout checks.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var checks := 0
var failures := 0
var output := ""

class FakeOnline extends Node:
	signal room_changed(room: Dictionary)
	signal match_preparing(config: Dictionary)
	signal state_changed(state: String)
	signal error_received(message: String)
	signal cursor_received(sender: int, payload: Dictionary)
	var room: Dictionary = {}
	var match_config: Dictionary = {}
	var player_id := 15
	var is_host := true
	var connection_state := "connected"
	var operations: Array[Dictionary] = []
	func connect_relay() -> Error: return OK
	func create_room(map_id: String, nickname: String) -> void: operations.append({"op": "create", "map_id": map_id, "name": nickname})
	func join_room(code: String, nickname: String) -> void: operations.append({"op": "join", "code": code, "name": nickname})
	func set_map(map_id: String) -> void: operations.append({"op": "map", "map_id": map_id})
	func set_slot(slot: int, kind: String, commander: String) -> void: operations.append({"op": "slot", "slot": slot, "kind": kind, "commander": commander})
	func move_to_slot(slot: int) -> void: operations.append({"op": "move", "slot": slot})
	func choose_commander(commander: String) -> void: operations.append({"op": "commander", "commander": commander})
	func set_ready(ready: bool) -> void: operations.append({"op": "ready", "ready": ready})
	func start_match() -> void: operations.append({"op": "start"})
	func leave_room() -> void: room = {}; room_changed.emit(room)
	func return_to_room() -> void: operations.append({"op": "return"})
	func disconnect_relay() -> void: connection_state = "disconnected"
	func send_cursor(payload: Dictionary) -> void: operations.append(payload)
	func install(value: Dictionary) -> void:
		room = value.duplicate(true)
		connection_state = str(room.phase)
		state_changed.emit(connection_state)
		room_changed.emit(room)

class FakeHUD extends Node:
	var blocked := false
	func is_pointer_blocked(_point: Vector2) -> bool: return blocked
	func is_pointer_over_hud(_point: Vector2) -> bool: return blocked

class FakeMap extends Node3D:
	var definition: Resource

class FakeBattle extends Node3D:
	var camera: Camera3D
	var hud: FakeHUD
	var map: FakeMap
	var finished := false
	var _local_menu := false
	var match_paused := false
	var surrendered_factions: Array[int] = []
	var shutdown_count := 0
	func prepare_shutdown() -> void:
		shutdown_count += 1
		await get_tree().process_frame

class RecordingTransition extends UITransition:
	var paths: Array[String] = []
	var rejected := ""
	func _ready() -> void: pass
	func change_scene(path: String) -> Error:
		paths.append(path)
		return ERR_CANT_OPEN if path == rejected else OK

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func make_room() -> Dictionary:
	var slots: Array[Dictionary] = []
	for index: int in 6:
		slots.append({"slot_id": index, "faction_id": index, "team_id": index % 2, "player_id": index + 10 if index in [0, 2, 3, 5] else -1,
			"kind": "human" if index in [0, 2, 3, 5] else "open", "name": ["晨风", "等待加入", "森林里的另一位伙伴", "小青", "等待加入", "我的指挥官"][index],
			"ready": index == 3, "connected": true, "controller": "human", "control_epoch": 1,
			"commander": ["squirrel", "rabbit", "bear", "frog", "squirrel", "rabbit"][index]})
	return {"code": "ABC234", "revision": 1, "phase": "room", "map_id": "islands", "host_player_id": 15, "slots": slots}

func capture(name: String) -> void:
	if output.is_empty(): return
	await create_timer(0.35, true, false, true).timeout
	for index: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "save " + name)

func _run() -> void:
	create_timer(80.0, true, false, true).timeout.connect(func(): quit(3))
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session: Node = root.get_node("Session")
	var original: Node = session.online
	var online := FakeOnline.new()
	root.add_child(online)
	session.online = online
	var room: Control = load("res://scenes/network/war_room.tscn").instantiate()
	root.add_child(room)
	await process_frame
	check(room.get_node("%Entry").visible and not room.get_node("%Room").visible, "empty room displays entry")
	room.get_node("%Nickname").text = "  "
	room._request("create")
	check(online.operations.is_empty(), "empty nickname never sends request")
	room.get_node("%Nickname").text = "我的指挥官"
	room.get_node("%RoomCode").text = "123"
	room._request("join")
	check(online.operations.is_empty(), "incomplete room code never sends request")
	room.get_node("%RoomCode").text = "abc234"
	room._request("join")
	check(online.operations[-1].code == "ABC234", "room code is normalized")
	check(room.get_node("%Join").disabled, "pending request prevents double join")
	room._error("房间不存在，请检查房间码。")
	await create_timer(0.5).timeout
	await capture("online_entry")
	var value := make_room()
	online.install(value)
	await process_frame
	check(room.get_node("%Room").visible and not room.get_node("%Entry").visible, "membership opens room")
	check(room.get_node("%Preview").local_faction == 5, "host in seat six highlights own spawn")
	check(room.get_node("%Seat5").get_node("%Badge").text == "你 · 房主", "host identity follows seat")
	check(not room.get_node("%Seat5").get_node("%Commander").disabled, "own commander editable")
	check(room.get_node("%Seat0").get_node("%Commander").disabled, "host cannot change another human commander")
	check(not room.get_node("%Seat4").get_node("%Occupant").disabled, "host can place bot in any empty slot")
	check(room.get_node("%Start").disabled, "open/unready slots block start")
	room._toggle_ready()
	check(online.operations[-1] == {"op": "ready", "ready": true}, "ready is sent without optimistic room mutation")
	check(not bool(online.room.slots[5].ready), "ready remains authoritative")
	room._fill_bots()
	check(online.operations[-1].slot == 1, "fill starts first open seat")
	var sent := online.operations.size()
	online.room_changed.emit(online.room)
	check(online.operations.size() == sent, "duplicate room update does not send fill twice")
	value.slots[1].kind = "bot"
	value.slots[1].name = "电脑 · 兔子"
	online.install(value)
	check(online.operations[-1].slot == 4, "fill waits for room confirmation before next seat")
	value.slots[4].kind = "bot"
	value.slots[4].name = "电脑 · 松鼠"
	for slot: Dictionary in value.slots: slot.ready = true
	online.install(value)
	check(not room.get_node("%Start").disabled, "filled ready room can start")
	check(room.get_node("%Seat4").get_node("%Move").visible, "computer seat supports exchange")
	await create_timer(0.5).timeout
	await capture("online_room_host_1600")
	online.is_host = false
	online.player_id = 13
	room._refresh(online.room)
	check(not room.get_node("%Start").visible, "guest cannot start match")
	check(room.get_node("%MapChoice").disabled, "guest cannot change map")
	check(not room.get_node("%Seat4").get_node("%Occupant").visible, "guest cannot change bots")
	check(not room.get_node("%Seat3").get_node("%Commander").disabled, "guest chooses own commander")
	check(room.get_node("%Preview").local_faction == 3, "guest spawn highlight follows faction")
	root.size = Vector2i(1280, 720)
	await capture("online_room_guest_1280")
	check(room.get_node("%Ready").get_global_rect().end.y <= room.size.y, "ready remains inside 720p viewport")
	value.phase = "loading"
	online.install(value)
	check(room.get_node("%Ready").disabled, "loading barrier locks ready")
	check(room.get_node("%Seat3").get_node("%Commander").disabled, "loading barrier locks commander")
	room._leave_room()
	check(room.get_node("%Entry").visible and not room.get_node("%Room").visible and not room.get_node("%Copy").visible, "leaving room returns to usable create/join entry")
	room.queue_free()
	await process_frame
	var battle := FakeBattle.new()
	battle.map = FakeMap.new()
	battle.map.definition = CATALOG.find_map("islands")
	battle.add_child(battle.map)
	battle.hud = FakeHUD.new()
	battle.add_child(battle.hud)
	battle.camera = Camera3D.new()
	battle.camera.position = Vector3(0, 36, 26)
	battle.add_child(battle.camera)
	root.add_child(battle)
	battle.camera.look_at(Vector3.ZERO)
	battle.camera.current = true
	await process_frame
	var cursors: CanvasLayer = load("res://scenes/network/teammate_cursors.tscn").instantiate()
	battle.add_child(cursors)
	value.phase = "match"
	online.install(value)
	cursors.configure(battle, online)
	check(cursors._peers.size() == 1 and cursors._peers.has(15), "only allied human sender is in fixed cursor pool")
	var payload: Dictionary = JSON.parse_string('{"world_x":0,"world_z":0,"visible":true,"pressed":true,"cursor_seq":1,"presence_epoch":1}')
	cursors._receive(10, payload)
	check(not cursors._peers.has(10), "enemy packet cannot create pointer")
	cursors._receive(15, payload)
	check(cursors._peers[15].visible, "JSON integer fields survive float decoding")
	cursors.tick(0.01)
	var pointer: Control = cursors._peers[15].pointer
	check(pointer.visible and pointer.pressed, "teammate arrow and held ring appear")
	check(pointer.position.distance_to(battle.camera.unproject_position(Vector3.ZERO)) <= 1.0, "world position is projected through local camera")
	await capture("online_teammate_cursor")
	var old_screen := pointer.position
	battle.camera.position.x += 4.0
	await process_frame
	cursors.tick(0.01)
	check(pointer.position.distance_to(old_screen) > 2.0, "camera movement immediately reprojects cursor")
	payload.cursor_seq = 2
	payload.visible = false
	payload.pressed = false
	payload.presence_epoch = 2
	cursors._receive(15, payload)
	check(not pointer.visible, "reliable hide removes pointer immediately")
	payload.cursor_seq = 3
	payload.presence_epoch = 1
	payload.visible = true
	cursors._receive(15, payload)
	check(not cursors._peers[15].visible, "old presence epoch cannot resurrect pointer")
	payload.cursor_seq = 4
	payload.presence_epoch = 3
	payload.world_x = INF
	cursors._receive(15, payload)
	check(not cursors._peers[15].visible, "nonfinite position rejected")
	payload.world_x = 2000
	cursors._receive(15, payload)
	check(not cursors._peers[15].visible, "outside-map position rejected")
	payload.world_x = 0
	cursors._receive(15, payload)
	cursors.tick(0.01)
	check(pointer.visible, "new valid epoch restores pointer")
	battle.hud.blocked = true
	cursors.tick(0.01)
	check(not pointer.visible, "remote pointer cannot cover local HUD")
	battle.hud.blocked = false
	battle._local_menu = true
	cursors.tick(0.01)
	check(not pointer.visible, "local menu hides remote presence")
	battle._local_menu = false
	cursors.tick(1.6)
	check(not pointer.visible, "silent cursor expires")
	payload.cursor_seq = 5
	cursors._receive(15, payload)
	cursors.tick(0.01)
	check(pointer.visible, "fresh sample restores expired pointer")
	battle.match_paused = true
	cursors.tick(0.01)
	check(pointer.visible, "manual global pause preserves allied pointers for discussion")
	battle.surrendered_factions.append(5)
	cursors.tick(0.01)
	check(not pointer.visible, "surrender fact immediately hides the sender without waiting for a room revision")
	payload.cursor_seq = 6
	cursors._receive(15, payload)
	check(not cursors._peers[15].visible, "late packet cannot resurrect surrendered teammate pointer")
	battle.surrendered_factions.assign([3])
	cursors._refresh(value)
	payload.cursor_seq = 7
	cursors._receive(15, payload)
	cursors.tick(0.01)
	check(pointer.visible, "surrendered spectator still sees active teammate pointers")
	cursors._publish(Vector2(2, 3), true, true)
	check(not online.operations[-1].visible and not online.operations[-1].pressed, "surrendered local player cannot publish a visible or pressed pointer")
	battle.surrendered_factions.clear()
	battle.match_paused = false
	value.slots[5].connected = false
	online.install(value)
	check(cursors._peers.is_empty() and not pointer.visible, "disconnected teammate is removed immediately")
	cursors._publish(Vector2(2, 3), true, true)
	var active_epoch: int = online.operations[-1].presence_epoch
	cursors._hide_local()
	check(online.operations[-1].presence_epoch > active_epoch and not online.operations[-1].visible and not online.operations[-1].pressed, "focus hide increments epoch and clears pressed state")
	await _menu_checks(original, online)
	await _lifecycle_checks(session, online, battle)
	battle.queue_free()
	session.online = original
	online.queue_free()
	await process_frame
	await _entry_round_trip(session)
	print("ONLINE_UI_TEST checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _menu_checks(original: Node, online: Node) -> void:
	# HUD uses the persistent authored Online node; install only test metadata.
	original.match_config = {"match_id": "test"}
	original.is_host = false

	var hud: CanvasLayer = load("res://scenes/block_war/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	check(hud.get_node("%PauseRestart").disabled and hud.get_node("%ResultRestart").disabled, "guest battle menu cannot return whole room")
	check(hud.get_node("%PauseCard").get_node("Title").text == "战斗仍在继续", "online menu explains no global pause")
	await _match_menu_checks(hud, original)
	hud.set_network_status("正在同步战场", "请稍候…")
	check(hud.get_node("%OnlineStatus").visible, "network wait status remains until explicit recovery")
	await create_timer(0.4).timeout
	await capture("online_sync_status")
	hud.set_network_status("等待房主恢复连接", "对局已暂停 · 30 秒内可恢复")
	await create_timer(0.4).timeout
	await capture("online_host_reconnect")
	hud.set_network_status("")
	check(not hud.get_node("%OnlineStatus").visible, "successful recovery explicitly clears wait status")
	check(hud.is_pointer_over_hud(hud.get_node("%Top").get_global_rect().get_center()), "shared pointer hides over informational scoreboard")
	hud.set_paused(true)
	await create_timer(0.4).timeout
	await capture("online_pause_guest")
	hud._request_exit()
	check(hud.get_node("%OnlineConfirm").visible, "leaving online battle requires concrete confirmation")
	var leave_detail: Label = hud.get_node("%OnlineConfirm").get_node("Center/Card/Column/Detail")
	check(leave_detail.text.contains("投降") and leave_detail.text.contains("40%") and leave_detail.text.contains("真人队友") and not leave_detail.text.contains("电脑接管"), "voluntary guest leave explains surrender and asset loss")
	_modal_focus_checks(hud, "voluntary leave")
	await create_timer(0.4).timeout
	await capture("online_exit_guest")
	_native_key(KEY_ENTER)
	check(not hud.get_node("%OnlineConfirm").visible, "cancel keeps player in match")
	original.is_host = true
	hud._configure_online_menu(original)
	hud._request_exit()
	check(leave_detail.text.contains("关闭房间") and leave_detail.text.contains("观战") and leave_detail.text.contains("托管"), "Host leave explains room closure and the option to retain hosting while spectating")
	hud._cancel_online_action()
	hud._request_restart()
	check(hud.get_node("%OnlineConfirm").visible and hud._online_action == "room", "host return confirms full-room consequence")
	_modal_focus_checks(hud, "Host room return")
	hud.show_result(true)
	check(not hud.get_node("%OnlineConfirm").visible, "match result dismisses stale confirmation")
	hud.queue_free()
	await process_frame
	original.match_config = {}
	original.is_host = false

func _native_key(code: int, echo := false, shift := false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		event.echo = echo and down
		event.shift_pressed = shift
		root.push_input(event, true)

func _modal_focus_checks(hud: CanvasLayer, context: String) -> void:
	var modal: Control = hud.get_node("%OnlineConfirm")
	var cancel: Button = modal.get_node("Center/Card/Column/Actions/Cancel")
	var confirm: Button = modal.get_node("Center/Card/Column/Actions/Confirm")
	var action: String = hud._online_action
	for reverse: bool in [false, true]:
		var confined := true
		for _step: int in 12:
			_native_key(KEY_TAB, false, reverse)
			confined = confined and root.gui_get_focus_owner() in [cancel, confirm]
		check(confined, context + " native " + ("Shift Tab" if reverse else "Tab") + " remains in the confirmation")
	var arrows_confined := true
	for arrow: int in [KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_LEFT]:
		_native_key(arrow)
		arrows_confined = arrows_confined and root.gui_get_focus_owner() in [cancel, confirm]
	check(arrows_confined and modal.visible and hud._online_action == action, context + " directional navigation cannot focus or activate background actions")
	cancel.grab_focus()

func _match_menu_checks(hud: CanvasLayer, online: Node) -> void:
	var match_requests: Array[bool] = []
	var surrender_requests: Array[int] = []
	var skill_requests: Array[int] = []
	var ratio_requests: Array[int] = []
	var local_requests: Array[bool] = []
	hud.match_pause_requested.connect(func(value: bool): match_requests.append(value))
	hud.surrender_requested.connect(func(): surrender_requests.append(1))
	hud.skill_requested.connect(func(index: int, _keyboard: bool): skill_requests.append(index))
	hud.percentage_changed.connect(func(value: int): ratio_requests.append(value))
	hud.pause_requested.connect(func(): local_requests.append(true))
	hud.resume_requested.connect(func(): local_requests.append(false))
	var state := {"global_paused": false, "local_surrendered": false, "can_match_pause": true, "can_surrender": true, "pause_actor_name": ""}
	hud._update_match_controls(state)
	check(InputMap.has_action("pause") and InputMap.action_get_events("pause").any(func(event: InputEvent): return event is InputEventKey and event.physical_keycode == KEY_F3), "pause is a native project input action bound to F3")
	_native_key(KEY_F3)
	check(match_requests == [true] and local_requests.is_empty(), "native F3 requests global pause without opening local menu")
	check(not hud._global_paused and not hud.get_node("%MatchStatus").visible, "request does not optimistically change authoritative pause state")
	_native_key(KEY_F3, true)
	check(match_requests.size() == 1, "held pause key cannot flood toggles through echo events")
	state.global_paused = true
	state.pause_actor_name = "晨风"
	hud._update_match_controls(state)
	check(hud.get_node("%MatchStatus").visible and hud.get_node("%MatchStatusDetail").text.contains("晨风"), "authoritative global pause names its actor in a persistent banner")
	await capture("online_match_paused")
	_native_key(KEY_F3)
	check(match_requests == [true, false], "any active guest can request resume from global pause")
	_native_key(KEY_ESCAPE)
	check(local_requests == [true] and match_requests.size() == 2, "Esc during global pause only requests the local menu")
	hud.set_paused(true)
	check(not hud.get_node("%MatchStatus").visible and hud.get_node("%MatchPause").text.begins_with("继续对局"), "local menu represents an existing global pause without duplicate banner")
	await capture("online_paused_menu")
	check(hud.get_node("%PauseMenuActions").get_global_rect().end.y <= hud.get_node("%PauseCard").get_global_rect().end.y - 12, "all seven native menu actions fit inside 720p card")
	hud._request_surrender()
	check(hud._online_action == "surrender" and surrender_requests.is_empty(), "surrender needs confirmation and sends no premature command")
	var detail: Label = hud.get_node("%OnlineConfirm").get_node("Center/Card/Column/Detail")
	check(detail.text.contains("随机") and detail.text.contains("真人队友") and detail.text.contains("40%") and detail.text.contains("所有真人") and detail.text.contains("观战"), "confirmation explains transfers garrison loss team defeat and spectator outcome")
	_modal_focus_checks(hud, "surrender")
	await capture("online_surrender_confirm")
	_native_key(KEY_F3)
	check(match_requests.size() == 2, "confirmation owns F3 and prevents an unintended global action")
	_native_key(KEY_ESCAPE)
	check(not hud.get_node("%OnlineConfirm").visible and surrender_requests.is_empty(), "Esc safely cancels surrender")
	hud._request_surrender()
	state.can_surrender = false
	hud._update_match_controls(state)
	check(not hud.get_node("%OnlineConfirm").visible and hud._online_action.is_empty(), "authority removing surrender permission dismisses a stale confirmation")
	state.can_surrender = true
	hud._update_match_controls(state)
	hud._request_surrender()
	hud._confirm_online_action()
	check(surrender_requests.size() == 1 and not hud._local_surrendered, "confirmation sends one request and waits for authority to enter spectating")
	state.can_surrender = false
	state.can_match_pause = false
	state.local_surrendered = true
	state.global_paused = false
	hud._update_match_controls(state)
	check(hud.get_node("%Surrender").disabled and hud.get_node("%MatchPause").disabled, "spectator cannot surrender twice or control pause")
	_native_key(KEY_F3)
	hud._request_skill(0, true)
	hud._select_percentage(100)
	hud._request_surrender()
	check(match_requests.size() == 2 and surrender_requests.size() == 1 and skill_requests.is_empty() and ratio_requests.is_empty(), "spectator shortcuts and direct UI callbacks cannot issue gameplay commands")
	hud._request_exit()
	check(detail.text.contains("已完成交接") and not detail.text.contains("40%"), "spectator leaving does not imply another asset transfer or garrison loss")
	hud._cancel_online_action()
	online.is_host = true
	hud._configure_online_menu(online)
	await capture("online_spectating_host")
	hud.set_paused(false)
	check(hud.get_node("%MatchStatusTitle").text.contains("观战"), "spectator sees persistent status after closing local menu")
	hud.set_network_status("正在同步战场", "请稍候")
	check(not hud.get_node("%MatchStatus").visible, "network recovery has visual priority over spectator status")
	hud.set_network_status("")
	check(hud.get_node("%MatchStatus").visible, "recovery completion restores persistent spectator status")
	# Remapping the action must also change which physical key the HUD accepts.
	var original_events := InputMap.action_get_events("pause")
	InputMap.action_erase_events("pause")
	var alternate := InputEventKey.new()
	alternate.physical_keycode = KEY_F8
	InputMap.action_add_event("pause", alternate)
	state.local_surrendered = false
	state.can_surrender = true
	state.can_match_pause = true
	hud._update_match_controls(state)
	_native_key(KEY_F3)
	check(match_requests.size() == 2, "unbound F3 no longer requests pause")
	_native_key(KEY_F8)
	check(match_requests == [true, false, true] and hud.get_node("%MatchPause").text.ends_with("F8"), "remapped action drives input and displayed shortcut")
	InputMap.action_erase_events("pause")
	for event: InputEvent in original_events: InputMap.action_add_event("pause", event)
	hud._request_surrender()
	check(detail.text.contains("房主") and detail.text.contains("继续托管"), "Host confirmation explains that surrender retains hosting responsibility")
	hud._cancel_online_action()
	hud._open_settings()
	_native_key(KEY_F3)
	check(match_requests.size() == 3, "settings keeps its keyboard focus without triggering global pause")
	root.get_node("Session/Settings").close_menu()
	online.is_host = false
	hud._configure_online_menu(online)
	hud._update_match_controls(state)

func _lifecycle_checks(session: Node, online: Node, battle: Node) -> void:
	var actual_transition: UITransition = session.transition
	var transition := RecordingTransition.new()
	session.transition = transition
	session._online_active = true
	transition.busy = true
	session._prepare_online_match({"map_id": "islands"})
	check(session._pending_online_scene == session.BATTLE_SCENE, "loading waits for current scene transition")
	session._online_room_changed({})
	check(session._pending_online_scene == session.ONLINE_SCENE, "room loss supersedes pending battle")
	transition.busy = false
	session._flush_online_scene()
	check(transition.paths[-1] == session.ONLINE_SCENE, "canceled load returns to room entry")
	transition.rejected = session.BATTLE_SCENE
	session._prepare_online_match({"map_id": "rift"})
	check(not session._online_battle_requested and online.room.is_empty(), "failed battle load leaves membership")
	check(transition.paths[-1] == session.ONLINE_SCENE and not session.online_notice.is_empty(), "failed load supplies actionable room notice")
	transition.rejected = ""
	battle.scene_file_path = session.BATTLE_SCENE
	current_scene = battle
	session._online_room_changed({"phase": "room"})
	await process_frame
	await process_frame
	check(battle.shutdown_count == 1 and transition.paths[-1] == session.ONLINE_SCENE, "accepted room return shuts battle down once before switching")
	current_scene = null
	session._online_active = false
	session._pending_online_scene = ""
	session._online_battle_requested = false
	session.transition = actual_transition
	session.online_notice = ""
	transition.free()

func _entry_round_trip(session: Node) -> void:
	change_scene_to_file(session.LOBBY_SCENE)
	await scene_changed
	await create_timer(0.5).timeout
	check(current_scene.get_node("%Version").text == "v" + str(ProjectSettings.get_setting("application/config/version")), "main menu uses release version setting")
	print("ONLINE_UI_VERSION ", current_scene.get_node("%Version").text)
	await capture("main_menu_version")
	current_scene.get_node("%OnlineMode").pressed.emit()
	while session.transition.busy: await process_frame
	check(current_scene.scene_file_path == session.ONLINE_SCENE and current_scene.get_node("%Create").is_visible_in_tree(), "main menu online entry works after leaving a room")
	current_scene.get_node("%Back").pressed.emit()
	while session.transition.busy: await process_frame
	check(current_scene.scene_file_path == session.LOBBY_SCENE and session.online.room.is_empty(), "back from online entry returns cleanly to main menu")
