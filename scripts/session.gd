extends Node
## Persistent preferences, selected commanders and native scene transitions.
signal load_failed(message: String)

const LOBBY_SCENE := "res://scenes/lobby.tscn"
const COMMANDER_SCENE := "res://scenes/block_war/commander_select.tscn"
const BATTLE_SCENE := "res://scenes/block_war/block_war.tscn"
var block_war_map_id := "rift"
var block_war_commander: StringName = &"squirrel"
var block_war_opponent_commander: StringName = &"squirrel"
@onready var settings: GameSettings = $Settings
@onready var transition: UITransition = $Transition

func _ready() -> void:
	transition.failed.connect(_on_transition_failed)
	record_diagnostic("startup", {"engine": Engine.get_version_info().string, "display": DisplayServer.get_name()})

func start_war(direct_launch: bool = false) -> Error:
	return change_scene(BATTLE_SCENE if direct_launch else COMMANDER_SCENE)

func back_to_lobby() -> void:
	if transition.busy:
		return
	get_tree().paused = false
	if change_scene(LOBBY_SCENE) != OK:
		load_failed.emit("无法返回主菜单，请检查游戏文件后重试。")

func change_scene(path: String) -> Error:
	return transition.change_scene(path)

func _on_transition_failed(_path: String, _error: Error) -> void:
	load_failed.emit("无法切换场景，请检查游戏文件后重试。")

func record_diagnostic(event: String, details: Dictionary = {}) -> void:
	print("BLOCK_WAR_DIAGNOSTIC ", JSON.stringify({"event": event, "pid": OS.get_process_id(),
		"seconds": snappedf(Time.get_ticks_msec() / 1000.0, 0.001), "details": details}))
