extends SceneTree
## Independent real-projectile combat, authority construction, UI and lifecycle.
const OUT := "res://.local/defenses/castle/"
var checks := 0
var failures: Array[String] = []
var game: Node3D
var shots: Array[Dictionary] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func settle() -> void:
	await physics_frame
	await process_frame
	await process_frame
func _run() -> void:
	create_timer(80,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var definition := BalanceCatalog.building("castle")
	check(definition.hp == 3600 and definition.cost == 950 and definition.build_seconds == 55,"castle durability and economy")
	check(definition.damage == 28 and definition.cooldown == 2.8 and definition.range == 12.5 and definition.weapon_count == 3,"three independent 28 damage guns")
	check(definition.melee_armor == 12 and definition.ranged_armor == 12 and definition.produces.is_empty(),"castle armor and defensive role")
	check(not BalanceCatalog.BUILDINGS.has("heavy_fortress"),"fortress remains unimplemented")
	game.set_paint_kind("castle")
	check(game.hud.get_node("%BuildingKinds/castle").button_pressed,"castle has native sandbox placement button")
	var at := Vector3.ZERO
	var found := false
	for x: int in range(-24,24,9):
		for z: int in range(-24,24,9):
			if not found and game.placement_valid(Vector3(x,0,z),"castle"):
				at = Vector3(x,0,z); found = true
	check(found and game.place_units(at) == 1,"place castle on real navigable terrain")
	var castle: BattleBuilding = game.get_node("Buildings").get_child(0)
	check(castle.artillery.guns.size() == 3 and castle.weapons.size() == 3,"scene guns match authority weapon states")
	check(castle._stats.size.x == 9 and castle._stats.size.z == 8,"headquarters-sized footprint")
	check(not game.placement_valid(at,"cannon_tower"),"immediate castle footprint reserves space")
	await settle()
	check(not game.placement_valid(at,"swordsman") and not game.get_node("ConstructionNavigation").contains_walkable_point(at),"paused castle stays a physical and navigation obstacle")
	castle.rotation.y = PI*.5
	check(castle.get_footprint_size().is_equal_approx(Vector3(8,8.05,9)),"rotated castle footprint matches collision box")
	castle.rotation.y = 0
	game.set_placing(false)
	game.select_entities([castle])
	game.hud.refresh()
	check(game.hud.get_node("UnitPanel")._stats_text(castle).contains("28 × 3") and game.hud.get_node("UnitPanel")._stats_text(castle).contains("近甲 12"),"sandbox displays every gun and actual armor")
	var targets: Array[BattleUnit] = []
	for i: int in 5:
		var unit: BattleUnit = game.spawn_unit("war_elephant",1,at+Vector3((i-2)*2.7,0,-11))
		targets.append(unit)
	var friend: BattleUnit = game.spawn_unit("swordsman",0,at+Vector3(0,0,-7))
	game.set_running(true)
	game.set_physics_process(false)
	castle.set_physics_process(false)
	castle.artillery.set_manual()
	for unit: BattleUnit in game.get_node("Units").get_children():
		unit.set_physics_process(false); unit.navigation_agent.avoidance_enabled = false
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.set_physics_process(false)
	pool.launched.connect(func(flight: ProjectileFlight):
		var origin_index := -1
		for i: int in 3:
			if flight._start.distance_to(castle.get_projectile_origin(i)) < .0001: origin_index = i
		shots.append({"origin":origin_index,"target":flight._target,"time":game.elapsed}))
	await settle()
	for count: int in [1,2,3,5]:
		for i: int in 5:
			targets[i].alive = i < count
			targets[i].hp = targets[i].max_hp
		shots.clear(); pool.reset_all()
		castle._scan_time = 0
		for weapon: BuildingWeaponState in castle.weapons: weapon.cooldown = 0
		castle._physics_process(.8)
		check(shots.size() == 3,"three independently ready guns fire with %d targets" % count)
		var unique: Array = []
		var origins: Array = []
		for shot: Dictionary in shots:
			if shot.target not in unique: unique.append(shot.target)
			origins.append(shot.origin)
		check(unique.size() == mini(count,3),"spread first, focus when fewer targets: %d" % count)
		check(origins == [0,1,2],"each projectile begins at its corresponding muzzle: %d" % count)
		pool._physics_process(1.0)
		var lost: float = 0
		for i: int in count: lost += targets[i].max_hp-targets[i].hp
		check(lost == 75 and friend.hp == friend.max_hp,"three 25-damage hits without splash or friendly damage: %d" % count)
	# One assigned target per gun; arbitrary different timers prove there is no volley clock.
	for unit: BattleUnit in targets: unit.alive = true; unit.hp = unit.max_hp
	shots.clear(); pool.reset_all()
	castle._scan_time = 100
	for i: int in 3:
		castle.weapons[i].target = targets[i]
		castle.weapons[i].cooldown = [0.0,.5,1.1][i]
		castle.artillery.guns[i].aim_at(targets[i].global_position+Vector3.UP,1)
	castle._physics_process(.01)
	check(shots.size() == 1 and shots[0].origin == 0,"first gun fires while other two reload")
	castle._physics_process(.5)
	check(shots.size() == 2 and shots[1].origin == 1,"second gun fires on its own timer")
	castle._physics_process(.6)
	check(shots.size() == 3 and shots[2].origin == 2,"third gun fires on its own timer")
	var remaining: float = castle.weapons[0].cooldown
	castle._acquire_weapon_targets()
	check(castle.weapons[0].cooldown == remaining,"reacquisition does not reset cooldown")
	castle._scan_time = 100
	castle._physics_process(1.69)
	check(shots.size() == 3,"no early repeat before each gun's full cooldown")
	castle._physics_process(.011)
	check(shots.size() == 4 and shots[3].origin == 0,"only first gun becomes ready after 2.8 seconds")
	pool.reset_all(); shots.clear()
	for weapon: BuildingWeaponState in castle.weapons:
		weapon.target = targets[0]; weapon.cooldown = 0
	targets[0].position = at+Vector3(0,0,-(4+12.5+targets[0].radius))
	check(castle._can_shoot_target(targets[0]),"range uses castle edge and victim radius")
	targets[0].position.z -= .02
	castle._physics_process(.1)
	check(shots.is_empty(),"every gun rejects target leaving range between scans")
	check(not castle._can_shoot_target(friend),"allied target rejected")
	targets[0].position = at+Vector3(0,0,-10)
	castle.under_construction = true
	castle._physics_process(3)
	check(shots.is_empty(),"unfinished castle cannot fire")
	castle.under_construction = false
	game.set_running(false)
	await create_timer(.1).timeout
	check(shots.is_empty(),"sandbox pause holds entire battery")
	game.set_running(true)
	castle.set_physics_process(false)
	for i: int in 3: castle.artillery.guns[i].aim_at(targets[0].global_position+Vector3.UP,1)
	pool.launched.connect(func(_flight): castle.receive_damage(4000),CONNECT_ONE_SHOT)
	castle._physics_process(.01)
	check(shots.size() == 1 and not castle.alive,"synchronous destruction during release cancels remaining guns")
	var before: float = targets[0].hp
	pool._physics_process(1)
	check(targets[0].hp == before-25,"already launched projectile survives destruction")
	game.clear_units()
	await settle()
	check(game.get_node("Buildings").get_child_count() == 0 and game.get_node("ConstructionNavigation").contains_walkable_point(at),"sandbox clear retires castle and releases navigation")
	await game.prepare_shutdown()
	game.queue_free(); await settle()
	root.get_node("Session").start_offline("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	while root.get_node("Session").transition.busy: await process_frame
	game.tests_running = true
	game.bots.clear(); game.set_physics_process(false)
	game.get_node("IncomeTimer").stop(); game.get_node("EnemyTimer").stop()
	for unit: BattleUnit in get_nodes_in_group("units"):
		unit.stop(); unit.set_physics_process(false); unit.navigation_agent.avoidance_enabled = false
	for building: BattleBuilding in get_nodes_in_group("buildings"):
		building.set_physics_process(false); building.production.set_physics_process(false)
	var player: PlayerState = game.get_player(0)
	player.gold = 3000
	var worker: BattleUnit = game.owned_entities(0,"units")[0]
	game.select_entities([worker]); game.hud.refresh()
	check(game.hud._actions.size() == 6 and game.hud._actions[5].kind == "action_page","worker buildings paginate through existing six slots")
	game.hud._on_recruit(5)
	check(game.hud._actions[0].id == "castle" and game.hud._actions[1].id == "headquarters","castle and headquarters accessible on second page")
	game.hud._on_recruit(0)
	check(game.build_mode and game.build_kind == "castle","visible castle action dispatches matching build command")
	var location: Vector3 = game.find_build_location(0,"castle",game.headquarters.global_position)
	check(location.is_finite(),"normal map finds legal headquarters-sized castle site")
	player.gold = 949
	check(game.placement_error(location,0,"castle").contains("金币不足"),"castle requires 950 gold")
	player.gold = 3000
	var result: Dictionary = game.command_bus.execute({"kind":"build","building_type":"castle","units":[worker.entity_id],"at":[location.x,0,location.z],"seq":game.next_command_sequence(0)},0)
	check(result.ok and player.gold == 2050 and player.paid_tower_count == 0,"authority pays exact castle price without arrow progression")
	var site: BattleBuilding = game.entities_by_id[result.entity_id]
	site.set_physics_process(false)
	check(site.hp == 360 and site.construction_refund() == 950,"castle starts at ten percent HP and full unbuilt refund")
	worker.position = site.get_attack_position(site.position+Vector3(10,0,0))+Vector3(1,0,0)
	site.try_claim_builder(worker)
	site.contribute_work(worker,27.5)
	check(is_equal_approx(site.construction_progress,.5) and site.hp == 1980 and site.construction_refund() == 475,"half construction has exact HP and refund")
	site.receive_damage(100)
	site.contribute_work(worker,27.5)
	check(site.is_constructed and site.hp == 3500,"55 second construction preserves received damage")
	game.select_entities([site]); game.hud.refresh()
	check(game.hud._actions[0].kind == "demolish" and game.hud.selected_stats.text.contains("近甲12") and game.hud.selected_stats.text.contains("3门炮"),"normal HUD displays actual armor and gun count with demolition action")
	var bot := SkirmishBot.new(game,1)
	bot._memory = {1:{"building":true,"kind":"castle"}}
	check(bot._known_fortifications() == 1,"AI recognizes castle fortification")
	check("castle" in FogOfWar.REVEAL_KINDS,"existing core-loss reveal includes surviving castles")
	check(site.demolish() and site.construction_refund() == 0,"completed castle demolishes without refund")
	await game.prepare_shutdown()
	game.queue_free(); await settle()
	game = null
	FileAccess.open(OUT+"functional.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CASTLE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
