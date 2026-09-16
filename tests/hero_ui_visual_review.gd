extends SceneTree
## Render the saved native interface over the actual sandbox, never a UI mockup.
const OUT := "res://.local/hero/ui/"
var game: Node3D

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func capture(label: String) -> void:
	await create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")

func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	AudioServer.set_bus_mute(0,true)
	root.size = Vector2i(1600,900)
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	root.gui_disable_input = true
	var controller: SandboxHeroController = game.hero_controller
	controller.create_or_update(HeroProfile.defaults(),false)
	var hero := controller.hero
	hero.position = Vector3.ZERO
	hero.model_pivot.rotation = Vector3.ZERO
	game.spawn_unit("shield_guard",1,Vector3(0,0,-8))
	game.spawn_unit("musketeer",0,Vector3(-3,0,-5))
	game.set_placing(false)
	game.camera_rig.focus_at(Vector3.ZERO,true)
	game.camera_rig.set_process(false)
	game.camera.size = 24
	controller.set_first_person(true)
	controller._capture(false)
	controller.yaw = 0
	controller.pitch = -.075
	game.set_running(true)
	for unit: BattleUnit in get_nodes_in_group("units"): unit.set_physics_process(false)
	await capture("first_person")
	hero.hp = 140
	controller.interface.open_inventory()
	await capture("inventory")
	var environment: Environment = game.get_node("WorldEnvironment").environment
	var exposure := environment.tonemap_exposure
	environment.tonemap_exposure = .3
	await capture("inventory_dark")
	environment.tonemap_exposure = exposure
	controller.interface.get_node("%EquippedWeapon").pressed.emit()
	await capture("weapon_details")
	controller.interface.close_panels()
	controller._capture(false)
	hero.hp = 65
	hero.inventory.use(&"healing_potion",hero)
	hero.inventory.use(&"windwalk_potion",hero)
	hero.weapon.rounds = 3
	hero.weapon.begin_reload()
	hero.weapon.reload_remaining = 1.2
	controller.interface.refresh()
	await capture("active_states")
	controller.interface.open_inventory()
	controller.interface._showing_weapon = false
	controller.interface._selected_item = &"windwalk_potion"
	controller.interface._selected_slot = 1
	controller.interface.refresh()
	root.size = Vector2i(1280,720)
	await capture("inventory_small")
	root.size = Vector2i(1600,900)
	controller.interface.close_panels()
	controller.set_first_person(false)
	await capture("rts")
	root.size = Vector2i(1280,720)
	await capture("rts_small")
	root.size = Vector2i(1600,900)
	controller.interface.open_creator()
	await capture("creator")
	controller.interface.close_panels()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_UI_VISUAL_REVIEW_COMPLETE")
	quit()
