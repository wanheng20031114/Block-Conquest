extends SceneTree
## Native simulation and input contracts for the standalone card / hero scenario.
var game: Node3D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func frames(count: int) -> void:
	for index: int in count: await physics_frame

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://.local/moba-test1")
	create_timer(110, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.edge_scroll = false
	game.get_node("Director").card_in = 10000
	game.heroes[1].set_physics_process(false)
	check(game.map_size == Vector2(200,56), "authored long narrow map")
	check(game.get_node("Buildings").get_child_count() == 10, "five fixed structures per side")
	check(game.hands[0].slots.size() == 5 and game.players[0].gold == 240, "five cards and starting gold")
	check(game.bases[0].max_hp == 2200 and BalanceCatalog.building("headquarters").hp != 2200, "scenario fort stats do not mutate RTS resources")
	for owner: int in 2:
		var sign_x: float = -1 if owner == 0 else 1
		check(game.bases[owner].position.x == sign_x*87, "mirrored HQ")
		check(game.fronts[owner][2][0].position.x == sign_x*61, "mirrored fortress")
		check(game.fronts[owner][1][0].position.x == sign_x*37, "mirrored castle")
		check(game.fronts[owner][0][0].position == Vector3(sign_x*15,0,-9) and game.fronts[owner][0][1].position == Vector3(sign_x*15,0,9), "paired towers")
	while game.elapsed < 7.9: await physics_frame
	check(game.army_counts[0] == 0, "no early wave")
	while game.wave_counts[0] == 0: await physics_frame
	check(absf(game.elapsed - 8.0) <= .04, "first wave at exactly eight seconds")
	var composition: Dictionary = {}
	for unit: BattleUnit in game.unit_container.get_children():
		if unit.owner_id == 0 and not unit is HeroUnit: composition[unit.unit_type] = int(composition.get(unit.unit_type,0)) + 1
	check(composition == {"spearman": 2, "archer": 3, "swordsman": 1}, "agreed wave composition")
	var first_uid: int = game.hands[0].slots[0].uid
	check(game.play_card(0,0,first_uid), "valid army card summons immediately")
	check(game.players[0].gold == 120 and game.army_counts[0] == 10, "one charge for four spearmen")
	check(not game.play_card(0,0,first_uid) and game.players[0].gold == 120, "stale card cannot replay")
	check(not game.play_card(0,1,game.hands[0].slots[1].uid), "insufficient gold rejected")
	var last: BattleUnit = game.unit_container.get_child(game.unit_container.get_child_count()-1)
	check(last.position.x < -70 and last.order == BattleUnit.Order.ATTACK_MOVE, "card troops originate at own HQ with autonomous orders")
	game.select_entities([last, game.local_hero()])
	check(game.selection == [game.local_hero()], "army excluded from player selection")
	check(not game.submit_local({"kind":"stop", "units":[last.entity_id]}).ok, "army commands rejected")
	var controlled: MobaHero = game.local_hero()
	check(game.submit_local({"kind":"move", "units":[controlled.entity_id], "at":[-76,0,4]}).ok, "hero command accepted by native validator")
	await frames(30)
	check(controlled.position.distance_to(Vector3(-80,0,0)) > 1, "RTS hero actually moves")
	controlled.stop()
	var clock: float = game.elapsed
	var refill: float = game.hands[0].slots[0].remaining
	game.set_running(false)
	await frames(45)
	check(game.elapsed == clock and game.hands[0].slots[0].remaining == refill, "pause freezes waves and card refill")
	game.set_running(true)
	await frames(46)
	check(game.hands[0].slots[0].card != null and game.hands[0].slots[0].uid != first_uid, "random refill gets a new identity")
	check(not game.play_card(0,0,first_uid), "refilled slot rejects old drag identity")
	# A full or physically blocked spawn never spends money or consumes a card.
	var saved_gold: int = game.players[0].gold
	game.players[0].gold = 1000
	var saved_count: int = game.army_counts[0]
	game.army_counts[0] = game.ARMY_CAP
	var uid: int = game.hands[0].slots[1].uid
	check(not game.play_card(0,1,uid) and game.players[0].gold == 1000 and game.hands[0].slots[1].uid == uid, "population cap is atomic")
	game.army_counts[0] = saved_count
	var saved_base: Vector3 = game.bases[0].position
	game.bases[0].position = Vector3(300,0,0)
	check(not game.play_card(0,1,uid) and game.players[0].gold == 1000 and game.hands[0].slots[1].uid == uid, "blocked exit is atomic")
	game.bases[0].position = saved_base
	game.players[0].gold = saved_gold
	# Native healing, timing, aura filtering and additive movement modifiers.
	var hero: MobaHero = game.local_hero()
	hero.stop()
	hero.hp = 50
	check(game.cast_skill(0) and hero.recovery_cooldown == 20, "E cooldown begins immediately")
	check(not game.cast_skill(0), "E cannot restart active healing")
	await frames(28)
	check(hero.hp == 50, "E does not heal before the first full second")
	await frames(3)
	check(hero.hp == 75, "E first tick restores 25")
	await frames(120)
	check(hero.hp == 175 and hero.recovery_ticks == 0 and absf(hero.recovery_cooldown-15) < .08, "E five ticks and independent twenty-second cooldown")
	var near: BattleUnit = game.spawn_unit("swordsman",0,hero.position+Vector3(0,0,2.7))
	var far: BattleUnit = game.spawn_unit("archer",0,hero.position+Vector3(0,0,-3.1))
	var enemy: BattleUnit = game.spawn_unit("archer",1,hero.position+Vector3(2.5,0,0))
	enemy.max_hp = 10000
	enemy.hp = 10000
	for unit: BattleUnit in [near,far,enemy]:
		unit.set_meta("moba_lane",1)
		unit.set_meta("moba_objective",game.get_node("Director").objective_for(unit.owner_id,1).entity_id)
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	check(game.cast_skill(1) and hero.morale_cooldown == 25, "R starts its independent cooldown")
	check(is_equal_approx(hero.speed,5.25) and is_equal_approx(near.speed,near._stats.speed*1.25), "R boosts self and nearby allies")
	check(far.movement_multiplier == 1 and enemy.movement_multiplier == 1, "R excludes outside radius and hostile units")
	game.get_node("StatusEffects").apply_morale(hero)
	check(near.movement_multiplier == 1.25, "morale refresh does not stack")
	hero.speed_boost_remaining = 1
	await frames(2)
	check(is_equal_approx(hero.speed,6.3), "morale composes with existing potion movement")
	await frames(90)
	check(near.speed == near._stats.speed and is_equal_approx(hero.speed,4.2), "morale expires without modifying base stats")
	# No last hit is required; each death resolves once, including native troop attacks.
	var gold: int = game.players[0].gold
	var bounty := maxi(5, roundi(enemy._stats.cost*.2))
	enemy._apply_damage(9999, null)
	check(game.players[0].gold == gold+bounty, "enemy soldier death pays gold without player last hit")
	game.on_entity_died(enemy)
	check(game.players[0].gold == gold+bounty, "duplicate death cannot mint gold")
	# RTS and first-person share this one hero and weapon cooldown; no reload ever starts.
	hero.stop()
	hero.position = Vector3(-80,0,12)
	game.hero_controller.set_first_person(true)
	game.hero_controller.capture_mouse(false)
	check(game.hero_controller.first_person and hero.directly_controlled, "F5 enters native direct control")
	check((game.hero_controller.camera.cull_mask & HeroUnit.BODY_LAYER) == 0 and game.heroes[1].health_bar.layers == 1, "only own body hidden in first person")
	check(game.get_node("Audio")._listener == game.hero_controller.camera.get_node("Listener"), "spatial audio culling follows first-person listener")
	hero.weapon.cooldown = 0
	var shots: int = hero.weapon.shots_fired
	for index: int in 16:
		while hero.weapon.cooldown > .000001: await physics_frame
		hero.fire_direction(Vector3.UP)
		check(hero.weapon.shots_fired == shots+index+1 and hero.weapon.reload_remaining == 0, "infinite ammo shot %d"%index)
	check(not hero.weapon.begin_reload(), "manual reload disabled in this mode")
	game.hero_controller.set_first_person(false)
	check(not hero.directly_controlled and game.local_hero() == hero, "F5 returns the same hero to RTS")
	# Hero death has no bounty, exits FPS, and reuses the spawn reservation path.
	game.hero_controller.set_first_person(true)
	gold = game.players[1].gold
	hero._apply_damage(9999, null)
	check(game.local_hero() == null and not game.hero_controller.first_person and game.players[1].gold == gold, "hero death exits control without soldier bounty")
	var dead_at: float = game.elapsed
	while game.local_hero() == null and game.elapsed-dead_at < 16: await physics_frame
	check(game.local_hero() != null and game.local_hero().hp == 200 and game.elapsed-dead_at >= 15-.04, "hero respawns after fifteen seconds")
	game.bases[1].receive_damage(99999, null)
	check(game.finished and not game.running and game.hud.get_node("%Modal").visible, "HQ destruction ends match and shows result")
	clock = game.elapsed
	await frames(30)
	check(game.elapsed == clock, "finished match cannot keep producing waves")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	check(get_nodes_in_group("entities").is_empty(), "all battle entities released on exit")
	print("MOBA_TEST1 ", checks, " checks; ", failures.size(), " failures")
	var result := {"checks":checks,"failures":failures}
	FileAccess.open("res://.local/moba-test1/tests.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	quit(0 if failures.is_empty() else 1)
