extends SceneTree
## Real input on the shared selection UI; optional actual-render screenshots.
var checks := 0
var failures: Array[String] = []
var game: Node3D
var capture := false

func _initialize() -> void:
	capture = "--capture-selection" in OS.get_cmdline_user_args()
	root.unfocusable = true
	if capture:
		root.visible = false
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL ", label)

func settle() -> void:
	await process_frame
	await process_frame

func key(code: Key, shift: bool = false, control: bool = false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		event.shift_pressed = shift
		event.ctrl_pressed = control
		root.push_input(event, true)
	await settle()

func click(button: BaseButton, control: bool = false, shift: bool = false) -> void:
	for modifier: Key in [KEY_CTRL, KEY_SHIFT]:
		var event := InputEventKey.new()
		event.keycode = modifier
		event.physical_keycode = modifier
		event.pressed = control if modifier == KEY_CTRL else shift
		Input.parse_input_event(event)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	root.push_input(motion, true)
	await process_frame
	check(root.gui_get_hovered_control() == button, "pointer reaches " + str(button.name))
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.ctrl_pressed = control
		event.shift_pressed = shift
		root.push_input(event, true)
		await process_frame
	for modifier: Key in [KEY_CTRL, KEY_SHIFT]:
		var event := InputEventKey.new()
		event.keycode = modifier
		Input.parse_input_event(event)
	await settle()

func type_slot(composition: SelectionComposition, kind: String) -> Button:
	for slot: Button in composition.slots:
		if slot.visible and str(slot.get_meta("group_key")).ends_with(":" + kind): return slot
	return null

func layout(panel: Control, label: String) -> void:
	var bounds := root.get_visible_rect()
	check(bounds.encloses(panel.get_global_rect()), label + " panel stays on screen")
	for node: Node in panel.find_children("*", "Button", true, false):
		var button: Button = node
		if button.is_visible_in_tree():
			check(panel.get_global_rect().encloses(button.get_global_rect()), label + " contains " + str(button.name))

func shot(label: String) -> void:
	if not capture: return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/rts-selection/" + label + ".png")

func run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute("res://.local/rts-selection")
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.edge_scroll = false
	game.hero_controller.create_or_update(HeroProfile.defaults(), false)
	var hero: HeroUnit = game.hero_controller.hero
	hero.position = Vector3(0, 0, -2)
	game.set_placing(false)
	game.set_running(true)
	game.set_physics_process(false)
	var army: Array = [hero]
	for kind: String in ["swordsman", "swordsman", "swordsman", "archer", "archer", "knight", "priest"]:
		army.append(game.spawn_unit(kind, 0, Vector3((army.size()%4)*2-3, 0, (army.size()/4)*2+1)))
	for unit: BattleUnit in army:
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	game.camera_rig.focus_at(Vector3(0,0,3), true)
	game.camera_rig.zoom_target = 23.0
	game.select_entities(army)
	var panel: Control = game.hud.get_node("UnitPanel")
	var composition: SelectionComposition = panel.composition
	await settle()
	check(composition.total_count == 8 and composition.groups.size() == 5, "mixed army groups exact counts")
	check(composition.total_supply == 9, "composition uses actual population costs")
	check(panel.focused_hero() == hero, "initial mixed selection prioritizes hero abilities")
	check(not game.hero_controller.interface.get_node("%Dock").visible, "RTS has no floating hero HUD")
	check(panel.get_node("%Stats").text.contains("远攻 40"), "hero stats add player and equipped weapon damage")
	await shot("hero_mixed")
	var before: Array = game.selection.duplicate()
	await click(type_slot(composition, "swordsman"))
	check(game.selection == before and composition.focused_group().members.size() == 3, "type inspection preserves whole army")
	check(not panel.get_node("%Abilities").visible, "ordinary subgroup uses ordinary commands")
	var focus_before: String = composition.focus_key
	await key(KEY_TAB)
	check(composition.focus_key != focus_before and game.selection == before, "Tab cycles without selecting another army")
	await key(KEY_TAB, true)
	check(composition.focus_key == focus_before, "Shift Tab reverses the type cycle")
	await click(panel.get_node("%Hold"))
	game.command_bus.tick()
	check(army.all(func(unit): return unit.order == BattleUnit.Order.HOLD), "common order affects all selected types")
	await click(type_slot(composition, "hero"))
	hero.hp = 100
	await key(KEY_Q)
	check(hero.hp == 160 and hero.inventory.count(&"healing_potion") == 2, "hero skill key uses one real item")
	await key(KEY_Q)
	check(hero.hp == 160 and not game.placing, "cooldown consumes the key without entering paint mode")
	check(army.slice(1).all(func(unit): return unit.order == BattleUnit.Order.HOLD), "hero ability leaves other orders intact")
	hero.weapon.rounds = 4
	await key(KEY_Y)
	check(hero.weapon.reload_remaining > 0 and hero.weapon.rounds == 4, "RTS reload shares weapon state")
	game.hud.refresh()
	check(panel.ability_buttons[0].get_node("Cooldown").value > 0, "ability cooldown is displayed")
	await key(KEY_1, false, true)
	await key(KEY_1)
	check(game.selection == before and hero.hp == 160, "number keys retain RTS control groups")
	await key(KEY_I)
	check(game.hero_controller.interface.get_node("%Inventory").visible, "focused hero opens inventory")
	check(game.hero_controller.interface.get_node("%BagHotbar").get_child(0).get_node("Key").text == game.settings.hotkey_text("rts_slot_1"), "backpack shows RTS command slot bindings")
	await key(KEY_I)
	await key(KEY_F5)
	check(not game.hud.visible and game.hero_controller.interface.get_node("%Dock").visible, "first person retains separate first person HUD")
	await key(KEY_F5)
	check(game.hud.visible and not game.hero_controller.interface.get_node("%Dock").visible, "returning RTS restores selection-bound panel")
	check(hero.weapon.rounds == 4 and hero.weapon.reload_remaining > 0, "view transition does not reset shared reload")
	game.select_entities(army)
	await click(type_slot(composition, "archer"), false, true)
	check(game.selection.size() == 6 and game.selection.all(func(unit): return unit.unit_type != "archer"), "Shift click removes only one type")
	await click(type_slot(composition, "swordsman"), true)
	check(game.selection.size() == 3 and game.selection.all(func(unit): return unit.unit_type == "swordsman"), "Ctrl click isolates one type")
	await key(KEY_I)
	check(not game.hero_controller._menu_active, "unselected hero has no inventory shortcut")
	game.select_entities([hero])
	await shot("hero_single")
	for kind: String in ["spearman", "engineer", "light_cavalry", "war_elephant", "catapult", "cannon", "heavy_cannon", "triple_cannon", "crossbowman", "musketeer", "farmer"]:
		var unit: BattleUnit = game.spawn_unit(kind, 0, Vector3(16+army.size(), 0, 0))
		unit.set_physics_process(false)
		army.append(unit)
	game.select_entities(army)
	check(composition.groups.size() == 16, "all distinct unit types represented")
	await click(composition.get_node("%Next"))
	check(composition.page == 1 and composition.slots.all(func(slot): return slot.visible), "large selection has native second page")
	for pixels: Vector2i in [Vector2i(1280,720), Vector2i(1600,900)]:
		root.size = pixels
		await settle()
		layout(panel, "sandbox %d" % pixels.x)
	game.select_entities(army.slice(1,8))
	await shot("troop_composition")
	var dying: BattleUnit = army[7]
	game.select_entities([army[1], dying, army[4]])
	await click(type_slot(composition, "archer"))
	dying.receive_damage(10000)
	game.hud.refresh()
	check(composition.total_count == 2 and composition.focused_entity() == army[4], "other type's death does not switch the active command card")
	army[4].receive_damage(10000)
	game.hud.refresh()
	check(composition.total_count == 1 and composition.focused_entity() == army[1], "death removes group and repairs focus")
	game.select_entities([game.get_tree().get_first_node_in_group("resource_veins")])
	check(composition.total_count == 1 and composition.total_supply == 0, "neutral resource remains inspectable")
	game.select_entities([])
	check(not panel.visible, "empty selection hides unit controls")
	await game.prepare_shutdown()
	await normal_battle()
	print("RTS_SELECTION_PANEL ", checks - failures.size(), "/", checks, " passed; failures=", failures)
	quit(0 if failures.is_empty() else 1)

func normal_battle() -> void:
	root.get_node("Session").start_offline("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	if root.get_node("Session").transition.busy:
		await root.get_node("Session").transition.completed
	game.bots.clear()
	game.set_physics_process(false)
	game.get_node("IncomeTimer").stop()
	game.camera_rig.edge_scroll = false
	game.camera_rig.focus_at(Vector3(0,0,3), true)
	game.camera_rig.zoom_target = 24.0
	var army: Array = []
	for kind: String in ["swordsman", "swordsman", "swordsman", "archer", "archer", "knight", "knight", "priest", "cannon", "farmer"]:
		army.append(game.spawn_unit(kind, 0, Vector3((army.size()%4)*2-3,0,(army.size()/4)*2)))
	for unit: BattleUnit in game.unit_container.get_children():
		unit.set_physics_process(false)
		unit.navigation_agent.avoidance_enabled = false
	game.get_node("FogOfWar").tick(0.2)
	game.get_node("FogOfWar").apply_visibility(game.local_owner_id)
	game.select_entities(army)
	var composition: SelectionComposition = game.hud.get_node("CommandBar/Composition")
	await settle()
	check(composition.visible and composition.total_count == 10, "normal battle shows selected army composition")
	check(game.hud._actions.is_empty(), "soldier subgroup does not show selected worker construction actions")
	await click(type_slot(composition,"farmer"))
	check(game.hud._actions.all(func(action): return action.kind in ["build", "action_page"]) and game.hud._actions.any(func(action): return action.kind == "build"), "worker subgroup exposes native construction actions and pagination")
	await click(type_slot(composition,"archer"))
	check(game.hud._actions.is_empty() and game.selection == army, "returning to archers retains whole mixed selection")
	check(game.hud.selected_name.text.contains("弓箭手 ×2"), "focused type shows matching count and stats")
	for pixels: Vector2i in [Vector2i(1280,720),Vector2i(1600,900)]:
		root.size = pixels
		await settle()
		layout(game.hud.get_node("CommandBar"), "normal %d" % pixels.x)
		check(game.hud.get_node("CommandBar").get_global_rect().encloses(composition.get_node("Hint").get_global_rect()), "normal composition hint stays inside bar")
	await shot("normal_army")
	var barracks: BattleBuilding = game.spawn_building("barracks",0,Vector3(10,0,6))
	barracks.set_physics_process(false)
	game.select_entities(army+[barracks])
	await click(type_slot(composition,"barracks"))
	check(game.selected_production() == barracks and game.hud._actions[0].id == "swordsman", "building subgroup exposes its existing production card")
	await key(KEY_TAB)
	check(composition.focused_group().kind == "swordsman" and game.hud._actions.is_empty(), "Tab returns from building to unit capabilities")
	await click(type_slot(composition,"archer"),true)
	check(game.selection.size() == 2 and game.selection.all(func(unit): return unit.unit_type == "archer"), "normal battle Ctrl click isolates that type")
	await game.prepare_shutdown()
	game.queue_free()
	await settle()
	game = null
