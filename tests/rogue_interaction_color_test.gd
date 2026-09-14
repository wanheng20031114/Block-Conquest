extends SceneTree
## Real mouse hover/selection and inherited native state colors on the pale UI.
const OUTPUT := "res://artifacts/rogue_interaction_colors"
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
var map: Node3D
var army: RogueArmyPanel
var rogue: RogueSession

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func hover(control: Control, local_point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_transform() * local_point
	motion.global_position = motion.position
	root.push_input(motion, true)
	await create_timer(0.24).timeout
	check(root.gui_get_hovered_control() == control, "native mouse hover reaches " + control.name)

func click(control: Control, local_point: Vector2) -> void:
	await hover(control, local_point)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_transform() * local_point
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	await create_timer(0.24).timeout

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png") == OK, "capture " + name)

func contrast(foreground: Color, background: Color) -> float:
	var front := Color(clampf(foreground.r, 0.0, 1.0), clampf(foreground.g, 0.0, 1.0), clampf(foreground.b, 0.0, 1.0)).srgb_to_linear()
	var back := Color(clampf(background.r, 0.0, 1.0), clampf(background.g, 0.0, 1.0), clampf(background.b, 0.0, 1.0)).srgb_to_linear()
	var a: float = front.r * 0.2126 + front.g * 0.7152 + front.b * 0.0722
	var b: float = back.r * 0.2126 + back.g * 0.7152 + back.b * 0.0722
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)

func record(widget: String, state: String, foreground: Color, background: Color, minimum: float = 4.5) -> void:
	var ratio := contrast(foreground, background)
	evidence.append({"widget": widget, "state": state, "foreground": foreground.to_html(false), "background": background.to_html(false), "contrast": snappedf(ratio, 0.01)})
	check(ratio >= minimum, "%s %s contrast %.2f >= %.1f" % [widget, state, ratio, minimum])

func inspect_list(list: ItemList, selected: bool) -> void:
	var font_key := "font_hovered_selected_color" if selected else "font_hovered_color"
	var style_key := "hovered_selected_focus" if selected and list.has_focus() else ("hovered_selected" if selected else "hovered")
	var background: StyleBoxFlat = list.get_theme_stylebox(style_key)
	record(list.name, font_key, list.get_theme_color(font_key), background.bg_color)

func inspect_button(button: Button, state: String = "hover") -> void:
	var style_key := "disabled" if button.disabled else ("pressed" if button.button_pressed else "hover")
	var font_key := "font_disabled_color" if button.disabled else ("font_hover_pressed_color" if button.button_pressed else "font_hover_color")
	var style: StyleBoxTexture = button.get_theme_stylebox(style_key)
	var texture: Image = style.texture.get_image()
	var background := texture.get_pixel(texture.get_width() / 2, texture.get_height() / 2) * style.modulate_color
	record(button.name, state, button.get_theme_color(font_key) * button.self_modulate, background * button.self_modulate, 3.0 if button.disabled else 4.5)

func _run() -> void:
	create_timer(55, true, false, true).timeout.connect(func(): push_error("Rogue interaction capture timeout"); quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	rogue = root.get_node("Session").rogue
	check(rogue.state.start_new("ranged", "steady", 73113) == OK, "prepare isolated in-memory army")
	rogue.state.data.roster[1].deployed = false
	rogue.state.data.bread = 15
	rogue.state.data.tickets[0].candidates = ["swordsman", "archer", "heavy_cannon"]
	map = load("res://scenes/rogue/rogue_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	army = map.army
	army.open_panel("formation")
	await create_timer(0.35).timeout
	var roster: ItemList = army.get_node("%ArmyRoster")
	await hover(roster, roster.get_item_rect(1).get_center())
	inspect_list(roster, false)
	await capture("formation_hover")
	await click(roster, roster.get_item_rect(1).get_center())
	check(roster.is_selected(1), "native click selects roster unit")
	inspect_list(roster, true)
	await capture("formation_hover_selected")
	army._set_status("此处与其他单位重叠，请换一个位置。", true)
	record("ArmyStatus", "error", army.get_node("%ArmyStatus").get_theme_color("font_color"), Color("eeecda"))
	var map_choice: OptionButton = army.get_node("%MapChoice")
	await hover(map_choice, map_choice.size * 0.5)
	inspect_button(map_choice)
	await capture("formation_dropdown_hover_error")
	var recruit_tab: Button = army.get_node("%RecruitTab")
	await hover(recruit_tab, recruit_tab.size * 0.5)
	inspect_button(recruit_tab)
	await click(recruit_tab, recruit_tab.size * 0.5)
	check(army._tab == "recruit", "native tab click opens recruitment")
	inspect_button(recruit_tab, "hover_pressed")
	await capture("recruit_tab_hover_pressed")
	var candidates: ItemList = army.get_node("%ArmyCandidates")
	await hover(candidates, candidates.get_item_rect(1).get_center())
	inspect_list(candidates, false)
	await capture("recruit_hover")
	await click(candidates, candidates.get_item_rect(1).get_center())
	check(candidates.is_selected(1), "native click selects recruit candidate")
	inspect_list(candidates, true)
	await capture("recruit_hover_selected")
	var tickets: ItemList = army.get_node("%ArmyTickets")
	await hover(tickets, tickets.get_item_rect(0).get_center())
	inspect_list(tickets, true)
	await capture("ticket_hover_selected")
	army._set_status("军队已准备就绪。")
	record("ArmyStatus", "success", army.get_node("%ArmyStatus").get_theme_color("font_color"), Color("eeecda"))
	army.close_panel()
	for route: Dictionary in rogue.state.data.nodes:
		if route.kind == "event" and route.event_id == "bread_cart":
			rogue.state.data.active_node = route.id
			break
	rogue.state.data.phase = "node"
	rogue.state.data.ap = 0
	rogue.state.data.gold = 0
	map._refresh()
	await process_frame
	await process_frame
	var option: Button = map.content.get_node("Options/Option0")
	await hover(option, option.size * 0.5)
	check(option.disabled, "unaffordable event choice stays disabled while hovered")
	inspect_button(option, "disabled_hover")
	await capture("event_disabled_hover")
	var output := FileAccess.open(OUTPUT + "/contrasts.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(evidence, "\t"))
	output.close()
	print("ROGUE_INTERACTION_COLORS=%d FAILURES=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
