extends SceneTree
## Actual sandbox render captures; no generated concept is substituted for gameplay.
const OUT := "res://.local/hero/current/"
var game: Node3D
func _initialize() -> void: run.call_deferred()
func wait_render() -> void:
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await wait_render()
	root.get_texture().get_image().save_png(OUT+name+".png")
func run() -> void:
	create_timer(90,true,false,true).timeout.connect(func():quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1600,900)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	var controller: SandboxHeroController = game.hero_controller
	controller.profile = HeroProfile.defaults()
	controller.interface.open_creator()
	await capture("creator")
	controller.interface.get_node("%Viewport").get_texture().get_image().save_png(OUT+"portrait.png")
	controller.interface.get_node("%PreviewPivot").rotation.y = deg_to_rad(-33.7)
	await capture("front")
	controller.interface.get_node("%PreviewPivot").rotation.y = 0
	controller.interface.get_node("%Fields").current_tab = 1
	for expression_index: int in HeroProfile.EXPRESSION_NAMES.size():
		controller.interface._draft.expression = expression_index
		controller.interface._draft.glasses = expression_index==2
		controller.interface._draft.scarf = expression_index==2
		controller.interface._draft.headwear = expression_index%3
		controller.interface._draft.feather = expression_index==2
		controller.interface._fill_creator()
		controller.interface._preview()
		await capture("expression_%d" % expression_index)
	controller.interface._draft = HeroProfile.defaults()
	controller.interface._fill_creator()
	controller.interface._preview()
	var portrait_model: HeroVisual = controller.interface.get_node("%Model")
	portrait_model.attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for pose: String in ["strike","reload"]:
		portrait_model.attack.play(pose)
		portrait_model.attack.advance(0)
		portrait_model.attack.seek(.07 if pose=="strike" else .75,true)
		await capture(pose)
	portrait_model.attack.play("strike")
	portrait_model.attack.seek(.65,true)
	controller.interface.get_node("%PreviewPivot").rotation.y = PI
	await capture("back")
	controller.interface.get_node("%PreviewPivot").rotation.y = PI*.5
	await capture("side")
	controller.interface.close_panels()
	controller.create_or_update(HeroProfile.defaults(),false)
	var hero: HeroUnit = controller.hero
	hero.position = Vector3.ZERO
	hero.model_pivot.rotation.y = 2.8
	game.spawn_unit("musketeer",0,Vector3(-2,0,.1))
	game.spawn_unit("swordsman",0,Vector3(2,0,.1))
	game.camera_rig.set_process(false)
	game.camera_rig.focus_at(Vector3.ZERO,true)
	game.camera.size = 8
	await capture("rts")
	game.camera.size = 24
	await capture("battle_zoom")
	var enemy: BattleUnit = game.spawn_unit("shield_guard",1,Vector3(0,0,-8))
	enemy.max_hp = 10000
	enemy.hp = 10000
	enemy.set_physics_process(false)
	game.set_running(true)
	controller.set_first_person(true)
	controller.yaw = 0.0
	controller.pitch = -.075
	await capture("first_person")
	hero.trigger_held = true
	await create_timer(.10).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"shot.png")
	hero.trigger_held = false
	controller.interface.open_inventory()
	await capture("inventory")
	controller.interface.close_panels()
	controller.interface.open_pause()
	game.settings.open_menu()
	game.settings.menu.show_page("FirstPerson")
	await capture("settings")
	game.settings.close_menu()
	controller.interface.open_creator()
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1280,800),Vector2i(1920,820)]:
		root.size = resolution
		await capture("layout_%dx%d"%[resolution.x,resolution.y])
	controller.interface.close_panels()
	controller.set_first_person(false)
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_VISUAL_REVIEW_COMPLETE")
	quit()
