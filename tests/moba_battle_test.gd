extends SceneTree
## Long native duel: no forced damage, scripted deaths or free gold.
var game: Node3D
var failures: Array[String] = []
var samples: Array = []
var peak_army: int = 0
var next_sample: float = 30
var next_audit: float = 1
## Fort durability and firepower increased substantially; require a completed
## push through all four defensive tiers within a bounded fifteen-minute match.
const MATCH_LIMIT := 900.0

func _initialize() -> void: run.call_deferred()

func run() -> void:
	seed(71032)
	DirAccess.make_dir_recursive_absolute("res://.local/moba-test1")
	create_timer(MATCH_LIMIT + 60, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.edge_scroll = false
	game.camera_rig.set_process(false)
	while game.elapsed < MATCH_LIMIT and not game.finished:
		await physics_frame
		peak_army = maxi(peak_army, game.army_counts[0]+game.army_counts[1])
		if game.elapsed >= next_audit:
			next_audit += 1
			var counts := PackedInt32Array([0,0])
			for unit: BattleUnit in game.unit_container.get_children():
				if not unit.alive: continue
				if not unit is HeroUnit: counts[unit.owner_id] += 1
				if not unit.position.is_finite(): failures.append("non-finite unit position")
			if counts != game.army_counts: failures.append("army accounting drift")
			if game.army_counts[0] > 240 or game.army_counts[1] > 240: failures.append("population cap exceeded")
			if game.players[0].gold < 0 or game.players[1].gold < 0: failures.append("negative balance")
		if game.elapsed >= next_sample:
			next_sample += 30
			var forts := [0,0]
			for building: BattleBuilding in game.get_node("Buildings").get_children():
				if building.alive: forts[building.owner_id] += 1
			var row := {"seconds":snappedf(game.elapsed,.1), "army":Array(game.army_counts), "forts":forts, "gold":[game.players[0].gold,game.players[1].gold], "plays":Array(game.card_plays), "orders":game.get_node("Director").orders_issued}
			row["defense_hp"] = []
			for building: BattleBuilding in game.get_node("Buildings").get_children():
				if building.owner_id == 0 and building.alive: row.defense_hp.append([building.building_type, snappedf(building.hp, 1)])
			if is_instance_valid(game.heroes[1]) and game.heroes[1].alive:
				row["bot_hero"] = {"x": snappedf(game.heroes[1].position.x, .1), "hp": snappedf(game.heroes[1].hp, 1), "shots": game.heroes[1].weapon.shots_fired}
			samples.append(row)
			print("MOBA_BATTLE ",JSON.stringify(row))
	if not game.finished: failures.append("unopposed bot could not break all reinforced defenses within fifteen minutes")
	if game.card_plays[1] < 3: failures.append("bot did not use earned gold for reinforcement")
	if game.earned_gold[0] <= 0 or game.earned_gold[1] <= 0: failures.append("both sides must earn bounty")
	var result := {"duration":game.elapsed,"finished":game.finished,"peak_army":peak_army,"samples":samples,"failures":failures}
	FileAccess.open("res://.local/moba-test1/battle-test.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MOBA_BATTLE_DONE ",JSON.stringify(result))
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
