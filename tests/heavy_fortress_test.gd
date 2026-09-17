extends SceneTree
## Real construction, independent cannons, impact boundary and alliance damage.
const OUT := "res://.local/defenses/heavy_fortress/"
var checks := 0
var failures: Array[String] = []
var game: Node3D
var shots: Array[Dictionary] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame
func freeze_unit(unit: BattleUnit) -> void:
	unit.set_physics_process(false)
	unit.navigation_agent.avoidance_enabled = false
func _run() -> void:
	create_timer(85,true,false,true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	var definition := BalanceCatalog.building("heavy_fortress")
	check(definition.hp == 5400 and definition.cost == 1800 and definition.build_seconds == 80,"fortress durability and construction economy")
	check(definition.damage == 80 and definition.cooldown == 4.5 and definition.range == 13 and definition.weapon_count == 2,"two independently reloading heavy guns")
	check(definition.splash_radius == 2.4 and definition.projectile == "cannon" and definition.bonuses.is_empty() and definition.armor_penetration == 0,"authored 2.4 blast without hidden bonus or penetration")
	check(definition.melee_armor == 15 and definition.ranged_armor == 15 and definition.produces.is_empty(),"fortress armor and defensive role")
	check(BalanceCatalog.building("castle").splash_radius == 0 and BalanceCatalog.building("cannon_tower").splash_radius == 0 and BalanceCatalog.unit("catapult").splash_radius == 2.7,"existing single-target and catapult radii preserved")
	game.set_paint_kind("heavy_fortress")
	check(game.hud.get_node("%BuildingKinds/heavy_fortress").button_pressed,"saved sandbox placement entry")
	var at := Vector3.ZERO
	var found := false
	for x: int in range(-20,21,8):
		for z: int in range(-20,21,8):
			if not found and game.placement_valid(Vector3(x,0,z),"heavy_fortress"):
				at = Vector3(x,0,z); found = true
	check(found and game.place_units(at) == 1,"place large fortress on real map")
	var fortress: BattleBuilding = game.get_node("Buildings").get_child(0)
	check(fortress.artillery.guns.size() == 2 and fortress.weapons.size() == 2,"native gun hierarchy matches authority states")
	check(definition.size.x == 12 and definition.size.z == 11,"12 by 11 footprint exceeds headquarters")
	check(not game.placement_valid(at,"cannon_tower"),"placement reserves the entire site immediately")
	await settle()
	check(not game.placement_valid(at,"swordsman") and not game.get_node("ConstructionNavigation").contains_walkable_point(at),"paused fortress blocks physics and navigation")
	fortress.rotation.y = PI*.5
	check(fortress.get_footprint_size().is_equal_approx(Vector3(11,7.2,12)),"quarter rotation swaps authored footprint axes")
	fortress.rotation.y = 0
	game.set_placing(false)
	game.select_entities([fortress]); game.hud.refresh()
	check(game.hud.get_node("UnitPanel")._stats_text(fortress).contains("80 × 2") and game.hud.get_node("UnitPanel")._stats_text(fortress).contains("近甲 15"),"selection shows actual per-gun damage and armor")
	var center := at+Vector3(0,0,-12)
	var targets: Array[BattleUnit] = []
	for offset: Vector3 in [Vector3.ZERO,Vector3(1.5,0,0),Vector3(0,0,3.55),Vector3(-3.57,0,0)]:
		targets.append(game.spawn_unit("war_elephant",1,center+offset))
	var friend: BattleUnit = game.spawn_unit("war_elephant",0,center+Vector3(0,0,-1))
	# A different owner with the same alliance is also immune.
	var ally_player: PlayerState = game.get_player(2)
	ally_player.alliance_id = fortress.alliance_id
	var ally: BattleUnit = game.spawn_unit("swordsman",2,center+Vector3(0,0,1))
	var enemy_wall: BattleBuilding = game.spawn_building("cannon_tower",1,center+Vector3(5.92,0,0))
	enemy_wall.rotation.y = PI*.25
	var far_wall: BattleBuilding = game.spawn_building("cannon_tower",1,center+Vector3(0,0,-6.01))
	far_wall.rotation.y = PI*.25
	game.set_running(true); game.set_physics_process(false)
	for building: BattleBuilding in game.get_node("Buildings").get_children(): building.set_physics_process(false)
	for unit: BattleUnit in game.get_node("Units").get_children(): freeze_unit(unit)
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.set_physics_process(false)
	fortress.artillery.set_manual()
	pool.launched.connect(func(flight: ProjectileFlight):
		var origin := -1
		for i: int in 2:
			if flight._start.distance_to(fortress.get_projectile_origin(i)) < .0001: origin = i
		shots.append({"origin":origin,"target":flight._target}))
	await settle()
	var payload := DamageResolver.snapshot(definition,0,fortress.owner_id,fortress.alliance_id)
	game.spawn_projectile(fortress,targets[0],payload,"cannon")
	pool.set_physics_process(false); pool._physics_process(1)
	check(targets[0].hp == 283 and targets[1].hp == 283 and targets[2].hp == 283,"center, inner and exact 2.4 edge each take 77 damage once")
	check(targets[3].hp == 360,"target 0.02 beyond blast boundary is unharmed")
	check(friend.hp == 360 and ally.hp == ally.max_hp,"own and different allied owner immune to blast")
	check(enemy_wall.hp == 1430 and far_wall.hp == 1500,"rotated building uses nearest wall, not distant center, at blast edge")
	# The launch snapshot owns its radius even when an isolated definition changes.
	var copy: BuildingDefinition = definition.duplicate()
	var snapshot := DamageResolver.snapshot(copy,0,0,fortress.alliance_id)
	copy.splash_radius = 0
	check(snapshot.splash_radius == 2.4 and definition.splash_radius == 2.4,"blast radius captured independently at launch")
	pool.reset_all(); shots.clear()
	# Move victims apart: each gun gets a distinct target and neither blast overlaps.
	for i: int in 4:
		targets[i].hp = 360
		targets[i].position = center+Vector3(-4+i*8,0,0)
		targets[i].alive = i < 2
	await settle()
	fortress._scan_time = 100
	for i: int in 2:
		fortress.weapons[i].target = targets[i]
		fortress.weapons[i].cooldown = [0.0,1.2][i]
		fortress.artillery.guns[i].aim_at(targets[i].global_position+Vector3.UP,1)
	fortress._physics_process(.01)
	check(shots.size() == 1 and shots[0].origin == 0,"ready left cannon fires while right cannon reloads")
	fortress._physics_process(1.2)
	check(shots.size() == 2 and shots[1].origin == 1 and shots[0].target != shots[1].target,"right cannon releases separately from its own muzzle")
	pool._physics_process(1)
	check(targets[0].hp == 283 and targets[1].hp == 283,"separate targets each receive one heavy shell")
	var remaining: float = fortress.weapons[0].cooldown
	fortress._acquire_weapon_targets()
	check(fortress.weapons[0].cooldown == remaining,"new target assignment preserves per-gun cooldown")
	fortress._scan_time = 100
	fortress._physics_process(3.29)
	check(shots.size() == 2,"no repeat before full 4.5 seconds")
	fortress._physics_process(.011)
	check(shots.size() == 3 and shots[2].origin == 0,"only left cannon ready at its own next deadline")
	pool.reset_all(); shots.clear()
	# One remaining enemy permits focus fire; no shared volley timer is introduced.
	targets[1].alive = false
	fortress._acquire_weapon_targets()
	check(fortress.weapons[0].target == targets[0] and fortress.weapons[1].target == targets[0],"single target may be shared by both guns")
	targets[0].position = at+Vector3(0,0,-(5.5+13+targets[0].radius))
	check(fortress._can_shoot_target(targets[0]),"firing range measured from fortress wall to victim edge")
	targets[0].position.z -= .02
	for weapon: BuildingWeaponState in fortress.weapons: weapon.cooldown = 0
	fortress._physics_process(.1)
	check(shots.is_empty(),"all guns reject targets outside range between scans")
	targets[0].position = center
	fortress.under_construction = true
	fortress._physics_process(5)
	check(shots.is_empty(),"unfinished fortress cannot attack")
	fortress.under_construction = false
	game.set_running(false)
	await create_timer(.05).timeout
	check(shots.is_empty(),"sandbox pause suspends gun logic")
	game.set_running(true); fortress.set_physics_process(false)
	for unit: BattleUnit in game.get_node("Units").get_children(): freeze_unit(unit)
	for i: int in 2: fortress.artillery.guns[i].aim_at(targets[0].global_position+Vector3.UP,1)
	await settle()
	pool.launched.connect(func(_flight): fortress.receive_damage(6000),CONNECT_ONE_SHOT)
	fortress._physics_process(.01)
	check(shots.size() == 1 and not fortress.alive,"destruction during release cancels unlaunched gun")
	var before: float = targets[0].hp
	pool.set_physics_process(false); pool._physics_process(1)
	check(targets[0].hp == before-77,"launched explosive remains effective after source death")
	game.clear_units(); await settle()
	check(game.get_node("Buildings").get_child_count() == 0 and game.get_node("ConstructionNavigation").contains_walkable_point(at),"clearing fortress releases navigation and collision")
	await game.prepare_shutdown(); game.queue_free(); await settle()
	await normal_construction()
	FileAccess.open(OUT+"functional.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("FORTRESS ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func normal_construction() -> void:
	root.get_node("Session").start_offline("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	while root.get_node("Session").transition.busy: await process_frame
	game.tests_running = true
	game.bots.clear(); game.set_physics_process(false)
	game.get_node("IncomeTimer").stop(); game.get_node("EnemyTimer").stop()
	for unit: BattleUnit in get_nodes_in_group("units"): unit.stop(); freeze_unit(unit)
	for building: BattleBuilding in get_nodes_in_group("buildings"):
		building.set_physics_process(false); building.production.set_physics_process(false)
	var player: PlayerState = game.get_player(0)
	player.gold = 5000
	var worker: BattleUnit = game.owned_entities(0,"units")[0]
	game.select_entities([worker]); game.hud.refresh()
	game.hud._on_recruit(5)
	check(game.hud._actions[1].id == "heavy_fortress","fortress accessible on second worker build page")
	game.hud._on_recruit(1)
	check(game.build_mode and game.build_kind == "heavy_fortress","native build action selects correct footprint")
	var location: Vector3 = game.find_build_location(0,"heavy_fortress",game.headquarters.global_position)
	check(location.is_finite(),"normal map supports a legal large fortress location")
	player.gold = 1799
	check(game.placement_error(location,0,"heavy_fortress").contains("金币不足"),"full 1800 gold required")
	player.gold = 5000
	var result: Dictionary = game.command_bus.execute({"kind":"build","building_type":"heavy_fortress","units":[worker.entity_id],"at":[location.x,0,location.z],"seq":game.next_command_sequence(0)},0)
	check(result.ok and player.gold == 3200 and player.paid_tower_count == 0,"authority spends 1800 without changing arrow tower progression")
	var site: BattleBuilding = game.entities_by_id[result.entity_id]
	site.set_physics_process(false)
	check(site.hp == 540 and site.construction_refund() == 1800,"site starts at ten percent HP and full unbuilt refund")
	worker.position = site.get_attack_position(site.position+Vector3(12,0,0))+Vector3(1,0,0)
	site.try_claim_builder(worker); site.contribute_work(worker,40)
	check(is_equal_approx(site.construction_progress,.5) and site.hp == 2970 and site.construction_refund() == 900,"half build after 40 seconds has exact HP and refund")
	site.receive_damage(100); site.contribute_work(worker,40)
	check(site.is_constructed and site.hp == 5300,"80 second construction preserves received damage")
	game.select_entities([site]); game.hud.refresh()
	check(game.hud._actions[0].kind == "demolish" and game.hud.selected_stats.text.contains("近甲15") and game.hud.selected_stats.text.contains("2门炮"),"normal HUD offers demolition and actual armor/gun stats")
	var bot := SkirmishBot.new(game,1)
	bot._memory = {1:{"building":true,"kind":"heavy_fortress"}}
	check(bot._known_fortifications() == 1 and "heavy_fortress" in FogOfWar.REVEAL_KINDS,"AI threat recognition and core-loss reveal include fortress")
	check(site.demolish() and site.construction_refund() == 0,"finished fortress demolition gives no refund")
	await settle()
	result = game.command_bus.execute({"kind":"build","building_type":"heavy_fortress","units":[worker.entity_id],"at":[location.x,0,location.z],"seq":game.next_command_sequence(0)},0)
	check(result.ok and player.gold == 1400,"another fortress costs the same fixed 1800")
	var cancel_site: BattleBuilding = game.entities_by_id[result.entity_id]
	cancel_site.set_physics_process(false)
	cancel_site.try_claim_builder(worker); cancel_site.contribute_work(worker,40)
	result = game.command_bus.execute({"kind":"cancel_site","target":cancel_site.entity_id,"seq":game.next_command_sequence(0)},0)
	check(result.ok and not cancel_site.alive and player.gold == 2300,"cancel command returns actual unbuilt 900 gold once")
	await game.prepare_shutdown(); game.queue_free(); await settle()
	game = null
