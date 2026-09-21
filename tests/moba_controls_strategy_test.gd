extends SceneTree
## Input, viewport layout and real combat regressions for the MOBA commander.
var game: Node3D
var checks := 0
var failures: Array[String] = []
var saved_preferences: String
var had_preferences: bool

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL ", message)

func frames(count: int) -> void:
	for index: int in count: await physics_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func rect(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)

func run() -> void:
	create_timer(65, true, false, true).timeout.connect(func(): quit(3))
	had_preferences = FileAccess.file_exists("user://moba_interface.cfg")
	if had_preferences: saved_preferences = FileAccess.get_file_as_string("user://moba_interface.cfg")
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.wave_due = PackedFloat64Array([10000, 10000])
	game.get_node("Director").card_in = 10000
	game.heroes[1].set_physics_process(false)
	game.hero_controller.set_follow(false)
	game.camera_rig.edge_scroll = false
	for building: BattleBuilding in game.get_node("Buildings").get_children():
		building.set_physics_process(false)
		if building.artillery != null:
			for gun: DefensiveGunVisual in building.artillery.guns:
				check((-gun.turret.global_basis.z).normalized().dot(Vector3.BACK) > .99, "resting cannon faces the player camera")
	var hero: MobaHero = game.local_hero()
	hero.position = Vector3(-76, 0, 0)
	hero.reset_physics_interpolation()
	var start: Vector3 = hero.position
	var camera_destination: Vector3 = game.camera_rig.destination
	key(KEY_D, true)
	await frames(15)
	key(KEY_D, false)
	await frames(2)
	var straight: float = hero.position.distance_to(start)
	check(straight > 1.7 and straight < 2.4, "top-down D moves the hero immediately at native speed")
	check(game.camera_rig.destination.is_equal_approx(camera_destination), "WASD does not pan the MOBA camera")
	check(not hero.directly_controlled and hero.move_input == Vector3.ZERO, "key release stops manual movement")
	start = hero.position
	key(KEY_W, true)
	key(KEY_D, true)
	await frames(15)
	key(KEY_W, false)
	key(KEY_D, false)
	await frames(2)
	check(absf(hero.position.distance_to(start) - straight) < .22, "diagonal movement is normalized")
	check(hero.position.z < start.z - 1, "W moves toward the top of the screen")
	game.command_move(Vector3(-72, 0, 3))
	await frames(2)
	check(hero.order == BattleUnit.Order.MOVE, "right-click command path takes over after keyboard movement")
	key(KEY_A, true)
	await frames(2)
	check(hero.directly_controlled and hero.waypoint_queue.is_empty(), "WASD immediately cancels a pending path")
	key(KEY_A, false)
	await frames(2)
	hero.position = Vector3(-76, 0, 0)
	var victim: BattleUnit = game.spawn_unit("swordsman", 1, Vector3(-72, 0, -6))
	victim.set_physics_process(false)
	victim.navigation_agent.avoidance_enabled = false
	var hp: float = victim.hp
	game.get_node("Director").decision_in = 10000
	key(KEY_D, true)
	await frames(24)
	key(KEY_D, false)
	await frames(2)
	check(victim.hp < hp, "hero lands real shots while moving with WASD")
	victim.position += Vector3(30, 0, 0)
	start = hero.position
	await frames(4)
	check(hero.position.distance_to(start) < .05 and hero.order == BattleUnit.Order.HOLD, "releasing WASD never chases an automatically acquired enemy")
	var cooldown: float = hero.weapon.cooldown
	game.hero_controller.set_first_person(true)
	check(is_equal_approx(hero.weapon.cooldown, cooldown), "F5 preserves weapon cooldown")
	game.hero_controller.set_first_person(false)
	key(KEY_D, true)
	await frames(2)
	game.set_running(false)
	start = hero.position
	await frames(4)
	check(hero.position == start and not hero.trigger_held, "pause clears movement and shooting")
	key(KEY_D, false)
	game.set_running(true)
	game.hero_controller._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not game.hero_controller.focused and hero.move_input == Vector3.ZERO, "focus loss releases direct input")
	game.hero_controller._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	game.hero_controller.set_follow(false)
	game.camera_rig.edge_scroll = false
	victim._apply_damage(99999, null)
	hero.stop()
	# Exercise ancestor scaling, hit rectangles and available drop area together.
	for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]:
		root.size = resolution
		await process_frame
		for scale_value: float in [.7, .85, 1.0]:
			game.hud.set_panel_scale(scale_value)
			await process_frame
			var left := rect(game.hud.get_node("%HeroPanel"))
			var right := rect(game.hud.get_node("%MapPanel"))
			check(left.end.x < rect(game.hud.cards[0]).position.x and right.position.x > rect(game.hud.cards[4]).end.x, "hero left / map right with no overlap at %s / %s" % [resolution, scale_value])
			check(root.get_visible_rect().encloses(left) and root.get_visible_rect().encloses(right), "scaled panels stay on screen")
			check(rect(game.hud.get_node("%DropZone")).end.y < left.position.y, "card drop area follows console size")
	# Both commanders must balance repeated waves by role, not entity parity.
	for owner: int in 2:
		for wave: int in 2: game.spawn_army(game.WAVE, owner)
		var lanes := [0, 0]
		var ranged_lanes := [0, 0]
		for unit: BattleUnit in game.unit_container.get_children():
			if not unit.alive or unit is HeroUnit or unit.owner_id != owner: continue
			var lane := 0 if int(unit.get_meta("moba_lane")) < 0 else 1
			lanes[lane] += 1
			if not unit._stats.projectile.is_empty(): ranged_lanes[lane] += 1
		check(absi(lanes[0] - lanes[1]) <= 2 and absi(ranged_lanes[0] - ranged_lanes[1]) <= 1, "both sides distribute melee and ranged reinforcements")
	var armies := [[], []]
	for unit: BattleUnit in game.unit_container.get_children():
		if unit.alive: armies[unit.owner_id].append(unit)
	game.players[1].gold = 240
	game.get_node("Director")._buy_card(armies)
	check(game.players[1].gold == 240, "bot saves for needed siege instead of buying cheap reinforcements")
	game.players[1].gold = 300
	game.get_node("Director")._buy_card(armies)
	check(game.players[1].gold == 45 and game.hands[1].slots[4].card == null, "saved gold purchases a real siege card at its normal price")
	for unit: BattleUnit in game.unit_container.get_children():
		if not unit is HeroUnit and unit.alive: unit._apply_damage(99999, null)
	var director: Node = game.get_node("Director")
	var rival: MobaHero = game.heroes[1]
	rival.hp = 151
	rival.recovery_cooldown = 0
	director.retreating = true
	director._command_hero([[], [rival]])
	check(rival.recovery_ticks == 5, "partially healed retreating hero continues recovery instead of remaining at base forever")
	rival.hp = 180
	director._command_hero([[], [rival]])
	check(not director.retreating, "recovered bot hero returns to its front line")
	var enemy: BattleUnit = game.spawn_unit("swordsman", 1, Vector3(1, 0, 0))
	enemy.set_physics_process(false)
	enemy.navigation_agent.avoidance_enabled = false
	enemy.hp = 1000
	var archer: BattleUnit = game.spawn_unit("archer", 0, Vector3(-13, 0, 0))
	archer.set_meta("moba_lane", -1)
	archer.set_meta("moba_file", -2)
	director._command_army(archer, [enemy], {})
	check(archer.order == BattleUnit.Order.MOVE and absf(archer.destination.z) > 2, "idle rear archer receives a separated firing position")
	start = archer.position
	await frames(120)
	check(archer.position.distance_to(start) > 2 and enemy.hp < 1000, "rear archer advances and deals damage through native combat")
	var fighter: BattleUnit = game.spawn_unit("swordsman", 0, Vector3(-.4, 0, 0))
	fighter.issue_attack(enemy)
	fighter._start_attack()
	var windup: float = fighter.attack_windup.time_left
	director._command_army(fighter, [enemy], {})
	check(fighter.target == enemy and is_equal_approx(fighter.attack_windup.time_left, windup), "commander preserves an active attack windup")
	if had_preferences: FileAccess.open("user://moba_interface.cfg", FileAccess.WRITE).store_string(saved_preferences)
	else: DirAccess.remove_absolute("user://moba_interface.cfg")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	print("MOBA_CONTROLS_STRATEGY ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
