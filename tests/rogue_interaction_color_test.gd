extends SceneTree
## Real mouse hover/selection and inherited native state colors on the pale UI.
const OUTPUT := "res://artifacts/rogue_interaction_colors"
const CHECKPOINT := "res://.local/rogue_interaction_color_checkpoint.json"
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

func style_color(style: StyleBox) -> Color:
	if style is StyleBoxFlat:
		return style.bg_color
	var paper: StyleBoxTexture = style
	var texture: Image = paper.texture.get_image()
	return texture.get_pixel(texture.get_width() / 2, texture.get_height() / 2) * paper.modulate_color

func inspect_card(card: Button, state: String, label_path: String) -> void:
	var label: Label = card.get_node(label_path)
	var style: StyleBox = card.get_theme_stylebox("disabled" if card.disabled else "hover")
	record(card.name + "/" + label.name, state, label.get_theme_color("font_color") * label.modulate, style_color(style), 3.0 if card.disabled else 4.5)

func inspect_button(button: Button, state: String = "hover") -> void:
	var style_key := "disabled" if button.disabled else ("pressed" if button.button_pressed else "hover")
	var font_key := "font_disabled_color" if button.disabled else ("font_hover_pressed_color" if button.button_pressed else "font_hover_color")
	var background: Color = style_color(button.get_theme_stylebox(style_key))
	record(button.name, state, button.get_theme_color(font_key) * button.self_modulate, background * button.self_modulate, 3.0 if button.disabled else 4.5)

func _run() -> void:
	create_timer(55, true, false, true).timeout.connect(func(): push_error("Rogue interaction capture timeout"); cleanup(); quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	rogue = root.get_node("Session").rogue
	rogue.save_path = CHECKPOINT
	check(rogue.state.start_new("ranged", "steady", 73113) == OK, "prepare isolated in-memory army")
	var initial_ticket: Dictionary = rogue.state.pending_recruit()
	initial_ticket.candidates = ["swordsman", "archer", "heavy_cannon"]
	check(rogue.state.discard_recruit(int(initial_ticket.uid)) == OK, "prepare formation without pending recruitment")
	rogue.state.data.roster[1].deployed = false
	rogue.state.data.bread = 3
	map = load("res://scenes/rogue/rogue_map.tscn").instantiate()
	root.add_child(map)
	current_scene = map
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	army = map.army
	army.open_panel("formation")
	await create_timer(0.35).timeout
	var roster: Button = army._rows["out:archer"]
	await hover(roster, roster.size * .5)
	inspect_card(roster, "group_hover", "Margin/Content/Name")
	await capture("formation_hover")
	await click(roster, roster.size * .5)
	check(army._selected_uids.size() == 4 and roster.get_meta("uids").all(func(uid: int) -> bool: return uid in army._selected_uids), "native row click selects the whole archer group")
	inspect_card(roster, "group_hover_selected", "Margin/Content/Name")
	await capture("formation_hover_selected")
	army._set_status("此处与其他单位重叠，请换一个位置。", true)
	record("ArmyStatus", "error", army.get_node("%ArmyStatus").get_theme_color("font_color"), Color("eeecda"))
	var map_choice: OptionButton = army.get_node("%MapChoice")
	await hover(map_choice, map_choice.size * 0.5)
	inspect_button(map_choice)
	await capture("formation_dropdown_hover_error")
	army._set_status("军队已准备就绪。")
	record("ArmyStatus", "success", army.get_node("%ArmyStatus").get_theme_color("font_color"), Color("eeecda"))
	army.close_panel()
	rogue.state.data.pending_recruits = [initial_ticket.duplicate(true)]
	rogue.state.data.recruit_return_phase = "map"
	rogue.state.data.phase = "recruit_unit"
	map._refresh()
	await create_timer(.65).timeout
	var recruit: Control = map.recruit_overlay
	var candidate: Button = recruit.cards[1]
	await hover(candidate, candidate.size * .5)
	inspect_card(candidate, "unit_hover", "Margin/Body/Name")
	check(candidate.position.y < -3.5, "native candidate hover raises only its own paper")
	await capture("recruit_units_hover")
	var expensive: Button = recruit.cards[2]
	await hover(expensive, expensive.size * .5)
	check(expensive.disabled, "unaffordable unit card remains disabled")
	inspect_card(expensive, "unit_disabled", "Margin/Body/Name")
	inspect_card(expensive, "unit_disabled", "Margin/Body/Description")
	await capture("recruit_units_disabled")
	await click(candidate, candidate.size * .5)
	await create_timer(.4).timeout
	check(rogue.state.data.phase == "recruit_batch" and rogue.state.data.recruit_kind == "archer", "native unit choice reaches persisted batch round")
	check(FileAccess.file_exists(CHECKPOINT), "unit choice saves only the isolated test checkpoint")
	rogue.state.data.bread = 2
	map._refresh()
	await create_timer(.65).timeout
	var batch: Button = recruit.cards[1]
	await hover(batch, batch.size * .5)
	inspect_card(batch, "batch_hover", "Margin/Body/Name")
	await capture("recruit_batches_hover")
	await hover(expensive, expensive.size * .5)
	check(expensive.disabled and int(expensive.get_meta("count")) == 9, "third archer batch shows nine units but is disabled with two bread")
	inspect_card(expensive, "batch_disabled", "Margin/Body/Name")
	inspect_card(expensive, "batch_disabled", "Margin/Body/Description")
	await capture("recruit_batches_disabled")
	await click(recruit.back_button, recruit.back_button.size * .5)
	await create_timer(.4).timeout
	check(rogue.state.data.phase == "recruit_unit", "native back returns to same ticket candidates")
	check(rogue.state.pending_recruit().candidates == initial_ticket.candidates, "native two-round navigation never redraws candidates")
	rogue.state.data.pending_recruits.clear()
	rogue.state.data.recruit_kind = ""
	rogue.state.data.recruit_return_phase = ""
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
	cleanup()
	print("ROGUE_INTERACTION_COLORS=%d FAILURES=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func cleanup() -> void:
	for path: String in [CHECKPOINT, CHECKPOINT + ".tmp"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
