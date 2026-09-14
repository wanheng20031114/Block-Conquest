extends SceneTree
## Real barracks, command routing, population, technology and role consumers.
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func freeze(unit: BattleUnit) -> void:
	unit.stop()
	unit.set_physics_process(false)
	unit.navigation_agent.avoidance_enabled = false
func spawn(kind: String,at: Vector3,owner: int = 0) -> BattleUnit:
	var result: BattleUnit = game.spawn_unit(kind,owner,at)
	freeze(result)
	return result
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/crossbow-20260914"))
	create_timer(80,true,false,true).timeout.connect(func():quit(3))
	change_scene_to_file("res://scenes/main.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.tests_running = true
	game.bots.clear()
	game.get_node("IncomeTimer").stop()
	game.get_node("EnemyTimer").stop()
	for unit: BattleUnit in get_nodes_in_group("units"): freeze(unit)
	for structure: BattleBuilding in get_nodes_in_group("buildings"):
		structure.set_physics_process(false)
		structure.production.set_physics_process(false)
	var player: PlayerState = game.get_player(0)
	player.gold = 20000
	var at: Vector3 = game.find_build_location(0,"barracks",game.headquarters.position)
	check(at.is_finite(),"legal barracks placement")
	var barracks: BattleBuilding = game.spawn_building("barracks",0,at)
	barracks.set_physics_process(false)
	barracks.production.set_physics_process(false)
	game.get_node("ConstructionNavigation").refresh()
	for attempt: int in 180:
		if game.find_recruit_position("crossbowman",barracks).is_finite(): break
		await physics_frame
	check(game.find_recruit_position("crossbowman",barracks).is_finite(),"native barracks exit")
	game.select_entities([barracks])
	game.hud._refresh_actions()
	check(game.hud._actions.any(func(a: Dictionary): return a.kind=="recruit" and a.id=="crossbowman"),"crossbow clickable on barracks first page")
	var listed: Array[String] = []
	for page: int in 2:
		game.hud._action_page = page
		game.hud._refresh_actions()
		for action: Dictionary in game.hud._actions:
			if action.kind == "recruit": listed.append(action.id)
	check(listed.size()==9 and listed.has("crossbowman") and listed.has("light_cavalry") and listed.has("war_elephant"),"pagination retains all nine recruits")
	player.gold = 74
	check(not barracks.production.recruit("crossbowman").ok and player.gold==74,"insufficient gold")
	player.gold = 20000
	var original_supply: int = player.military_supply
	check(game.command_bus.execute({"kind":"recruit","target":barracks.entity_id,"unit_type":"crossbowman"},0).ok,"validated recruit command")
	check(player.gold==19925 and player.reserved_military_supply==1,"75 gold reserves one military population")
	barracks.production._physics_process(8.99)
	check(barracks.production.training.size()==1,"full nine seconds required")
	barracks.production._physics_process(.01)
	check(barracks.production.training.is_empty() and player.military_supply==original_supply+1 and player.reserved_military_supply==0,"single spawn converts population reservation")
	var crossbow: BattleUnit
	for unit: BattleUnit in game.owned_entities(0,"units"):
		if unit.unit_type=="crossbowman": crossbow=unit
	check(crossbow!=null and crossbow.hp==60 and crossbow._model.batch_parts.size()==12,"trained native model")
	freeze(crossbow)
	game.select_entities([crossbow])
	check(game.own_selected_units()==[crossbow] and game.own_selected_workers().is_empty(),"crossbow selection cannot build")
	game.hud.refresh()
	check(game.hud.selected_role.text.contains("远程步兵") and game.hud.selected_stats.text.contains("穿甲3"),"selected panel exposes class and penetration")
	barracks.production.recruit("crossbowman")
	var gold: int = player.gold
	check(barracks.production.cancel_training(0).ok and player.gold==gold+75 and player.reserved_military_supply==0,"refund and reservation release")
	player.military_supply = player.get_supply_limit()
	check(not barracks.production.recruit("crossbowman").ok,"population limit")
	player.military_supply = original_supply+1
	check(not game.headquarters.production.recruit("crossbowman").ok,"wrong producer rejected")
	var blockers: Array[BattleUnit] = []
	for attempt: int in 180:
		var exit_at: Vector3 = game.find_recruit_position("crossbowman",barracks)
		if not exit_at.is_finite(): break
		blockers.append(spawn("farmer",exit_at))
		await physics_frame
	check(not game.find_recruit_position("crossbowman",barracks).is_finite(),"blocked exit fixture")
	barracks.production.recruit("crossbowman")
	barracks.production._physics_process(9)
	check(barracks.production.training.size()==1 and player.reserved_military_supply==1,"finished job retained behind blocked exit")
	for blocker: BattleUnit in blockers: blocker.queue_free()
	await physics_frame
	await physics_frame
	barracks.production._physics_process(.3)
	check(barracks.production.training.is_empty() and player.reserved_military_supply==0,"cleared exit releases job once")
	var engineer := spawn("engineer",Vector3(3,0,0))
	var priest := spawn("priest",Vector3(-3,0,0))
	var farmer := spawn("farmer",Vector3(0,0,3))
	game.select_entities([crossbow,engineer,priest,farmer])
	check(game.own_selected_workers()==[farmer],"mixed selection only construction role can build")
	crossbow.hp=30
	check(priest.support.valid_target(crossbow) and not engineer.support.valid_target(crossbow),"healing recognizes ranged infantry but repair excludes it")
	check(engineer.support.enabled() and priest.support.enabled() and not farmer.support.enabled(),"support roles route into existing abilities")
	var bot := SkirmishBot.new(game,0)
	bot._refresh_own_army()
	check(crossbow in bot._army and engineer not in bot._army and priest not in bot._army,"AI keeps support out of attack army")
	check(bot._recruitment_role("crossbowman")=="archer","AI maps new ranged infantry into original counter strategy")
	bot._memory={100:{"building":false,"kind":"crossbowman","seen_at":0.0}}
	check(bot._composition().archer==1,"crossbow threat counted")
	var enemy_base: BattleBuilding = game.owned_entities(1,"buildings")[0]
	bot._visible_enemies.assign([enemy_base])
	bot._memory={enemy_base.entity_id:{"building":true,"kind":enemy_base.building_type,"position":enemy_base.global_position}}
	check(bot._attack_target(enemy_base.global_position,1)==enemy_base,"AI building targets never enter the unit catalogue")
	var enemy_worker := spawn("farmer",Vector3(1,0,0),1)
	var enemy_crossbow := spawn("crossbowman",Vector3(3,0,0),1)
	var enemy_siege := spawn("cannon",Vector3(4,0,0),1)
	bot._visible_enemies.assign([enemy_worker,enemy_crossbow])
	bot._memory.clear()
	for enemy: BattleUnit in [enemy_worker,enemy_crossbow,enemy_siege]:
		bot._memory[enemy.entity_id]={"building":false,"kind":enemy.unit_type,"position":enemy.global_position}
	check(bot._attack_target(Vector3.ZERO,10)==enemy_crossbow,"AI target priority preserves construction role penalty")
	bot._visible_enemies.append(enemy_siege)
	check(bot._attack_target(Vector3.ZERO,10)==enemy_siege,"AI target priority preserves siege family weighting")
	check(RogueCatalog.is_ranged_infantry("crossbowman") and not RogueCatalog.is_ranged_infantry("cannon"),"rogue class-dependent buffs use shared classification")
	player.complete_upgrade(BalanceCatalog.upgrade("attack_3"))
	player.complete_upgrade(BalanceCatalog.upgrade("cannon_range_1"))
	check(crossbow.attack_range==7 and crossbow._stats.armor_penetration==3,"research does not extend crossbow range or penetration")
	barracks.production.recruit("crossbowman")
	barracks.production.destroyed()
	check(barracks.production.training.is_empty() and player.reserved_military_supply==0,"producer destruction clears queue")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open("res://.local/crossbow-20260914/integration-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CROSSBOW_INTEGRATION ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
