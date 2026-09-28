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
	await create_timer(0.4).timeout
	await capture("online_exit_guest")
	hud._cancel_online_action()
	check(not hud.get_node("%OnlineConfirm").visible, "cancel keeps player in match")
	original.is_host = true
	hud._configure_online_menu(original)
	hud._request_restart()
	check(hud.get_node("%OnlineConfirm").visible and hud._online_action == "room", "host return confirms full-room consequence")
	hud.show_result(true)
	check(not hud.get_node("%OnlineConfirm").visible, "match result dismisses stale confirmation")
	hud.queue_free()
	await process_frame
	original.match_config = {}
	original.is_host = false

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
