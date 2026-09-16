extends SceneTree
var checks := 0
var failures: Array[String] = []
var game: Node3D
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)
func sync_physics() -> void:
	await physics_frame
	await physics_frame
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	var controller: SandboxHeroController = game.hero_controller
	check(controller.create_or_update(HeroProfile.defaults(),false),"create local sandbox hero")
	var hero: HeroUnit = controller.hero
	check(hero.unit_type=="hero" and hero.hp==200 and hero.speed==4.2,"independent hero definition")
	check(hero.weapon.payload(hero._stats,0,0).base_damage+hero.weapon.definition.attack_bonus==40,"20 plus 20 additive attack")
	check(hero._stats.is_ranged_infantry() and hero._stats.melee_armor==3 and hero._stats.ranged_armor==3,"orthogonal infantry and ranged classification")
	check(game.sandbox_unit_count==1 and game.get_player(0).military_supply==1,"hero population uses actual definition")
	hero.position = Vector3.ZERO
	hero.model_pivot.rotation = Vector3.ZERO
	hero.set_physics_process(false)
	var target: BattleUnit = game.spawn_unit("shield_guard",1,Vector3(0,0,-8))
	target.set_physics_process(false)
	target.navigation_agent.avoidance_enabled = false
	target.max_hp = 10000
	target.hp = 10000
	game.set_running(true)
	await sync_physics()
	check(hero.fire_direction(hero._aim_point(target)-hero.logic_eye()),"free aim valid shot")
	check(target.hp==9967 and hero.weapon.rounds==9,"40 minus seven ranged armor, one round consumed")
	check(not hero.fire_direction(Vector3.FORWARD),"shared cooldown blocks another shot")
	hero.weapon.advance(.649)
	check(not hero.fire_direction(Vector3.FORWARD),"cannot shoot early at .649 seconds")
	hero.weapon.advance(.001)
	check(hero.fire_direction(Vector3.UP),"shooting into sky can miss")
	check(target.hp==9967 and hero.weapon.rounds==8,"miss still consumes ammo")
	for index: int in 8:
		hero.weapon.advance(.65)
		hero.fire_direction(Vector3.UP)
	check(hero.weapon.rounds==0 and is_equal_approx(hero.weapon.reload_remaining,1.8),"ten rounds starts 1.8 second auto reload")
	hero.weapon.advance(.6)
	var remaining := hero.weapon.reload_remaining
	controller.set_first_person(true)
	check(controller.first_person and hero.directly_controlled and not game.hud.visible,"F5 mode shares one entity and hides RTS")
	# Test the actual input path: 800 raw counts (one inch at 800 DPI) must
	# rotate 17.6 degrees at CS2 sensitivity 1, irrespective of stretched UI input.
	var old_sensitivity: float = game.settings.fp_sensitivity
	var old_fov: float = game.settings.fp_fov
	var old_invert: bool = game.settings.fp_invert_y
	game.settings.fp_invert_y = false
	for sensitivity: float in [0.35, 1.0, 2.0]:
		game.settings.fp_sensitivity = sensitivity
		for fov: float in [70.0, 110.0]:
			game.settings.fp_fov = fov
			controller.yaw = 0.0
			controller.pitch = 0.0
			var motion := InputEventMouseMotion.new()
			motion.screen_relative = Vector2(800,100)
			motion.relative = Vector2(400,50)
			controller.handle_input(motion)
			check(absf(rad_to_deg(controller.yaw)+17.6*sensitivity)<0.0001, "CS2 horizontal rotation ignores FOV and stretched relative input")
			check(absf(rad_to_deg(controller.pitch)+2.2*sensitivity)<0.0001, "CS2 vertical rotation uses the same scale")
	game.settings.fp_sensitivity = 1.0
	controller.yaw = 0.0
	var small_motion := InputEventMouseMotion.new()
	small_motion.screen_relative = Vector2(8,0)
	for packet: int in 100: controller.handle_input(small_motion)
	check(absf(rad_to_deg(controller.yaw)+17.6)<0.0001, "split and accumulated mouse packets turn by the same angle")
	game.settings.fp_invert_y = true
	controller.pitch = 0.0
	small_motion.screen_relative = Vector2(0,100)
	controller.handle_input(small_motion)
	check(absf(rad_to_deg(controller.pitch)-2.2)<0.0001, "invert Y changes direction without changing sensitivity")
	controller._look_captured = false
	controller.handle_input(small_motion)
	check(absf(rad_to_deg(controller.pitch)-2.2)<0.0001, "uncaptured mouse motion cannot rotate the hero")
	controller._look_captured = true
	game.settings.fp_sensitivity = old_sensitivity
	game.settings.fp_fov = old_fov
	game.settings.fp_invert_y = old_invert
	check(not controller.camera.get_cull_mask_value(19),"FP excludes body and every attached cosmetic")
	for mesh: MeshInstance3D in hero._model.find_children("*","MeshInstance3D",true,false):
		check(mesh.layers==HeroUnit.BODY_LAYER,"body layer includes "+str(mesh.name))
	controller.set_first_person(false)
	check(hero.weapon.rounds==0 and hero.weapon.reload_remaining==remaining,"switch cannot reload or reset progress")
	check(game.camera.current and game.hud.visible and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"return restores camera UI and cursor")
	hero.weapon.advance(remaining-.01)
	check(hero.weapon.rounds==0,"no early reload completion")
	hero.weapon.advance(.01)
	check(hero.weapon.rounds==10,"reload refills exactly ten")
	check(not hero.weapon.begin_reload(),"cannot restart full magazine")
	var wall: StaticBody3D = load("res://tests/fixtures/hero_wall.tscn").instantiate()
	wall.position = Vector3(0,0,-4)
	game.add_child(wall)
	await sync_physics()
	check(hero.query_shot(hero._aim_point(target)-hero.logic_eye()).collider==wall,"wall blocks aimed enemy")
	hero.fire_direction(hero._aim_point(target)-hero.logic_eye())
	check(target.hp==9967,"wall hit deals no target damage")
	wall.position.z = -.5
	await sync_physics()
	check(hero.query_shot(Vector3.FORWARD).collider==wall,"gun extending beyond near wall cannot bypass obstruction")
	wall.position.z = -4
	await sync_physics()
	hero.set_direct_control(true)
	hero.move_input = Vector3.FORWARD
	for index: int in 60: hero._physics_process(1.0/30.0)
	check(hero.position.z > -3.5,"direct movement cannot cross wall")
	hero.move_input = Vector3.ZERO
	var ground := hero.global_position
	var shape_at: Vector3 = hero.get_node("CollisionShape3D").global_position
	check(hero.jump(),"cosmetic jump starts")
	hero._physics_process(.325)
	check(hero.jump_offset>.44 and hero.global_position==ground,"jump changes visual height only")
	check(hero.get_node("CollisionShape3D").global_position==shape_at,"jump retains standing hurtbox")
	var enemy_payload := DamageResolver.snapshot(BalanceCatalog.unit("musketeer"),0,1,1)
	hero.receive_hit(enemy_payload,target)
	check(hero.hp==178,"existing attacks still hit jumping hero with shared armor")
	check(not hero.jump(),"jump cannot stack")
	hero._physics_process(.325)
	check(hero.jump_offset==0.0 and hero.global_position==ground,"jump lands on unchanged logical position")
	hero.set_direct_control(false)
	wall.queue_free()
	var edited := HeroProfile.defaults()
	edited.name = "胶囊测试"
	edited.faction = 2
	edited.nose = true
	edited.backpack = true
	var before_rounds := hero.weapon.rounds
	check(controller.create_or_update(edited,false),"appearance and faction edit")
	check(hero.hp==178 and hero.weapon.rounds==before_rounds,"appearance edit preserves combat state")
	check(game.get_player(0).military_supply==0 and game.get_player(2).military_supply==1,"team change moves supply once")
	check(hero._model.get_node("Rig/Accessories/Nose").visible,"nose accessory is an authored optional part")
	controller.set_first_person(true)
	hero.receive_damage(1000)
	check(not controller.first_person and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"death exits direct control")
	check(game.get_player(2).military_supply==0,"death releases hero supply")
	check(controller.create_or_update(edited,false),"sandbox can recreate hero")
	var replacement := controller.hero
	await create_timer(1.8).timeout
	check(controller.hero==replacement,"old corpse cleanup cannot clear replacement hero")
	game.clear_units()
	await process_frame
	check(not controller.has_hero() and game.sandbox_unit_count==0,"clear sandbox removes owned hero")
	check(not game.settings.defaults().fp_head_bob and game.settings.defaults().fp_fov==90,"comfort defaults")
	var clean: Dictionary = game.settings._sanitize({"fp_fov":999,"fp_sensitivity":-2,"fp_head_bob":false})
	check(clean.fp_fov==110 and clean.fp_sensitivity==.05,"FP settings clamp values")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_SANDBOX ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
