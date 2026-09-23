extends SceneTree
## Real 2v2 / 3v3 campaigns with a passive human, including cold AI planning cost.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	var session := root.get_node("Session")
	for map_id: String in ["rivers", "islands"]:
		if not OS.get_cmdline_user_args().is_empty() and map_id != OS.get_cmdline_user_args()[0]:
			continue
		session.block_war_map_id = map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.audio.muted = true
		var started := Time.get_ticks_usec()
		game._ai_turn()
		print("TEAM_AI_COLD map=", map_id, " ms=", (Time.get_ticks_usec() - started) / 1000.0)
		for faction: int in range(1, game.faction_count):
			check(game.by_id[faction].is_constructing, "every computer develops its own economy")
		var expanded := PackedByteArray()
		expanded.resize(game.faction_count)
		var max_tick_us := 0
		for step: int in 9000:
			started = Time.get_ticks_usec()
			game.simulate(0.1)
			max_tick_us = maxi(max_tick_us, Time.get_ticks_usec() - started)
			for building: WarBuilding in game.buildings:
				if building.building_id >= game.faction_count and building.faction >= 0:
					expanded[building.faction] = 1
			if step % 1200 == 0:
				print("TEAM_CAMPAIGN map=", map_id, " time=", game.elapsed, " allies=", game.team_total_for(0), " enemies=", game.team_total_for(1), " expanded=", expanded, " max_tick_ms=", max_tick_us / 1000.0)
				await process_frame
			if game.finished:
				break
		for faction: int in range(1, game.faction_count):
			check(expanded[faction] == 1, "each computer captures a new building during the campaign")
		for building: WarBuilding in game.buildings:
			check(is_finite(building.population) and building.population >= 0.0, "team battles keep population finite and nonnegative")
		check(game.finished, "a passive human's alliance is resolved within 900 simulated seconds")
		print("TEAM_CAMPAIGN_RESULT map=", map_id, " time=", game.elapsed, " finished=", game.finished, " max_tick_ms=", max_tick_us / 1000.0)
		await game.prepare_shutdown()
	session.block_war_map_id = "rift"
	print("BLOCK_WAR_TEAM_CAMPAIGN checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
