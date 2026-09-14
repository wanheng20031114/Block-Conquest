extends SceneTree
## Native material/layout review at the three supported desktop resolutions.
const OUTPUT := "res://artifacts/ui_medieval_rogue"
var failures: Array[String] = []
var checks := 0
var map: Node3D
var rogue: RogueSession

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func capture(name: String, width: int) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	inspect_buttons(name + " " + str(width))
	check(root.get_texture().get_image().save_png("%s/%s_%d.png" % [OUTPUT, name, width]) == OK, "capture " + name)

func inspect_buttons(page: String) -> void:
	for button: BaseButton in map.ui.find_children("*", "BaseButton", true, false):
		if not button.is_visible_in_tree():
			continue
		var state: String = "disabled" if button.disabled else ("pressed" if button.button_pressed else "normal")
		var style: StyleBox = button.get_theme_stylebox(state)
		if not style is StyleBoxTexture:
			continue
		var texture_style: StyleBoxTexture = style
		var corners := Vector2(texture_style.texture_margin_left + texture_style.texture_margin_right, texture_style.texture_margin_top + texture_style.texture_margin_bottom)
		check(button.size.x >= corners.x and button.size.y >= corners.y, "%s %s preserves its fixed texture corners" % [page, button.name])
		if not button is Button or button.text.is_empty():
			continue
		var font: Font = button.get_theme_font("font")
		var font_size: int = button.get_theme_font_size("font_size")
		var text_width := 0.0
		for line: String in button.text.split("\n"):
			text_width = maxf(text_width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		var left: float = style.get_content_margin(SIDE_LEFT)
		var right: float = button.size.x - style.get_content_margin(SIDE_RIGHT)
		if button is OptionButton:
			right -= button.get_theme_icon("arrow").get_width() + button.get_theme_constant("arrow_margin")
		check(text_width <= right - left + 1.0, "%s %s text fits its safe content width" % [page, button.name])
		var text_left: float = left if button.alignment == HORIZONTAL_ALIGNMENT_LEFT else (left + (right - left - text_width) * 0.5)
		check(text_left >= texture_style.texture_margin_left - 1.0 and button.size.x - text_left - text_width >= texture_style.texture_margin_right - 1.0, "%s %s text clears decorative corners" % [page, button.name])

func visible_bounds(control: Control, label: String) -> void:
	check(root.get_visible_rect().encloses(control.get_global_rect()), label + " fits viewport")

func _run() -> void:
	create_timer(75, true, false, true).timeout.connect(func(): push_error("Style capture timed out"); quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	rogue = root.get_node("Session").rogue
	check(rogue.state.start_new("ranged", "steady", 73113) == OK, "prepare army in memory")
	rogue.state.data.bread = 15
	rogue.state.data.tickets[0].candidates = ["swordsman", "archer", "heavy_cannon"]
	map = load("res://scenes/rogue/rogue_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	root.content_scale_size = Vector2i(1600, 900)
	var map_only: bool = "--map-only" in OS.get_cmdline_user_args()
	var resolutions: Array = [Vector2i(1600, 900)] if map_only else [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
	for resolution: Vector2i in resolutions:
		root.size = resolution
		await process_frame
		await process_frame
		map._new_run_requested = false
		map.army.hide()
		map._preview_id = -1
		map._refresh()
		check(map.get_node("Nodes").visible and map.ui.get_node("Top").visible, "map restores route markers and supplies")
		var battle_id: int = -1
		for route: Dictionary in rogue.state.data.nodes:
			if route.kind == "battle":
				battle_id = int(route.id)
				break
		map._select_node(battle_id)
		await capture("map", resolution.x)
		visible_bounds(map.ui.get_node("Top"), "map header")
		visible_bounds(map.preview, "node order")
		if map_only:
			_finish()
			return
		map._new_run_requested = true
		map._setup_step = 0
		map._refresh()
		await capture("strategy", resolution.x)
		check(not map.get_node("Nodes").visible and not map.ui.get_node("Top").visible, "setup backdrop hides route markers and supplies")
		visible_bounds(map.setup_content, "strategy choices")
		for index: int in 3:
			var choice: Control = map.setup_content.get_node("Choices/Choice%d" % index)
			check(choice.get_global_rect().encloses(choice.get_node("Effect").get_global_rect()), "strategy description fits paper card")
		map._setup_step = 1
		map._refresh()
		await capture("starter_army", resolution.x)
		map._new_run_requested = false
		map._refresh()
		map.army.open_panel("formation")
		await capture("formation", resolution.x)
		visible_bounds(map.army.get_node("%CloseArmy"), "army return")
		visible_bounds(map.army.get_node("%ArmyBoard"), "formation table")
		map.army._change_tab("recruit")
		await capture("recruit", resolution.x)
		visible_bounds(map.army.get_node("%RecruitConfirm"), "recruit confirm")
		map.army.close_panel()
	root.size = Vector2i(1600, 900)
	for kind: String in ["shop", "event", "camp"]:
		for route: Dictionary in rogue.state.data.nodes:
			if route.kind == kind:
				rogue.state.data.active_node = route.id
				rogue.state.data.phase = "node"
				map._refresh()
				await capture(kind, 1600)
				break
	rogue.state.data.phase = "siege_briefing"
	map._previous_phase = "siege_briefing"
	map._refresh()
	await capture("siege_briefing", 1600)
	map._toggle_pause_menu()
	await capture("pause", 1600)
	_finish()

func _finish() -> void:
	print("ROGUE_STYLE_CHECKS=%d FAILURES=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
