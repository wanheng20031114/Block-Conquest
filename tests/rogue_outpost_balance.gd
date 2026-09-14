extends "res://tests/rogue_battle_balance.gd"
## Comparable first-layer samples using the established automatic assault driver.
## This measures three starting armies; it does not assert player-facing balance.

func _run() -> void:
	create_timer(400.0, true, false, true).timeout.connect(func(): quit(3))
	session = root.get_node("Session")
	Engine.physics_ticks_per_second = 120
	Engine.time_scale = 4.0
	var map_hash: String = FileAccess.get_sha256("res://scenes/rogue/battle_outpost_map.tscn")
	for pack: String in ["steady", "ranged", "mobile"]:
		await _case("outpost", pack)
		var record: Dictionary = results.back()
		record["strategy"] = "ranged"
		record["seed"] = 24681
		record["enemy_total"] = game.enemy_total
		record["reinforcements"] = game.enemy_reinforcements
		record["initial_units"] = session.rogue.state.deployed_units().size()
		record["casualties"] = int(record.initial_units) - int(record.survivors)
		record["map_sha256"] = map_hash
		record["balance_status"] = "automated assault only; not verified player balance"
		print("ROGUE_OUTPOST_CASE ", JSON.stringify(record))
	var file := FileAccess.open("res://artifacts/rogue_outpost_ai_playtest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 30
	print("ROGUE_OUTPOST_PLAYTEST ", JSON.stringify(results))
	quit()
