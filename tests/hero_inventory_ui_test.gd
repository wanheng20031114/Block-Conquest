extends SceneTree
## Real sandbox input and authored UI, with inventory invariants and appearance persistence.
var checks := 0
var failures: Array[String] = []
var game: Node3D
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ",label)
func key(code: Key,alt: bool = false) -> void:
	for down: bool in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = down
		event.alt_pressed = alt
		root.push_input(event,true)
	await process_frame
func click(button: BaseButton) -> void:
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for down: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event,true)
	await process_frame
func run() -> void:
	create_timer(45,true,false,true).timeout.connect(func():quit(3))
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	var controller: SandboxHeroController = game.hero_controller
	controller.create_or_update(HeroProfile.defaults(),false)
	var hero: HeroUnit = controller.hero
	hero.set_physics_process(false)
	var inventory := hero.inventory
	check(inventory.slots.size()==24 and inventory.hotbar.size()==5,"24 inventory slots and five references")
	check(inventory.count(&"healing_potion")==3 and inventory.count(&"windwalk_potion")==2,"trial starter supplies")
	check(not inventory.use(&"healing_potion",hero).is_empty() and inventory.count(&"healing_potion")==3 and inventory.cooldowns.is_empty(),"full health costs no item or cooldown")
	hero.hp = 100
	check(inventory.use(&"healing_potion",hero).is_empty() and hero.hp==160 and inventory.count(&"healing_potion")==2,"healing restores 60 once")
	inventory.assign(4,&"healing_potion")
	check(not inventory.use(inventory.hotbar[4],hero).is_empty() and hero.hp==160,"duplicated shortcut cannot bypass cooldown")
	inventory.move_stack(0,23)
	check(inventory.count(&"healing_potion")==2 and inventory.slots[23].count==2,"moving stack conserves count")
	check(not inventory.use(inventory.hotbar[0],hero).is_empty(),"moving stack preserves type cooldown")
	inventory.advance(10)
	check(inventory.use(&"healing_potion",hero).is_empty() and hero.hp==200,"healing clamps at maximum")
	check(inventory.use(&"windwalk_potion",hero).is_empty() and is_equal_approx(hero.speed,5.04),"speed potion grants 20 percent")
	check(not inventory.use(&"windwalk_potion",hero).is_empty() and inventory.count(&"windwalk_potion")==1,"speed cannot stack")
	hero._physics_process(10)
	check(is_equal_approx(hero.speed,4.2) and inventory.cooldowns[&"windwalk_potion"]==5,"speed ends before its cooldown")
	inventory.add(&"healing_potion",7)
	check(inventory.count(&"healing_potion")==8 and inventory.slots[23].count==5 and inventory.slots[0].count==3,"stack limit five, fills existing stack first")
	inventory.move_stack(0,23)
	check(inventory.slots[0].count==3 and inventory.slots[23].count==5,"merge cannot overfill destination")
	inventory.move_stack(0,1)
	check(inventory.slots[0].id==&"windwalk_potion" and inventory.slots[1].id==&"healing_potion","different stacks swap")
	var stored := inventory.count(&"healing_potion")
	var remainder := inventory.add(&"healing_potion",200)
	check(inventory.count(&"healing_potion")+remainder==stored+200 and inventory.slots.all(func(s: Dictionary):return s.count<=5),"overflow cannot lose or duplicate items")
	check(not inventory.assign(5,&"healing_potion") and not inventory.assign(0,&"unknown"),"shortcut validation")
	await key(KEY_I)
	check(controller._menu_active and controller.interface.get_node("%Inventory").visible,"physical I opens native inventory")
	check(not game.hud.visible,"inventory keeps the scene visible without overlapping RTS controls")
	var close_rect: Rect2 = controller.interface.get_node("%CloseInventory").get_global_rect()
	check(close_rect.position.x>root.get_visible_rect().size.x-240 and close_rect.position.y>50,"backpack close button stays in upper right")
	var slot: HeroInventorySlot = controller.interface.get_node("%BagGrid").get_child(1)
	var shortcut: HeroInventorySlot = controller.interface.get_node("%BagHotbar").get_child(3)
	var drag := {"inventory":inventory,"slot":1,"is_shortcut":false,"id":&"healing_potion"}
	check(shortcut._can_drop_data(Vector2.ZERO,drag),"native drop accepts local inventory item")
	shortcut._drop_data(Vector2.ZERO,drag)
	check(inventory.hotbar[3]==&"healing_potion" and inventory.count(&"healing_potion")+remainder==stored+200,"drop binds a reference without copying stock")
	check(not slot._can_drop_data(Vector2.ZERO,{"inventory":null,"slot":0,"is_shortcut":false,"id":&"healing_potion"}),"foreign inventory cannot drop")
	await click(controller.interface.get_node("%BagGrid").get_child(0))
	check(controller.interface.get_node("%ItemName").text=="加速药剂","native slot click selects its actual item")
	await key(KEY_ESCAPE)
	check(not controller._menu_active and not game.running,"Esc closes bag and retains earlier pause")
	game.set_running(true)
	await key(KEY_F5)
	check(controller.first_person and game.running,"F5 enters first person without pausing")
	hero.hp = 70
	inventory.advance(20)
	await key(KEY_1)
	check(hero.hp==130,"first-person number uses potion")
	await key(KEY_4)
	check(hero.hp==130,"second bound number cannot bypass same-item cooldown")
	await key(KEY_I)
	var remaining: float = inventory.cooldowns[&"healing_potion"]
	await create_timer(.15).timeout
	check(not game.running and inventory.cooldowns[&"healing_potion"]==remaining,"inventory pauses simulation clocks")
	await key(KEY_1)
	check(hero.hp==130,"modal number input cannot consume a potion")
	await key(KEY_I)
	check(game.running and controller._look_captured,"closing bag restores running and capture intent (headless mouse has no capture)")
	await key(KEY_ESCAPE)
	check(controller._menu_active and not game.running,"FP escape opens pause menu")
	game.settings.open_menu()
	await process_frame
	check(game.settings.is_open() and not game.running,"nested settings remain paused")
	game.settings.close_menu()
	await process_frame
	check(not controller._menu_active and game.running,"closing nested settings restores the prior running state")
	await key(KEY_F5)
	check(not controller.first_person and game.hud.visible,"F5 returns to RTS")
	hero.hp = 70
	inventory.advance(20)
	await key(KEY_1)
	check(hero.hp==70,"RTS group digit does not use a potion")
	await key(KEY_1,true)
	check(hero.hp==130,"RTS Alt-digit uses the hero hotbar")
	controller.interface.open_creator()
	await key(KEY_1)
	check(hero.hp==130,"creator input cannot trigger items")
	var model: HeroVisual = controller.interface.get_node("%Model")
	for expression: int in HeroProfile.EXPRESSION_NAMES.size():
		var look := HeroProfile.defaults()
		look.expression = expression
		look.headwear = expression%3
		look.glasses = true
		look.scarf = true
		model.apply_appearance(look)
		var visible := model.get_node("Rig/Expressions").get_children().filter(func(n: Node3D):return n.visible)
		check(visible.size()==1 and visible[0].get_index()==expression,"exactly one authored expression %d"%expression)
	var customized := HeroProfile.defaults()
	customized.expression = 2
	customized.headwear = 2
	customized.feather = true
	customized.name = "远行者测试"
	check(HeroProfile.save_profile(customized,"res://.local/hero/profile-test.cfg")==OK,"appearance saves to isolated native config")
	check(HeroProfile.read_profile("res://.local/hero/profile-test.cfg")==customized,"all new customization fields survive reload")
	controller.interface._draft = customized
	controller.interface.get_node("%ResetAppearance").pressed.emit()
	check(controller.interface._draft.expression==0 and controller.interface._draft.headwear==0 and not controller.interface._draft.feather and controller.interface._draft.name==customized.name,"reset returns to concept C face and preserves identity")
	controller.interface.close_panels()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	print("HERO_INVENTORY_UI ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
