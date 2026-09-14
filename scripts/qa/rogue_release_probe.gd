extends Node
## Packaged-build smoke: real exported scenes and isolated checkpoint ownership.
var failures: Array[String] = []
var checks: int = 0
var _done: bool = false
var _save_path: String

func _ready() -> void:
	get_tree().create_timer(40.0,true,false,true).timeout.connect(_timeout)
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _settle() -> void:
	for index: int in 6: await get_tree().process_frame

func _timeout() -> void:
	if not _done:
		failures.append("packaged roguelike timeout")
		_finish()

func _run() -> void:
	var rogue: RogueSession = Session.rogue
	_save_path = "user://rogue_release_probe_%d.json" % OS.get_process_id()
	rogue.save_path = _save_path
	_check(rogue.start_new("melee","steady",55199)==OK,"exported run starts")
	await get_tree().scene_changed
	await _settle()
	var map: Node3D = get_tree().current_scene
	_check(map.scene_file_path==RogueSession.MAP_SCENE,"exported forest loads")
	_check(map.get_node("Nodes").get_child_count()==34,"all authored route nodes packaged")
	map.army.open_panel("formation","outpost")
	await _settle()
	_check(map.army.visible,"exported army and models open")
	map.army.close_panel()
	_check(rogue.state.population()==18,"exported balance catalogue")
	var target: int = -1
	for entry: Dictionary in rogue.state.data.nodes:
		if entry.kind == "battle": target=int(entry.id); break
	for edge: Array in rogue.state.data.edges:
		if int(edge[0])==target: rogue.state.data.current_node=int(edge[1]); break
		if int(edge[1])==target: rogue.state.data.current_node=int(edge[0]); break
	_check(rogue.enter_node(target)==OK,"exported outpost starts")
	await get_tree().scene_changed
	await _settle()
	var battle: Node3D = get_tree().current_scene
	_check(battle.remaining_buildings()==8 and battle.living_enemies()==16,"outpost assets and definitions packaged")
	battle.skip_intro()
	battle.end_battle(true)
	battle.accept_result()
	await get_tree().scene_changed
	await _settle()
	_check(rogue.state.data.phase=="map" and int(rogue.state.data.xp)==50,"packaged victory commits reward")
	_check(rogue.load_run()==OK,"packaged checkpoint reloads")
	await get_tree().scene_changed
	await _settle()
	rogue.state.data.phase="siege_briefing"
	rogue.state.data.ap=0
	rogue.state.data.pending_siege=true
	rogue.state.data.battle_kind="siege"
	_check(rogue.save_checkpoint()==OK,"mandatory siege checkpoint stored")
	_check(rogue.launch_battle()==OK,"exported siege starts")
	await get_tree().scene_changed
	await _settle()
	battle=get_tree().current_scene
	_check(battle.headquarters.alive and battle.encounter.enemy_cap==24,"siege base and waves packaged")
	battle.skip_intro()
	battle.end_battle(true)
	battle.accept_result()
	await get_tree().scene_changed
	await _settle()
	_check(rogue.state.data.phase=="intermission" and int(rogue.state.data.ap)==12,"exported first floor reaches saved intermission")
	_finish()

func _finish() -> void:
	if _done: return
	_done=true
	if not _save_path.is_empty() and FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
	print("ROGUE_RELEASE_RESULT ",JSON.stringify({"checks":checks,"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)
