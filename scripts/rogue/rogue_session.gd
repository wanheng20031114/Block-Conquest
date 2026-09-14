class_name RogueSession
extends Node
## Scene-facing run owner; checkpoints contain only validated plain JSON data.

signal changed
const MAP_SCENE: String = "res://scenes/rogue/rogue_map.tscn"
const BATTLE_SCENE: String = "res://scenes/rogue/battle.tscn"
const SAVE_PATH: String = "user://rogue_run.json"
@export var save_path: String = SAVE_PATH
var state: RogueRunState = RogueRunState.new()
var error_message: String = ""

func start_new(strategy: String, pack: String, run_seed: int = 0) -> Error:
	if get_parent().transition.busy:
		return _fail("画面切换中，请稍候", ERR_BUSY)
	var fresh := RogueRunState.new()
	var result: Error = fresh.start_new(strategy, pack, run_seed)
	if result != OK:
		error_message = fresh.error_message
		return result
	var previous: RogueRunState = state
	state = fresh
	result = save_checkpoint()
	if result != OK:
		state = previous
		return result
	_prepare_singleplayer()
	changed.emit()
	return _change_scene(MAP_SCENE)

func has_checkpoint() -> bool:
	return FileAccess.file_exists(save_path)

func save_checkpoint() -> Error:
	if state == null or state.data.is_empty(): return _fail("尚未开始肉鸽远征", ERR_UNCONFIGURED)
	if state.data.phase not in RogueRunState.SAFE_PHASES:
		return _fail("当前节点尚未退出，最近的安全存档保持不变", ERR_BUSY)
	var reason: String = state.checkpoint_error()
	if not reason.is_empty(): return _fail(reason, ERR_INVALID_DATA)
	var payload: String = JSON.stringify(state.export_checkpoint())
	var envelope: Dictionary = {"format": 1, "snapshot": payload, "sha256": payload.sha256_text()}
	var temporary: String = save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("无法创建临时存档，请检查用户目录写入权限", FileAccess.get_open_error())
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK: return _fail("存档写入失败，原存档保持不变", write_error)
	var verification: Dictionary = _read_checkpoint(temporary)
	if verification.is_empty(): return ERR_FILE_CORRUPT
	var result: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path))
	if result != OK: return _fail("无法替换检查点，原存档保持不变", result)
	error_message = ""
	return OK

func load_run() -> Error:
	if get_parent().transition.busy:
		return _fail("画面切换中，请稍候", ERR_BUSY)
	var loaded: Dictionary = _read_checkpoint(save_path)
	if loaded.is_empty(): return ERR_FILE_CORRUPT if FileAccess.file_exists(save_path) else ERR_FILE_NOT_FOUND
	var candidate := RogueRunState.new()
	var result: Error = candidate.import_checkpoint(loaded)
	if result != OK: return _fail(candidate.error_message, result)
	state = candidate
	_prepare_singleplayer()
	error_message = ""
	changed.emit()
	return _change_scene(MAP_SCENE)

func enter_node(id: int) -> Error:
	if get_parent().transition.busy:
		return _fail("画面切换中，请稍候", ERR_BUSY)
	var previous: Dictionary = state.data.duplicate(true)
	var result: Error = state.enter_node(id)
	if result != OK: return _fail(state.error_message, result)
	if state.data.phase == "battle":
		result = launch_battle()
		if result != OK:
			state.data = previous
			changed.emit()
		return result
	return _publish_mutation(true)

func leave_node() -> Error:
	var result: Error = state.leave_node()
	if result != OK: return _fail(state.error_message, result)
	return _publish_mutation(true)

func launch_battle() -> Error:
	if get_parent().transition.busy:
		return _fail("画面切换中，请稍候", ERR_BUSY)
	var old_phase: String = state.data.phase
	var result: Error = state.launch_battle()
	if result != OK: return _fail(state.error_message, result)
	result = _change_scene(BATTLE_SCENE)
	if result != OK:
		state.data.phase = old_phase
		return result
	changed.emit()
	return OK

func resolve_battle(won: bool) -> void:
	var result: Error = state.resolve_battle(won)
	if result != OK:
		error_message = state.error_message
		return
	# Failure never overwrites the last checkpoint. Reward choices remain transient.
	_publish_mutation(true)
	_change_scene(MAP_SCENE)

func purchase(offer_index: int) -> Error:
	return _publish_result(state.purchase(offer_index))

func resolve_event(option: int) -> Error:
	return _publish_result(state.resolve_event(option))

func choose_camp(option: int) -> Error:
	return _publish_result(state.choose_camp(option))

func choose_relic(id: String) -> Error:
	return _publish_result(state.choose_relic(id), true)

func recruit(ticket_uid: int, kind: String, batches: int) -> Error:
	return _publish_result(state.recruit(ticket_uid, kind, batches), true)

func set_deployed(uid: int, value: bool) -> Error:
	return _publish_result(state.set_deployed(uid, value), true)

func set_layout(uid: int, encounter: String, layout: Array) -> Error:
	return _publish_result(state.set_layout(uid, encounter, layout), true)

func _publish_result(result: Error, persist: bool = false) -> Error:
	if result != OK: return _fail(state.error_message, result)
	return _publish_mutation(persist)

func _publish_mutation(persist: bool) -> Error:
	error_message = ""
	var result: Error = OK
	if persist and state.data.phase in RogueRunState.SAFE_PHASES:
		result = save_checkpoint()
	changed.emit()
	return result

func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("尚无肉鸽存档，请先开始一局远征", ERR_FILE_NOT_FOUND)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取肉鸽存档", FileAccess.get_open_error())
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("肉鸽存档损坏：文件不是有效的存档数据", ERR_FILE_CORRUPT)
		return {}
	var envelope: Dictionary = parser.data
	if typeof(envelope.get("format")) not in [TYPE_INT, TYPE_FLOAT] or float(envelope.format) != 1.0 or typeof(envelope.get("snapshot")) != TYPE_STRING or typeof(envelope.get("sha256")) != TYPE_STRING:
		_fail("肉鸽存档格式不受支持", ERR_FILE_CORRUPT)
		return {}
	var payload: String = envelope.snapshot
	if payload.sha256_text() != envelope.sha256:
		_fail("肉鸽存档校验失败，文件可能未完整写入", ERR_FILE_CORRUPT)
		return {}
	if parser.parse(payload) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("肉鸽检查点内容无效", ERR_FILE_CORRUPT)
		return {}
	var candidate := RogueRunState.new()
	if candidate.import_checkpoint(parser.data) != OK:
		_fail(candidate.error_message, ERR_FILE_CORRUPT)
		return {}
	return candidate.export_checkpoint()

func _prepare_singleplayer() -> void:
	get_tree().paused = false
	var owner_session: Node = get_parent()
	owner_session.relay.leave_room()
	owner_session.relay.disconnect_relay()
	owner_session.online = false
	owner_session.config.clear()

func _change_scene(path: String) -> Error:
	var result: Error = get_parent().change_scene(path)
	if result != OK: return _fail("无法加载肉鸽场景，请检查游戏文件", result)
	return OK

func _fail(message: String, code: Error) -> Error:
	error_message = message
	return code
