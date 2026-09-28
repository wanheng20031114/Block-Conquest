extends Node
## Persistent preferences, selected commanders and native scene transitions.
signal load_failed(message: String)

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const COMMANDER_SCENE := "res://scenes/block_war/commander_select.tscn"
const BATTLE_SCENE := "res://scenes/block_war/block_war.tscn"
const ONLINE_SCENE := "res://scenes/network/war_room.tscn"
var block_war_map_id := "rift"
var block_war_commander: StringName = &"squirrel"
var block_war_opponent_commander: StringName = &"squirrel"
var online_nickname := "指挥官"
var online_notice := ""
var _online_active := false
var _pending_online_scene := ""
var _returning_online := false
var _online_battle_requested := false
@onready var settings: GameSettings = $Settings
@onready var transition: UITransition = $Transition
@onready var online: Node = $Online

func _ready() -> void:
	transition.failed.connect(_on_transition_failed)
	transition.completed.connect(_flush_online_scene)
	online.match_preparing.connect(_prepare_online_match)
	online.room_changed.connect(_online_room_changed)
	online.error_received.connect(_online_error)
	record_diagnostic("startup", {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name()})

func start_war(direct_launch: bool = false) -> Error:
	_online_active = false
	return change_scene(BATTLE_SCENE if direct_launch else COMMANDER_SCENE)

func start_online() -> Error:
	_online_active = true
	return change_scene(ONLINE_SCENE)

func back_to_online_room() -> void:
	if transition.busy:
		return
	get_tree().paused = false
	online.return_to_room()

func _prepare_online_match(config: Dictionary) -> void:
	if not _online_active:
		return
	block_war_map_id = str(config.map_id)
	_online_battle_requested = true
	_queue_online_scene(BATTLE_SCENE)

func _online_room_changed(value: Dictionary) -> void:
	if not _online_active:
		return
	var scene := get_tree().current_scene
	var in_battle := scene != null and scene.scene_file_path == BATTLE_SCENE
	if value.is_empty() or str(value.get("phase", "")) == "room":
		if _online_battle_requested or in_battle:
			_online_battle_requested = false
			if value.is_empty():
				online_notice = "房间已关闭，请重新创建或加入房间。"
			_queue_online_scene(ONLINE_SCENE)

func _online_error(message: String) -> void:
	if not _online_active:
		return
	var scene := get_tree().current_scene
	if _online_battle_requested or _returning_online or (scene != null and scene.scene_file_path == BATTLE_SCENE):
		if online.room.is_empty():
			_online_room_changed({})
			online_notice = message
		elif scene != null and scene.scene_file_path == BATTLE_SCENE:
			scene.hud.notify(message)

func _queue_online_scene(path: String) -> void:
	_pending_online_scene = path
	_flush_online_scene()

func _flush_online_scene() -> void:
	if transition.busy or _returning_online or _pending_online_scene.is_empty():
		return
	var path := _pending_online_scene
	_pending_online_scene = ""
	var scene := get_tree().current_scene
	if path == ONLINE_SCENE and scene != null and scene.scene_file_path == BATTLE_SCENE:
		_returning_online = true
		await scene.prepare_shutdown()
		_returning_online = false
		if not _online_active:
			return
		if _pending_online_scene == path:
			_pending_online_scene = ""
	if change_scene(path) != OK:
		online_notice = "联机战场载入失败，请返回房间后重试。"
		load_failed.emit(online_notice)
		if path == BATTLE_SCENE:
			_online_battle_requested = false
			online.leave_room()
			_queue_online_scene(ONLINE_SCENE)

func back_to_lobby() -> void:
	if transition.busy:
		return
	get_tree().paused = false
	_online_active = false
	_pending_online_scene = ""
	_online_battle_requested = false
	online.disconnect_relay()
	if change_scene(LOBBY_SCENE) != OK:
		load_failed.emit("无法返回主菜单，请检查游戏文件后重试。")

func change_scene(path: String) -> Error:
	return transition.change_scene(path)

func _on_transition_failed(path: String, _error: Error) -> void:
	load_failed.emit("无法切换场景，请检查游戏文件后重试。")
	if _online_active and path == BATTLE_SCENE:
		online_notice = "联机战场载入失败，请检查游戏文件后重试。"
		_online_battle_requested = false
		online.leave_room()
		_queue_online_scene(ONLINE_SCENE)

func record_diagnostic(event: String, details: Dictionary = {}) -> void:
	print("BLOCK_WAR_DIAGNOSTIC ", JSON.stringify({"event": event, "pid": OS.get_process_id(),
		"seconds": snappedf(Time.get_ticks_msec() / 1000.0, 0.001), "details": details}))
