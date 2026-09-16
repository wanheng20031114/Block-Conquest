extends SceneTree
## The authored bottom bar receives real pointer/key events in both encounter scenes.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks: int = 0
var failures: Array[String] = []
var game: Node3D
var hud: Control
var visual: bool = false

func _initialize() -> void:
	visual = DisplayServer.get_name() != "headless"
	if visual:
		root.visible = false
		root.unfocusable = true
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func settle() -> void:
	await create_timer(0.22, true, false, true).timeout

func modifier(key_code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key_code
	event.physical_keycode = key_code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func click(button: BaseButton, control: bool = false, shift: bool = false, held_seconds: float = 0.0) -> void:
	if control: await modifier(KEY_CTRL, true)
	if shift: await modifier(KEY_SHIFT, true)
	var at: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	await process_frame
	check(root.gui_get_hovered_control() == button, "native pointer reaches " + str(button.name))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.ctrl_pressed = control
		event.shift_pressed = shift
		root.push_input(event, true)
		await process_frame
		if pressed and held_seconds > 0.0:
			await create_timer(held_seconds, true, false, true).timeout
	if control: await modifier(KEY_CTRL, false)
	if shift: await modifier(KEY_SHIFT, false)
	await settle()

func key(key_code: Key, control: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key_code
		event.physical_keycode = key_code
		event.ctrl_pressed = control
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func shot(name: String) -> void:
	if visual:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://.local/rogue_hud_" + name + ".png") == OK, "capture " + name)

func visible_slots() -> Array:
	return hud.get_node("%ArmySlots").get_children().filter(func(slot): return slot.visible)

func load_encounter(kind: String) -> void:
	if is_instance_valid(game):
		await game.prepare_shutdown()
	var session: Node = root.get_node("Session")
	session.rogue.state = RogueRunState.new()
	check(session.rogue.state.start_new("melee", "steady", 24681) == OK, "create isolated roster " + kind)
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = kind
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	game = current_scene
	hud = game.hud
	while not game._match_ready:
		await process_frame
	check(not hud.get_node("%Commands").visible and not hud.get_node("%Groups").visible, "intro hides all command surfaces")
	game.skip_intro()
	# Freeze simulation while testing the live UI; issuing orders still uses the real command bus.
	game.set_physics_process(false)
	game._set_combat_processing(false)
	game.camera_rig.edge_scroll = false
	await settle()

func validate_layout(size_pixels: Vector2i) -> void:
	var screen: Rect2 = root.get_visible_rect()
	for name: String in ["Commands", "MapPanel", "Groups"]:
		var panel: Control = hud.get_node("%" + name)
		check(screen.encloses(panel.get_global_rect()), "%s stays on screen at %d" % [name, size_pixels.x])
		for node: Node in panel.find_children("*", "Button", true, false):
			var button: Button = node
			if button.is_visible_in_tree():
				check(panel.get_global_rect().encloses(button.get_global_rect()), "%s contains %s at %d" % [name, button.name, size_pixels.x])
	check(hud.get_node("%Commands").size.y == 158.0, "normal battle bottom bar height at %d" % size_pixels.x)
	check(hud.get_node("%Minimap").size == Vector2(174, 160), "normal battle minimap usable size at %d" % size_pixels.x)
	check(not hud.get_node("%SelectionDetails").get_global_rect().intersects(hud.get_node("%ArmyList").get_global_rect()), "selection and army list do not overlap at %d" % size_pixels.x)

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute("res://.local")
	var save_exists: bool = FileAccess.file_exists("user://rogue_run.json")
	var save_hash: String = FileAccess.get_sha256("user://rogue_run.json") if save_exists else ""
	await load_encounter("outpost")
	var army: Array = hud._army_units.duplicate()
	var roster: Array = root.get_node("Session").rogue.state.data.roster.duplicate(true)
	check(hud.get_node("Commands/Margin/Content/Composition").visible, "battle entry presents auto-selected army composition")
	game.select_entities([])
	await settle()
	check(visible_slots().size() == army.size(), "every deployed unit has a clickable portrait")
	check(not hud.get_node("%Base").visible, "outpost does not show an absent headquarters action")
	await click(visible_slots()[0], false, false, 0.32)
	check(game.selection == [army[0]], "portrait click selects that unit through RTS selection")
	check(hud.get_node("%SelectedPortrait").texture != null, "selected unit keeps its native model portrait")
	army[0].hp -= 7.0
	hud.refresh()
	check(is_equal_approx(hud.get_node("%SelectionHP").value, army[0].hp), "selected health uses live battle health")
	check(is_equal_approx(visible_slots()[0].get_node("Health").value, army[0].hp), "roster card health uses live battle health")
	var effective: UnitDefinition = army[0].get_combat_definition()
	check(hud.get_node("%SelectedStats").text.contains(str(snappedf(effective.damage, 0.1))), "selected attack includes the run's runtime modifiers")
	await click(visible_slots()[1], false, true)
	check(game.selection.size() == 2 and army[0] in game.selection and army[1] in game.selection, "Shift portrait click adds a unit")
	await key(KEY_1, true)
	check(game.control_groups[1].size() == 2, "native Ctrl+1 stores the current selection")
	check(hud.get_node("Commands/Margin/Content/Composition").visible and not hud.get_node("%ArmyList").visible, "multi selection shows the selected army composition")
	game.select_entities([])
	await settle()
	await click(visible_slots()[2])
	await click(hud.get_node("%Group1"))
	check(game.selection.size() == 2 and army[0] in game.selection and army[1] in game.selection, "group button recalls the saved pair")
	check(hud.get_node("%Group1").button_pressed and hud.get_node("%Group1").text.ends_with("2"), "group shows selected state and live count")
	game.select_entities([])
	await settle()
	await click(visible_slots()[2])
	await click(hud.get_node("%Group1"), false, true)
	check(game.control_groups[1].size() == 3, "Shift group click appends a new unit")
	await click(hud.get_node("%Group2"), true)
	check(game.control_groups[2].size() == 1, "Ctrl group click stores a separate group")
	await key(KEY_1)
	check(game.selection.size() == 3, "native 1 recalls the larger group")
	await click(hud.get_node("%Hold"))
	game.command_bus.tick()
	check(game.selection.all(func(unit): return unit.order == BattleUnit.Order.HOLD), "hold button reaches the actual command bus")
	await click(hud.get_node("%Stop"))
	game.command_bus.tick()
	check(game.selection.all(func(unit): return unit.order == BattleUnit.Order.IDLE), "stop button reaches the actual command bus")
	await click(hud.get_node("%Attack"))
	check(game.attack_mode and game.selection.size() == 3, "attack mode does not clear selection through HUD click-through")
	game.set_attack_mode(false)
	await click(hud.get_node("%Army"))
	check(game.selection.size() == army.size(), "full army action keeps every deployed military unit")
	for size_pixels: Vector2i in SIZES:
		root.size = size_pixels
		await settle()
		validate_layout(size_pixels)
		await shot("outpost_%d" % size_pixels.x)
	await click(hud.get_node("Commands/Margin/Content/Composition").slots[0], true)
	check(game.selection.all(func(unit): return unit.unit_type == army[0].unit_type), "Ctrl portrait click selects the displayed unit's entire type")
	game.select_entities([army[0]])
	hud.refresh()
	await shot("single_unit")
	for i: int in range(5):
		game.spawn_unit("archer", 0, Vector3(-40, 0, i * 2.0))
	hud.refresh()
	check(not hud.get_node("%ArmyNext").disabled, "larger rosters expose a second page")
	await click(hud.get_node("%ArmyNext"))
	check(hud._army_page == 1 and visible_slots().size() == army.size() + 5 - 16, "pagination presents remaining units")
	await click(visible_slots()[0])
	check(game.selection.size() == 1 and game.selection[0] == hud._army_units[16], "page two portrait selects the correct unit")
	army[0].receive_damage(army[0].max_hp * 10.0)
	hud.refresh()
	check(army[0] not in hud._army_units and hud.get_node("%Group1").text.ends_with("2"), "fallen soldiers leave roster cards and group counts")
	check(root.get_node("Session").rogue.state.data.roster == roster, "battle health and UI selection do not change persistent roster")
	for kind: String in ["knight", "engineer", "cannon", "heavy_cannon", "light_cavalry"]:
		game.spawn_unit(kind, 0, Vector3(-40,0,12))
	game.select_army()
	await settle()
	var composition: SelectionComposition = hud.get_node("Commands/Margin/Content/Composition")
	check(composition.groups.size() > 8 and not composition.get_node("%Next").disabled, "large mixed army has multiple composition pages")
	var selected: Array = game.selection.duplicate()
	var old_focus: String = composition.focus_key
	await key(KEY_TAB)
	check(composition.focus_key != old_focus and game.selection == selected, "rogue Tab cycles selected types without changing orders")
	validate_layout(Vector2i(1600,900))
	check(hud.get_node("%Commands").get_global_rect().encloses(composition.get_node("Hint").get_global_rect()), "composition hint stays inside the battle bar")
	await load_encounter("siege")
	await click(hud.get_node("%Base"))
	check(game.selection == [game.headquarters], "siege headquarters action selects the actual base")
	check(hud.get_node("%SelectionHP").max_value == game.headquarters.max_hp, "base details show encounter-specific health")
	check(hud.get_node("%SelectedStats").text.contains("3 / 远甲 3"), "base details show encounter-specific armor")
	check(hud.get_node("%Attack").disabled and hud.get_node("%Stop").disabled, "base does not offer unsupported unit orders")
	check(hud.find_children("*", "Button", true, false).all(func(button): return not str(button.name).begins_with("Recruit") and not str(button.name).begins_with("Build")), "battle bar has no production or construction actions")
	root.size = Vector2i(1600, 900)
	await settle()
	await shot("siege_base")
	await game.prepare_shutdown()
	check(FileAccess.file_exists("user://rogue_run.json") == save_exists and (not save_exists or FileAccess.get_sha256("user://rogue_run.json") == save_hash), "HUD tests leave the user checkpoint unchanged")
	print("ROGUE_BATTLE_HUD ", checks - failures.size(), "/", checks, " passed; failures=", failures)
	quit(0 if failures.is_empty() else 1)
