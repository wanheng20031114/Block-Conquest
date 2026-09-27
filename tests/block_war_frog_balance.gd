extends SceneTree
## Mirrored smoke audit of the first balance pass, not a win-rate estimate.
var game: Node3D
var results: Array[Dictionary] = []
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	var settings := {"frog_costs": RULES.FROG_COSTS, "frog_cooldowns": RULES.FROG_COOLDOWNS, "rabbit_rush_radius": RULES.RABBIT_RUSH_RADIUS, "rabbit_rush_attack_bonus": RULES.RABBIT_RUSH_ATTACK_BONUS}
	print("FROG_AUDIT_SETTINGS ", JSON.stringify(settings))
	var catalog := preload("res://scripts/block_war/war_map_catalog.gd")
	for definition: Resource in catalog.MAPS.slice(0, 2):
		for opponent: StringName in [&"squirrel", &"rabbit", &"bear"]:
			for frog_side: int in 2:
				if game != null:
					await game.prepare_shutdown()
				var session := root.get_node("Session")
				session.block_war_map_id = definition.map_id
				session.block_war_commander = &"frog" if frog_side == 0 else opponent
				session.block_war_opponent_commander = opponent if frog_side == 0 else &"frog"
				change_scene_to_file("res://scenes/block_war/block_war.tscn")
				await scene_changed
				game = current_scene
				game.set_process(false)
				game.camera_rig.set_process(false)
				game.audio.muted = true
				game._other_ai.append(game.AI_STRATEGY.new(0))
				var casts: Array[int] = [0, 0, 0, 0]
				while not game.finished and game.elapsed < 240.0:
					var previous: Array = game.faction_skills[frog_side].cooldowns.duplicate()
					game.simulate(0.25)
					for i: int in 4:
						if game.faction_skills[frog_side].cooldowns[i] > previous[i] + 0.001:
							casts[i] += 1
					if int(game.elapsed * 4.0) % 40 == 0:
						await process_frame
				var owned: Array[int] = [0, 0]
				var population: Array[float] = [float(game.marches.total_for(0)), float(game.marches.total_for(1))]
				for building: WarBuilding in game.buildings:
					if building.faction >= 0:
						owned[building.faction] += 1
						population[building.faction] += building.population
				var result := {"map": definition.map_id, "opponent": opponent, "frog_side": frog_side, "seconds": snappedf(game.elapsed, 0.1), "finished": game.finished, "buildings": owned, "population": population, "frog_casts": casts}
				results.append(result)
				print("FROG_MATCH ", JSON.stringify(result))
	await game.prepare_shutdown()
	assert(DirAccess.make_dir_recursive_absolute("res://.local/frog") == OK)
	var file := FileAccess.open("res://.local/frog/balance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"settings": settings, "matches": results}, "\t"))
	file.close()
	quit()
