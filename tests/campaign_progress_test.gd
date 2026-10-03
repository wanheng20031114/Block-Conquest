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
	var departure: int = session.campaign_travel_from
	game.hud.get_node("%ResultExit").pressed.emit()
	await scene_changed
	var diorama: SubViewportContainer = current_scene.diorama
	if departure >= 0:
		var route: Path3D = diorama.world_route
		var departure_offset := route.curve.get_closest_offset(route.to_local(diorama.parking_anchors[departure].global_position))
		check(absf(diorama.train.progress - departure_offset) < 0.02, "returning victory initially places the train at its departure station")
		check(session.campaign_travel_from == departure, "scene creation preserves the unpresented journey")
	await _settle()
	check(current_scene.scene_file_path == session.CAMPAIGN_SCENE, "battle exit returns to the campaign")
	check(session.campaign_active_stage == -1, "returning clears only the active battle")
	if departure >= 0:
		check(diorama.train_moving, "the train begins driving after the railway transition opens")
		while diorama.train_moving:
			await process_frame
		check(diorama.parked_station == session.campaign_current_stage(), "the journey ends at the newly unlocked station")
		check(session.campaign_travel_from == -1, "arrival consumes the pending journey")
	else:
		check(not diorama.train_moving, "returning without new progress keeps the train parked")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	var previous := {
		"path": session.campaign_save_path,
		"completed": session.campaign_completed_count,
		"active": session.campaign_active_stage,
		"travel_from": session.campaign_travel_from,
		"map": session.block_war_map_id,
		"commander": session.block_war_commander,
		"opponent": session.block_war_opponent_commander,
		"had_selection": session.has_meta("campaign_selected_stage"),
		"selection": session.get_meta("campaign_selected_stage", 0),
	}
	var directory := ProjectSettings.globalize_path("res://.local/campaign-progress-%d" % OS.get_process_id())
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated progress fixture directory")
	session.campaign_save_path = directory.path_join("campaign.cfg")
	session.campaign_travel_from = 3
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 0, "fresh save starts with zero completed stations")
	check(session.campaign_travel_from == -1, "a fresh progress load clears any previous session journey")
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
	check(session.campaign_completed_count == 1 and session.campaign_current_stage() == 1, "victory unlocks the next station as the train's destination")
	check(session.campaign_travel_from == 0, "victory retains the old station until the return journey is presented")
	check(session.complete_campaign_stage() == OK and session.campaign_travel_from == 0, "duplicate victory cannot consume or replace the pending journey")
	check(session.get_meta("campaign_selected_stage") == 1, "new victory selects the next unlocked station on return")
	check(session.campaign_stage_completed(0) and session.campaign_stage_unlocked(1), "passed station remains available to replay")
	check(FileAccess.file_exists(session.campaign_save_path), "victory persists progress")
	await _return_to_railway(game)
	game = await _launch(1)
	_finish(game, -1)
	check(session.campaign_completed_count == 1, "draw does not advance progress")
	check(session.campaign_travel_from == -1, "draw does not schedule a train journey")
	game = await _restart(game)
	_finish(game, 1)
	check(session.campaign_completed_count == 1, "defeat does not advance progress")
	check(session.campaign_travel_from == -1, "defeat does not schedule a train journey")
	game = await _restart(game)
	_finish(game, 0)
	check(session.campaign_completed_count == 2, "retry victory advances progress once")
	check(session.campaign_travel_from == 1, "retry victory departs from the station that was actually reached")
	await _return_to_railway(game)
	game = await _launch(0)
	session.set_meta("campaign_selected_stage", 0)
	check(session.campaign_current_stage() == 2, "replaying a previous station never moves the train back")
	_finish(game, 0)
	check(session.campaign_completed_count == 2 and session.campaign_current_stage() == 2, "replay victory preserves the furthest progress")
	check(session.campaign_travel_from == -1, "replay victory does not schedule an already completed journey")
	check(session.get_meta("campaign_selected_stage") == 0, "replay victory preserves the browsed station")
	await _return_to_railway(game)
	session.campaign_completed_count = 0
	session.campaign_travel_from = 1
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 2, "fresh read restores persisted progress")
	check(session.campaign_travel_from == -1, "reloading saved progress begins parked without replaying session travel")
	game = await _launch(2)
	game.exit_to_lobby()
	await scene_changed
	await _settle()
	check(session.campaign_completed_count == 2 and session.campaign_active_stage == -1, "leaving an unfinished battle preserves progress")
	check(session.campaign_travel_from == -1 and not current_scene.diorama.train_moving, "leaving an unfinished battle does not move the train")
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
	check(session.campaign_travel_from == -1, "failed save does not schedule a journey to an unsaved destination")
	session.campaign_save_path = valid_path
	for index: int in range(2, 5):
		session.campaign_active_stage = index
		check(session.complete_campaign_stage() == OK and session.campaign_completed_count == index + 1, "remaining victories advance one station at a time")
		check(session.campaign_travel_from == 2, "unpresented victories retain the earliest departure station")
	# Replaying an old station must also preserve a journey awaiting presentation.
	session.campaign_active_stage = 0
	check(session.complete_campaign_stage() == OK and session.campaign_travel_from == 2, "replaying an old victory preserves the pending forward journey")
	session.campaign_active_stage = 5
	session.campaign_save_path = directory.path_join("missing/campaign.cfg")
	check(session.complete_campaign_stage() != OK and session.campaign_travel_from == 2, "a later save failure preserves the pending journey")
	session.campaign_save_path = valid_path
	# Model the already arrived final station before winning its battle.
	session.campaign_travel_from = -1
	check(session.complete_campaign_stage() == OK and session.campaign_completed_count == 6, "final victory completes all six stations")
	check(session.campaign_travel_from == -1, "final victory cannot schedule a journey beyond the terminus")
	check(session.campaign_current_stage() == 5 and session.campaign_completed_count == 6, "completed railway keeps the train at the final station")
	for index: int in 6:
		check(session.campaign_stage_completed(index) and session.campaign_stage_unlocked(index), "all completed stations remain replayable")
	session.campaign_completed_count = 0
	check(session.load_campaign_progress() == OK and session.campaign_completed_count == 6, "complete campaign persists across reload")
	session.campaign_save_path = previous.path
	session.campaign_completed_count = previous.completed
	session.campaign_active_stage = previous.active
	session.campaign_travel_from = previous.travel_from
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
