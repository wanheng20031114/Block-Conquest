extends SceneTree
## Native 30 Hz RTS combat; repeated orders cannot reset the hero's own weapon.
var checks := 0
var failures: Array[String] = []
var times: Array[float] = []
var game: Node3D
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)
func run() -> void:
	create_timer(35,true,false,true).timeout.connect(func():quit(3))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	var controller: SandboxHeroController = game.hero_controller
	controller.create_or_update(HeroProfile.defaults(),false)
	var hero := controller.hero
	hero.position = Vector3.ZERO
	hero.model_pivot.rotation = Vector3.ZERO
	var enemy: BattleUnit = game.spawn_unit("shield_guard",1,Vector3(0,0,-8))
	enemy.max_hp = 10000
	enemy.hp = 10000
	enemy.set_physics_process(false)
	enemy.navigation_agent.avoidance_enabled = false
	hero.shot_resolved.connect(func(_hit: Dictionary):times.append(float(Engine.get_physics_frames())/Engine.physics_ticks_per_second))
	game.set_running(true)
	while times.size()<12:
		hero.issue_attack(enemy)
		await create_timer(.11).timeout
	game.set_running(false)
	check(enemy.hp==10000-33*12,"twelve native RTS shots use 40 minus ranged armor")
	for index: int in range(1,10):
		var gap := times[index]-times[index-1]
		check(gap>=.61 and gap<=.69,"native shot interval %d = %.3f"%[index,gap])
	check(absf((times[9]-times[0])/9.0-.65)<.006,"average cadence remains .65 despite fractional physics ticks")
	check(times[10]-times[9]>=1.76 and times[10]-times[9]<=1.87,"empty magazine reload blocks for 1.8 seconds")
	check(hero.weapon.rounds==8,"twelfth shot leaves eight rounds after one refill")
	check(hero.global_position.distance_to(Vector3.ZERO)<.1,"clear RTS firing does not cause approach jitter")
	var friend: BattleUnit = game.spawn_unit("shield_guard",0,Vector3(0,0,-4))
	friend.set_physics_process(false)
	await physics_frame
	await physics_frame
	check(hero.query_shot(hero._aim_point(enemy)-hero.logic_eye()).collider==friend,"friendly soldier blocks the shot")
	var hp := friend.hp
	hero.set_physics_process(false)
	hero.weapon.advance(2)
	game.set_running(true)
	hero.fire_direction(hero._aim_point(enemy)-hero.logic_eye())
	game.set_running(false)
	check(friend.hp==hp and enemy.hp==10000-33*12,"friendly block cannot damage friend or shoot through it")
	controller.set_first_person(true)
	var body_at := hero.global_position
	controller._update_camera(0)
	var camera_y := controller.camera.global_position.y
	hero._model.locomotion.seek(.24,true)
	controller._update_camera(0)
	check(is_equal_approx(camera_y,controller.camera.global_position.y),"locomotion animation never moves comfort camera")
	hero.model_pivot.position.y = .45
	check(hero.global_position==body_at,"render pose cannot move the collision body")
	controller.set_first_person(false)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_COMBAT_FLOW ",checks," checks; ",failures.size()," failures; shot_times=",times)
	quit(0 if failures.is_empty() else 1)
