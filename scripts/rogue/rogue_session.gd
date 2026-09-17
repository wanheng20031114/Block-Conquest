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
	if state == null or state.data.is_empty(): return _fail("尚未开始远征", ERR_UNCONFIGURED)
	if not state.can_checkpoint():
		return _fail("当前节点尚未完成，最近的存档保持不变", ERR_BUSY)
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
	if result != OK: return _fail("无法更新远征存档，原存档保持不变", result)
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
	var previous: RogueRunState = state
	state = candidate
	if not state.data.pending_recruits.is_empty():
		result = save_checkpoint()
		if result != OK:
			state = previous
			return result
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
	return _publish_mutation(true, previous)

func leave_node() -> Error:
	return _mutate(func() -> Error: return state.leave_node(), true)

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
	var result: Error = _mutate(func() -> Error: return state.resolve_battle(won), true)
	if result == OK: _change_scene(MAP_SCENE)

func confirm_settlement() -> Error:
	return _mutate(func() -> Error: return state.confirm_settlement(), true)

func purchase(offer_index: int) -> Error:
	return _mutate(func() -> Error: return state.purchase(offer_index))

func resolve_event(option: int) -> Error:
	return _mutate(func() -> Error: return state.resolve_event(option))

func choose_camp(option: int) -> Error:
	return _mutate(func() -> Error: return state.choose_camp(option))

func choose_relic(id: String) -> Error:
	return _mutate(func() -> Error: return state.choose_relic(id), true)

func choose_recruit_unit(ticket_uid: int, kind: String) -> Error:
	return _mutate(func() -> Error: return state.choose_recruit_unit(ticket_uid, kind), true)

func back_to_recruit_units() -> Error:
	return _mutate(func() -> Error: return state.back_to_recruit_units(), true)

func confirm_recruit_batches(ticket_uid: int, batches: int) -> Error:
	return _mutate(func() -> Error: return state.confirm_recruit_batches(ticket_uid, batches), true)

func discard_recruit(ticket_uid: int) -> Error:
	return _mutate(func() -> Error: return state.discard_recruit(ticket_uid), true)

func recruit(ticket_uid: int, kind: String, batches: int) -> Error:
	return _mutate(func() -> Error: return state.recruit(ticket_uid, kind, batches), true)

func set_deployed(uid: int, value: bool) -> Error:
	return set_deployed_many([uid], value)

func set_layout(uid: int, encounter: String, layout: Array) -> Error:
	return set_layouts(encounter, [{"uid": uid, "layout": layout}])

func set_deployed_many(uids: Array, value: bool) -> Error:
	return _mutate(func() -> Error: return state.set_deployed_many(uids, value), true)

func set_layouts(encounter: String, changes: Array) -> Error:
	return _mutate(func() -> Error: return state.set_layouts(encounter, changes), true)

func _mutate(action: Callable, persist: bool = false) -> Error:
	var previous: Dictionary = state.data.duplicate(true)
	var result: Error = action.call()
	if result != OK:
		state.data = previous
		return _fail(state.error_message, result)
	return _publish_mutation(persist, previous)

func _publish_mutation(persist: bool, previous: Dictionary) -> Error:
	error_message = ""
	var result: Error = OK
	if persist and state.can_checkpoint():
		result = save_checkpoint()
		if result != OK:
			state.data = previous
			return result
	changed.emit()
	return result

func _read_checkpoint(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("尚无远征存档，请先开始一次远征", ERR_FILE_NOT_FOUND)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("无法读取远征存档", FileAccess.get_open_error())
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("远征存档损坏：文件不是有效的存档数据", ERR_FILE_CORRUPT)
		return {}
	var envelope: Dictionary = parser.data
	if typeof(envelope.get("format")) not in [TYPE_INT, TYPE_FLOAT] or float(envelope.format) != 1.0 or typeof(envelope.get("snapshot")) != TYPE_STRING or typeof(envelope.get("sha256")) != TYPE_STRING:
		_fail("无法读取此版本的远征存档", ERR_FILE_CORRUPT)
		return {}
	var payload: String = envelope.snapshot
	if payload.sha256_text() != envelope.sha256:
		_fail("远征存档校验失败，文件可能未完整写入", ERR_FILE_CORRUPT)
		return {}
	if parser.parse(payload) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_fail("远征存档内容无效", ERR_FILE_CORRUPT)
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
	if result != OK: return _fail("无法加载远征场景，请检查游戏文件", result)
	return OK

func _fail(message: String, code: Error) -> Error:
	error_message = message
	return code
