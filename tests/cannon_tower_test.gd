extends SceneTree
## Real sandbox combat, authority construction, catalogue UI, and saved geometry.
const OUT := "res://.local/defenses/cannon_tower/"
var checks := 0
var failures: Array[String] = []
var game: Node3D
var shots: Array[Dictionary] = []

func _initialize() -> void:
	Engine.max_fps = 120
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)

func settle() -> void:
	await physics_frame
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(80, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_placing(false)
	game.set_physics_process(false)
	var definition := BalanceCatalog.building("cannon_tower")
	check(definition.hp == 1500 and definition.cost == 350 and definition.build_seconds == 30, "tower durability and construction economy")
	check(definition.projectile == "cannon" and definition.damage == 48 and definition.cooldown == 2.4 and definition.range == 12, "single cannon weapon definition")
	check(definition.bonuses.is_empty() and definition.armor_penetration == 0, "no hidden class bonus or penetration")
	check(BalanceCatalog.building("defense_tower").name == "箭塔", "existing tower is named Arrow Tower")
	check(not BalanceCatalog.BUILDINGS.has("castle") and not BalanceCatalog.BUILDINGS.has("heavy_fortress"), "later buildings remain behind individual acceptance gates")
	game.set_paint_kind("cannon_tower")
	check(game.hud.get_node("%BuildingKinds/cannon_tower").button_pressed and not game.hud.get_node("%CountRow").visible, "native sandbox cannon placement entry")
	var at := Vector3.ZERO
	for x: int in range(-20, 20, 6):
		for z: int in range(-20, 20, 6):
			if game.placement_valid(Vector3(x, 0, z), "cannon_tower"):
				at = Vector3(x, 0, z)
	check(game.place_units(at) == 1, "place completed cannon tower on real terrain")
	var tower: BattleBuilding = game.get_node("Buildings").get_child(0)
	check(tower._stats.size == Vector3(5, 5.2, 5) and tower.artillery != null, "native model and collision footprint")
	check(not tower.can_process(), "paused sandbox pauses buildings")
	check(not game.placement_valid(at, "cannon_tower"), "immediate placement reserves occupied footprint")
	await settle()
	check(not game.placement_valid(at, "swordsman"), "paused building remains a physics obstacle for troop placement")
	check(not game.get_node("ConstructionNavigation").contains_walkable_point(at), "building removes underlying navigation")
	game.set_faction(2)
	check(game.hud.get_node("ModelPreviews")._models.cannon_tower.get_node("Fabric").get_instance_shader_parameter("team_color") == FactionPalette.SANDBOX_COLORS[2], "portrait supports sandbox team colours")
	game.set_faction(0)
	game.set_placing(false)
	game.select_entities([tower])
	game.hud.refresh()
	check(game.hud.get_node("UnitPanel").visible, "shared selection panel accepts defensive building")
	var payload := DamageResolver.snapshot(definition, 0, 0, 0)
	for pair: Array in [["shield_guard", 41, 4], ["swordsman", 46, 3], ["knight", 41, 3], ["war_elephant", 45, 8], ["cannon", 46, 4]]:
		var victim := BalanceCatalog.unit(pair[0])
		var damage: float = DamageResolver.resolve(payload, victim, 0)
		check(damage == pair[1] and ceili(victim.hp / damage) == pair[2], "real damage and shots to defeat " + pair[0])
	var enemy: BattleUnit = game.spawn_unit("war_elephant", 1, at + Vector3(0, 0, -10))
	var neighbor: BattleUnit = game.spawn_unit("swordsman", 1, at + Vector3(.5, 0, -10.5))
	var friend: BattleUnit = game.spawn_unit("swordsman", 0, at + Vector3(-.5, 0, -9.5))
	game.set_running(true)
	game.set_physics_process(false)
	tower.set_physics_process(false)
	for unit: BattleUnit in [enemy, neighbor, friend]:
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	tower.artillery.animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.set_physics_process(false)
	pool.launched.connect(func(flight: ProjectileFlight): shots.append({"start": flight._start, "target": flight._target, "kind": flight._kind, "time": game.elapsed}))
	await settle()
	tower._target = enemy
	tower._scan_time = 100
	tower._cooldown = 0
	var muzzle: Vector3 = tower.get_projectile_origin()
	tower._physics_process(1.0 / 60)
	check(shots.size() == 1 and shots[0].kind == "cannon", "one attack launches one cannonball")
	check(shots[0].start.distance_to(tower.get_projectile_origin()) < .0001, "true muzzle has no legacy building origin offset")
	pool.set_physics_process(false)
	pool._physics_process(1.0)
	check(enemy.hp == enemy.max_hp - 45, "cannonball applies one ranged hit")
	check(neighbor.hp == neighbor.max_hp and friend.hp == friend.max_hp, "visual explosion has no splash or friendly damage")
	for tick: int in 23:
		game.elapsed += .1
		tower._physics_process(.1)
	check(shots.size() == 1, "cooldown prevents early repeat fire")
	game.elapsed += .101
	tower._physics_process(.101)
	check(shots.size() == 2, "next shot follows independent 2.4 second building cooldown")
	pool.reset_all()
	tower._cooldown = 0
	enemy.position = at + Vector3(0, 0, 10)
	await settle()
	tower._physics_process(1.0 / 60)
	check(shots.size() == 2, "opposite target waits for actual turret alignment")
	for tick: int in 70: tower._physics_process(1.0 / 60)
	check(shots.size() == 3 and tower.model_pivot.rotation == Vector3.ZERO, "turret rotates without rotating masonry")
	tower.artillery.sample_fire(.07)
	check(is_equal_approx(tower.artillery.get_node("Turret/Elevation/Barrel").position.z, .36), "saved animation has visible recoil")
	check(tower.artillery.muzzle.position == Vector3(0, 0, -2.445), "muzzle is parented to the recoiling barrel")
	tower.artillery.sample_fire(.9)
	check(tower.artillery.get_node("Turret/Elevation/Barrel").position == Vector3.ZERO, "recoil returns precisely to mount")
	pool.reset_all()
	enemy.position = at + Vector3(0, 0, -(2.5 + 12 + enemy.radius))
	check(tower._can_shoot_target(enemy), "range includes exact wall-to-unit-edge boundary")
	enemy.position.z -= .02
	check(not tower._can_shoot_target(enemy), "range rejects target beyond wall boundary")
	check(not tower._can_shoot_target(friend), "allied target cannot be shot")
	tower._target = enemy
	tower._cooldown = 0
	tower._physics_process(.1)
	check(shots.size() == 3, "expired target cannot fire between scans")
	var arrow: BattleBuilding = game.spawn_building("defense_tower", 0, at + Vector3(8, 0, 0))
	arrow.set_physics_process(false)
	var old_flight := ProjectileFlight.new()
	old_flight.initialize(game, arrow, enemy, DamageResolver.snapshot(arrow._stats, 0, 0, 0), "arrow")
	check(arrow.artillery == null and old_flight._start.distance_to(arrow.get_projectile_origin()) > 1.3, "old arrow origin and static model remain unchanged")
	old_flight.reset()
	var headquarters: BattleBuilding = game.spawn_building("headquarters", 0, at + Vector3(18, 0, 0))
	headquarters.rotation.y = PI * .5
	check(headquarters.get_footprint_size().is_equal_approx(Vector3(8, 6, 9)), "rotated headquarters navigation footprint matches collision")
	game.set_running(false)
	var launch_count := pool.launch_count
	await create_timer(.15).timeout
	check(pool.launch_count == launch_count, "sandbox pause freezes attack release")
	game.select_entities([tower])
	game.remove_selected()
	await settle()
	check(not is_instance_valid(tower) and game.get_node("ConstructionNavigation").contains_walkable_point(at), "removing selected tower releases geometry and navigation")
	game.clear_units()
	await settle()
	check(game.get_node("Buildings").get_child_count() == 0 and game.sandbox_unit_count == 0 and pool.active_flights.is_empty(), "clear sandbox releases troops buildings and projectiles")
	await game.prepare_shutdown()
	root.get_node("Session").start_offline("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	# The normal scene finishes its native two-physics-frame ready coroutine
	# after publishing match_ready. Let it finish before this fast manual test exits.
	await physics_frame
	await physics_frame
	await process_frame
	while root.get_node("Session").transition.busy: await process_frame
	game.tests_running = true
	game.bots.clear()
	game.set_physics_process(false)
	game.get_node("IncomeTimer").stop()
	game.get_node("EnemyTimer").stop()
	for unit: BattleUnit in get_nodes_in_group("units"):
		unit.stop(); unit.set_physics_process(false); unit.navigation_agent.avoidance_enabled = false
	for building: BattleBuilding in get_nodes_in_group("buildings"):
		building.set_physics_process(false); building.production.set_physics_process(false)
	var player: PlayerState = game.get_player(0)
	var bot := SkirmishBot.new(game, 1)
	bot._memory = {1:{"building":true,"kind":"cannon_tower"},2:{"building":true,"kind":"barracks"},3:{"building":false,"kind":"swordsman"}}
	check(bot._known_fortifications() == 1, "AI identifies cannon tower as a fortification without recruiting new buildings")
	var distant: BattleBuilding = game.spawn_building("cannon_tower", 1, Vector3(35,0,35))
	distant.set_physics_process(false)
	var fog: FogOfWar = game.get_node("FogOfWar")
	fog.tick(.2)
	check(not fog.entity_visible(0, distant), "unseen enemy tower stays hidden before faction reveal")
	fog.reveal_alliance_buildings(1)
	check(fog.entity_visible(0, distant), "losing core buildings reveals surviving cannon towers under existing victory rules")
	var worker: BattleUnit = game.owned_entities(0, "units")[0]
	player.gold = 2000
	var location: Vector3 = game.find_build_location(0, "cannon_tower", game.headquarters.global_position)
	check(location.is_finite(), "real construction finds valid 5 by 5 site")
	game.select_entities([worker]); game.hud.refresh()
	check(game.hud._actions.size() == 6 and game.hud._actions.any(func(action): return action.id == "cannon_tower"), "six native worker actions include cannon tower")
	game.set_build_mode(true, "cannon_tower")
	check(game.build_mode and game.get_node("BuildingPreview/Model") is DefensiveTowerVisual, "normal construction preview uses authored turret")
	player.gold = 349
	check(game.placement_error(location, 0, "cannon_tower").contains("金币不足"), "350 gold required")
	player.gold = 2000
	var result: Dictionary = game.command_bus.execute({"kind":"build", "building_type":"cannon_tower", "units":[worker.entity_id], "at":[location.x,0,location.z], "seq":game.next_command_sequence(0)}, 0)
	check(result.ok and player.gold == 1650 and player.paid_tower_count == 0, "authority creates cannon site without changing arrow price history")
	var site: BattleBuilding = game.entities_by_id[result.entity_id]
	site.set_physics_process(false)
	check(site.hp == 150 and site.under_construction and site.construction_refund() == 350, "new construction starts at ten percent HP with full unbuilt refund")
	worker.position = site.get_attack_position(site.position + Vector3(8,0,0)) + Vector3(1,0,0)
	site.try_claim_builder(worker)
	site.contribute_work(worker, 15)
	check(is_equal_approx(site.construction_progress, .5) and site.construction_refund() == 175 and site.hp == 825, "half-built cannon has correct work HP and refund")
	site.receive_damage(80)
	site.contribute_work(worker, 15)
	check(site.is_constructed and site.hp == 1420, "30 second construction preserves enemy damage")
	game.select_entities([site]); game.hud.refresh()
	check(game.hud._actions[0].kind == "demolish", "completed tower exposes native demolition command")
	check(site.construction_refund() == 0 and site.demolish(), "completed cannon can be demolished without refund")
	await game.prepare_shutdown()
	game.queue_free()
	await settle()
	game = null
	FileAccess.open(OUT + "functional.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	print("CANNON_TOWER ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
