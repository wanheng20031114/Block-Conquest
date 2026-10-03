extends Node
## Persistent preferences, selected commanders and native scene transitions.
signal load_failed(message: String)
signal campaign_progress_changed

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const COMMANDER_SCENE := "res://scenes/block_war/commander_select.tscn"
const BATTLE_SCENE := "res://scenes/block_war/block_war.tscn"
const CAMPAIGN_SCENE := "res://scenes/campaign/campaign_map.tscn"
const CAMPAIGN_STAGES: Array[Resource] = [
	preload("res://data/campaign/01_woodland.tres"),
	preload("res://data/campaign/02_forest.tres"),
	preload("res://data/campaign/03_crossing.tres"),
	preload("res://data/campaign/04_pass.tres"),
	preload("res://data/campaign/05_snowfield.tres"),
	preload("res://data/campaign/06_summit.tres"),
]
const ONLINE_SCENE := "res://scenes/network/war_room.tscn"
const TUTORIAL_MENU_SCENE := "res://scenes/tutorial/tutorial_menu.tscn"
const TUTORIAL_BATTLE_SCENE := "res://scenes/tutorial/tutorial_battle.tscn"
const TUTORIAL_CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const TUTORIAL_PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")
const FIRST_RUN_STATE := preload("res://scripts/tutorial/first_run_state.gd")
var first_run: RefCounted
var tutorial_lesson_id: String = "core_command"
var tutorial_progress_path: String = TUTORIAL_PROGRESS.SAVE_PATH
var block_war_map_id := "rift"
var block_war_commander: StringName = &"squirrel"
var block_war_opponent_commander: StringName = &"squirrel"
var online_nickname := "指挥官"
var online_notice := ""
var campaign_save_path := "user://campaign.cfg"
var campaign_completed_count := 0
var campaign_active_stage := -1
# A saved victory unlocks its destination before the map presents the journey.
var campaign_travel_from := -1
var _online_active := false
var _pending_online_scene := ""
var _returning_online := false
var _online_battle_requested := false
@onready var settings: GameSettings = $Settings
@onready var transition: UITransition = $Transition
@onready var online: Node = $Online

func _enter_tree() -> void:
	first_run = FIRST_RUN_STATE.new()

func _ready() -> void:
	load_campaign_progress()
	transition.failed.connect(_on_transition_failed)
	transition.completed.connect(_flush_online_scene)
	online.match_preparing.connect(_prepare_online_match)
	online.room_changed.connect(_online_room_changed)
	online.error_received.connect(_online_error)
	record_diagnostic("startup", {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name()})

func start_war(direct_launch: bool = false) -> Error:
	campaign_active_stage = -1
	_online_active = false
	return change_scene(BATTLE_SCENE if direct_launch else COMMANDER_SCENE)

func start_online() -> Error:
	campaign_active_stage = -1
	_online_active = true
	return change_scene(ONLINE_SCENE)

func campaign_current_stage() -> int:
	# The destination follows saved progress, never the station being replayed.
	return mini(campaign_completed_count, CAMPAIGN_STAGES.size() - 1)

func campaign_stage_unlocked(index: int) -> bool:
	return index >= 0 and index < CAMPAIGN_STAGES.size() and index <= campaign_completed_count

func campaign_stage_completed(index: int) -> bool:
	return index >= 0 and index < campaign_completed_count

func load_campaign_progress() -> Error:
	var config := ConfigFile.new()
	var error := config.load(campaign_save_path)
	if error == ERR_FILE_NOT_FOUND:
		campaign_completed_count = 0
		campaign_travel_from = -1
		return OK
	if error != OK:
		push_warning("战役进度无法读取，错误码 %d" % error)
		return error
	var completed: Variant = config.get_value("campaign", "completed_count", 0)
	if not completed is int or completed < 0 or completed > CAMPAIGN_STAGES.size():
		push_warning("战役存档中的通关数量无效。")
		return ERR_INVALID_DATA
	campaign_completed_count = completed
	campaign_travel_from = -1
	return OK

func start_campaign_stage(index: int) -> Error:
	if transition.busy:
		return ERR_BUSY
	if not campaign_stage_unlocked(index):
		return ERR_INVALID_PARAMETER
	get_tree().paused = false
	_online_active = false
	_pending_online_scene = ""
	_online_battle_requested = false
	online.disconnect_relay()
	campaign_active_stage = index
	block_war_map_id = CAMPAIGN_STAGES[index].map_id
	block_war_opponent_commander = CAMPAIGN_STAGES[index].opponent_commander
	var error := change_scene(COMMANDER_SCENE)
	if error != OK:
		campaign_active_stage = -1
	return error

func complete_campaign_stage() -> Error:
	if _online_active or not campaign_stage_unlocked(campaign_active_stage):
		return ERR_INVALID_PARAMETER
	var completed := maxi(campaign_completed_count, campaign_active_stage + 1)
	if completed == campaign_completed_count:
		return OK
	var config := ConfigFile.new()
	config.set_value("campaign", "completed_count", completed)
	var error := config.save(campaign_save_path)
	if error != OK:
		return error
	var departure := campaign_current_stage()
	campaign_completed_count = completed
	if campaign_current_stage() != departure and campaign_travel_from < 0:
		campaign_travel_from = departure
	set_meta("campaign_selected_stage", campaign_current_stage())
	campaign_progress_changed.emit()
	return OK

func back_to_campaign() -> Error:
	if transition.busy:
		return ERR_BUSY
	get_tree().paused = false
	campaign_active_stage = -1
	return change_scene(CAMPAIGN_SCENE)

func start_tutorial(lesson_id: String = "") -> Error:
	if transition.busy:
		return ERR_BUSY
	if not lesson_id.is_empty() and not TUTORIAL_CATALOG.IDS.has(lesson_id):
		return ERR_INVALID_PARAMETER
	if lesson_id.is_empty() and TUTORIAL_PROGRESS.has_started(tutorial_progress_path):
		return show_tutorial_menu()
	tutorial_lesson_id = TUTORIAL_CATALOG.CORE_IDS[0] if lesson_id.is_empty() else lesson_id
	return _open_tutorial_scene(TUTORIAL_BATTLE_SCENE)

func show_tutorial_menu() -> Error:
	if transition.busy:
		return ERR_BUSY
	return _open_tutorial_scene(TUTORIAL_MENU_SCENE)

func _open_tutorial_scene(path: String) -> Error:
	get_tree().paused = false
	campaign_active_stage = -1
	_online_active = false
	_pending_online_scene = ""
	_online_battle_requested = false
	online.disconnect_relay()
	return change_scene(path)

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
	campaign_active_stage = -1
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
