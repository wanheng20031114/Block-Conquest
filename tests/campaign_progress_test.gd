extends SceneTree
## Exercise real commander / battle transitions and keep progress fixtures local.

const MAP_CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var checks := 0
var failures: Array[String] = []
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _settle() -> void:
	while session.transition.busy:
		await process_frame

func _launch(index: int) -> Node3D:
	check(session.start_campaign_stage(index) == OK, "unlocked station starts")
	await scene_changed
	await _settle()
	check(current_scene.scene_file_path == session.COMMANDER_SCENE, "every campaign launch offers commander selection")
	current_scene.get_node("%Next").pressed.emit()
	await scene_changed
	var game: Node3D = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	await _settle()
	check(game.scene_file_path == session.BATTLE_SCENE, "commander confirmation opens the station battle directly")
	check(game.map.definition.map_id == session.CAMPAIGN_STAGES[index].map_id, "station uses its authored battlefield")
	check(game.faction_skills[1].commander == session.CAMPAIGN_STAGES[index].opponent_commander, "station uses its authored opponent")
	check(game.hud.get_node("%PauseExit").text == "返回战役铁路", "pause menu returns to the railway")
	return game

func _restart(game: Node3D) -> Node3D:
	game.restart()
	await scene_changed
	var replacement: Node3D = current_scene
	replacement.set_process(false)
	replacement.ai_enabled = false
	replacement.audio.muted = true
	await _settle()
	return replacement

func _finish(game: Node3D, winner: int) -> void:
	game.marches.clear()
	for building: Node3D in game.buildings:
		building.kind = 1
		building.population = 0.0
		building.faction = winner if winner >= 0 else building.building_id % 2
	game._check_victory()
	check(game.finished and game.winner_team == winner, "authored battle resolves the requested outcome")

func _return_to_railway(game: Node3D) -> void:
	game.hud.get_node("%ResultExit").pressed.emit()
	await scene_changed
	await _settle()
	check(current_scene.scene_file_path == session.CAMPAIGN_SCENE, "battle exit returns to the campaign")
	check(session.campaign_active_stage == -1, "returning clears only the active battle")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	var previous := {
		"path": session.campaign_save_path,
		"completed": session.campaign_completed_count,
		"active": session.campaign_active_stage,
		"map": session.block_war_map_id,
		"commander": session.block_war_commander,
		"opponent": session.block_war_opponent_commander,
		"had_selection": session.has_meta("campaign_selected_stage"),
		"selection": session.get_meta("campaign_selected_stage", 0),
	}
	var directory := ProjectSettings.globalize_path("res://.local/campaign-progress-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated progress fixture directory")
	session.campaign_save_path = directory.path_join("campaign.cfg")
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 0, "fresh save starts with zero completed stations")
	check(session.campaign_current_stage() == 0, "fresh train waits at station one")
	check(session.campaign_stage_unlocked(0) and not session.campaign_stage_unlocked(1), "only the first station initially unlocks")
	check(not session.campaign_stage_unlocked(-1) and not session.campaign_stage_unlocked(6), "out of range stations are rejected")
	check(session.start_campaign_stage(5) == ERR_INVALID_PARAMETER, "locked final station cannot launch")
	var maps: Array[String] = []
	for stage: Resource in session.CAMPAIGN_STAGES:
		var definition: Resource = MAP_CATALOG.find_map(stage.map_id)
		check(definition != null and ResourceLoader.exists(definition.scene_path, "PackedScene"), "station battlefield exists")
		check(not maps.has(stage.map_id), "each station has a different battlefield")
		maps.append(stage.map_id)
	check(maps.size() == 6, "campaign contains exactly six stations")
	var game := await _launch(0)
	_finish(game, 0)
	check(session.campaign_completed_count == 1 and session.campaign_current_stage() == 1, "victory unlocks the next station and advances the train")
	check(session.get_meta("campaign_selected_stage") == 1, "new victory selects the next unlocked station on return")
	check(session.campaign_stage_completed(0) and session.campaign_stage_unlocked(1), "passed station remains available to replay")
	check(FileAccess.file_exists(session.campaign_save_path), "victory persists progress")
	await _return_to_railway(game)
	game = await _launch(1)
	_finish(game, -1)
	check(session.campaign_completed_count == 1, "draw does not advance progress")
	game = await _restart(game)
	_finish(game, 1)
	check(session.campaign_completed_count == 1, "defeat does not advance progress")
	game = await _restart(game)
	_finish(game, 0)
	check(session.campaign_completed_count == 2, "retry victory advances progress once")
	await _return_to_railway(game)
	game = await _launch(0)
	session.set_meta("campaign_selected_stage", 0)
	check(session.campaign_current_stage() == 2, "replaying a previous station never moves the train back")
	_finish(game, 0)
	check(session.campaign_completed_count == 2 and session.campaign_current_stage() == 2, "replay victory preserves the furthest progress")
	check(session.get_meta("campaign_selected_stage") == 0, "replay victory preserves the browsed station")
	await _return_to_railway(game)
	session.campaign_completed_count = 0
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 2, "fresh read restores persisted progress")
	game = await _launch(2)
	game.exit_to_lobby()
	await scene_changed
	await _settle()
	check(session.campaign_completed_count == 2 and session.campaign_active_stage == -1, "leaving an unfinished battle preserves progress")
	check(session.start_war(true) == OK, "free play still starts")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	await _settle()
	_finish(game, 0)
	check(session.campaign_completed_count == 2, "free play victory cannot advance the campaign")
	await game.prepare_shutdown()
	# Persistence boundaries use the same Session method as the real result hook.
	session.campaign_active_stage = 2
	session._online_active = true
	check(session.complete_campaign_stage() == ERR_INVALID_PARAMETER and session.campaign_completed_count == 2, "online mode cannot write campaign victories")
	session._online_active = false
	var valid_path: String = session.campaign_save_path
	session.campaign_save_path = directory.path_join("missing/campaign.cfg")
	check(session.complete_campaign_stage() != OK and session.campaign_completed_count == 2, "failed save does not claim persistent progress")
	session.campaign_save_path = valid_path
	for index: int in range(2, 6):
		session.campaign_active_stage = index
		check(session.complete_campaign_stage() == OK and session.campaign_completed_count == index + 1, "remaining victories advance one station at a time")
	check(session.campaign_current_stage() == 5 and session.campaign_completed_count == 6, "completed railway keeps the train at the final station")
	for index: int in 6:
		check(session.campaign_stage_completed(index) and session.campaign_stage_unlocked(index), "all completed stations remain replayable")
	session.campaign_completed_count = 0
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 6, "complete campaign persists across reload")
	session.campaign_save_path = previous.path
	session.campaign_completed_count = previous.completed
	session.campaign_active_stage = previous.active
	session.block_war_map_id = previous.map
	session.block_war_commander = previous.commander
	session.block_war_opponent_commander = previous.opponent
	if previous.had_selection:
		session.set_meta("campaign_selected_stage", previous.selection)
	else:
		session.remove_meta("campaign_selected_stage")
	check(DirAccess.remove_absolute(valid_path) == OK and DirAccess.remove_absolute(directory) == OK, "only temporary campaign fixture files are removed")
	print("CAMPAIGN_PROGRESS_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
