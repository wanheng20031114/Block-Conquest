extends SceneTree
## Checks real scene controls after their native theme owners enter the tree.
## No battles, network sessions, settings writes, or player checkpoints run.
## Contrast is measured from resolved glyph colors and authored background
## resources, including texture center samples and translucent overlays.

const ACTIVE_MIN: float = 4.5
const DISABLED_MIN: float = 3.0
const SAMPLE_UV: Array[Vector2] = [Vector2(0.2, 0.2), Vector2(0.5, 0.2), Vector2(0.8, 0.2),
	Vector2(0.2, 0.5), Vector2(0.5, 0.5), Vector2(0.8, 0.5),
	Vector2(0.2, 0.8), Vector2(0.5, 0.8), Vector2(0.8, 0.8)]
const STATES: Dictionary = {
	"Button": [
		["normal", "font_color", ["normal"], ACTIVE_MIN],
		["hover", "font_hover_color", ["hover"], ACTIVE_MIN],
		["pressed", "font_pressed_color", ["pressed"], ACTIVE_MIN],
		["hover_pressed", "font_hover_pressed_color", ["hover_pressed"], ACTIVE_MIN],
		["focus", "font_focus_color", ["normal", "focus"], ACTIVE_MIN],
		["disabled", "font_disabled_color", ["disabled"], DISABLED_MIN]],
	"ItemList": [
		["normal", "font_color", ["panel"], ACTIVE_MIN],
		["hover", "font_hovered_color", ["panel", "hovered"], ACTIVE_MIN],
		["selected", "font_selected_color", ["panel", "selected"], ACTIVE_MIN],
		["selected_focus", "font_selected_color", ["panel", "selected_focus"], ACTIVE_MIN],
		["hover_selected", "font_hovered_selected_color", ["panel", "hovered_selected"], ACTIVE_MIN],
		["hover_selected_focus", "font_hovered_selected_color", ["panel", "hovered_selected_focus"], ACTIVE_MIN]],
	"TabBar": [
		["normal", "font_unselected_color", ["tab_unselected"], ACTIVE_MIN],
		["hover", "font_hovered_color", ["tab_hovered"], ACTIVE_MIN],
		["selected", "font_selected_color", ["tab_selected"], ACTIVE_MIN],
		["focus", "font_selected_color", ["tab_selected", "tab_focus"], ACTIVE_MIN],
		["disabled", "font_disabled_color", ["tab_disabled"], DISABLED_MIN]],
	"PopupMenu": [
		["normal", "font_color", ["panel"], ACTIVE_MIN],
		["hover", "font_hover_color", ["panel", "hover"], ACTIVE_MIN],
		["accelerator", "font_accelerator_color", ["panel"], ACTIVE_MIN],
		["separator", "font_separator_color", ["panel"], ACTIVE_MIN],
		["disabled", "font_disabled_color", ["panel"], DISABLED_MIN]],
	"LineEdit": [
		["normal", "font_color", ["normal"], ACTIVE_MIN],
		["selected", "font_selected_color", ["normal", "@selection_color"], ACTIVE_MIN],
		["focus", "font_color", ["normal", "focus"], ACTIVE_MIN],
		["placeholder", "font_placeholder_color", ["normal"], ACTIVE_MIN],
		["read_only", "font_uneditable_color", ["read_only"], DISABLED_MIN]]
}

var checks: int = 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var image_cache: Dictionary = {}
var control_count: int = 0

func _initialize() -> void:
	root.visible = false
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func(): quit(3))
	# Standalone authored UI scenes are sufficient. Their native child windows,
	# including OptionButton popup menus, inherit the exact in-game theme chain.
	await inspect_scene("res://scenes/unit_codex.tscn", ["Entries", "CategoryTabs", "CloseCodex", "PreviewIdle", "LoopPreview"])
	await inspect_scene("res://scenes/lobby.tscn", ["SoloMenu", "Multiplayer", "SoloDifficulty", "Nickname"])
	await inspect_scene("res://scenes/rogue/army_panel.tscn", ["ArmyRoster", "ArmyTickets", "ArmyCandidates", "FormationTab", "RecruitConfirm", "MapChoice"])
	await inspect_scene("res://scenes/hud.tscn", ["AttackButton", "ArmyButton", "Recruit0"])
	await inspect_scene("res://scenes/rogue/battle_hud.tscn", ["Army", "Attack", "Hold"])
	await inspect_scene("res://scenes/sandbox_hud.tscn", ["Place", "Select", "Run", "Map"])
	var settings: Node = root.get_node("Session/Settings")
	for name: String in ["WindowMode", "Vsync", "Apply"]:
		inspect_control(settings.get_node("%" + name), "settings/" + name)
	DirAccess.make_dir_recursive_absolute("res://artifacts/ui-style")
	var output := FileAccess.open("res://artifacts/ui-style/contrast-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "controls": control_count,
		"active_minimum": ACTIVE_MIN, "disabled_minimum": DISABLED_MIN,
		"failures": failures, "measurements": measurements}, "\t"))
	output.close()
	print("UI_CONTRAST_TEST ", JSON.stringify({"checks": checks, "controls": control_count, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func inspect_scene(path: String, names: Array) -> void:
	var scene: Node = load(path).instantiate()
	# Do not start background game/UI processing; native _ready still establishes
	# actual themes, models, and signal bindings before the properties are read.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(scene)
	await process_frame
	for name: String in names:
		inspect_control(scene.get_node("%" + name), path.get_file() + "/" + name)
	scene.queue_free()
	await process_frame

func inspect_control(control: Node, label: String) -> void:
	var family: String = ""
	if control is ItemList: family = "ItemList"
	elif control is TabBar: family = "TabBar"
	elif control is PopupMenu: family = "PopupMenu"
	elif control is LineEdit: family = "LineEdit"
	elif control is Button: family = "Button"
	check(not family.is_empty(), label + " has a supported native control type")
	if family.is_empty(): return
	control_count += 1
	for rule: Array in STATES[family]:
		var name: String = rule[1]
		var source: String = color_source(control, name)
		var color: Color = control.get_theme_color(name)
		# Include the shared motion contract at its settled state. self_modulate
		# affects this button's glyphs and styles, but not its parent's paper.
		var tint: Color = Color.WHITE
		if family == "Button" and control.has_meta(UIMotion.BUTTON_META):
			var light: float = 0.91 if rule[0] in ["pressed", "hover_pressed"] else (1.10 if rule[0] in ["hover", "focus"] else 1.0)
			var base: Color = control.get_meta(UIMotion.BUTTON_META).color
			tint = Color(base.r * light, base.g * light, base.b * light, base.a)
		var shown_color: Color = tinted(color, tint)
		var backgrounds: Array[Color] = background_samples(control, rule[2], tint)
		var minimum: float = INF
		for background: Color in backgrounds:
			minimum = minf(minimum, contrast(background.blend(shown_color), background))
		var state_label: String = "%s/%s" % [label, rule[0]]
		check(not source.is_empty(), state_label + " defines " + name + " in its actual theme chain")
		check(minimum + 0.000001 >= float(rule[3]), "%s contrast %.2f:1 >= %.1f:1; text=%s" % [state_label, minimum, rule[3], color.to_html()])
		measurements.append({"control": label, "family": family, "state": rule[0],
			"color_key": name, "text": color.to_html(), "source": source,
			"displayed_text": shown_color.to_html(), "motion_tint": tint.to_html(),
			"minimum_ratio": minimum, "target": rule[3],
			"background_samples": backgrounds.map(func(value: Color): return value.to_html())})
	if control is OptionButton or control is MenuButton:
		inspect_control(control.get_popup(), label + "/PopupMenu")

func color_source(control: Node, key: String) -> String:
	if control is Control and control.has_theme_color_override(key):
		return "local override"
	var types: Array[String] = []
	var variation: String = control.theme_type_variation
	if not variation.is_empty(): types.append(variation)
	var native: String = control.get_class()
	while not native.is_empty():
		types.append(native)
		native = ClassDB.get_parent_class(native)
	var owner: Node = control
	while owner != null:
		if (owner is Control or owner is Window) and owner.theme != null:
			var theme: Theme = owner.theme
			for type: String in types:
				if theme.has_color(key, type):
					return theme.resource_path + "/" + type
		owner = owner.get_parent()
	return ""

func background_samples(control: Node, styles: Array, tint: Color) -> Array[Color]:
	var layers: Array = []
	var owner: Node = control.get_parent()
	while owner != null:
		if owner is Panel or owner is PanelContainer:
			layers.push_front(style_samples(owner.get_theme_stylebox("panel")))
		# The codex's paper backdrop is an authored sibling below its content,
		# deliberately absent from the ItemList's transparent panel style.
		if owner.scene_file_path == "res://scenes/unit_codex.tscn":
			layers.push_front(style_samples(owner.get_node("Backdrop").get_theme_stylebox("panel")))
		if owner.scene_file_path == "res://scenes/rogue/army_panel.tscn":
			layers.push_front(style_samples(owner.get_node("Backdrop").get_theme_stylebox("panel")))
			layers.push_front(repeated(owner.get_node("Underlay").color))
		owner = owner.get_parent()
	var backgrounds: Array[Color] = []
	backgrounds.resize(SAMPLE_UV.size())
	backgrounds.fill(Color.TRANSPARENT)
	for layer: Array[Color] in layers:
		blend_samples(backgrounds, layer)
	for style_name: String in styles:
		if style_name.begins_with("@"):
			var selection: Color = control.get_theme_color(style_name.trim_prefix("@"))
			blend_samples(backgrounds, repeated(tinted(selection, tint)))
		else:
			var samples: Array[Color] = style_samples(control.get_theme_stylebox(style_name))
			for index: int in samples.size(): samples[index] = tinted(samples[index], tint)
			blend_samples(backgrounds, samples)
	# Some cards have authored translucent texture pixels, and lobby buttons
	# overlay the moving 3D view. Check both light and dark underlays instead of
	# discarding texture alpha or assuming the background is opaque cream.
	var composed: Array[Color] = []
	for background: Color in backgrounds:
		composed.append(Color.BLACK.blend(background))
		if background.a < 1.0: composed.append(Color.WHITE.blend(background))
	return composed

func tinted(color: Color, tint: Color) -> Color:
	return Color(minf(color.r * tint.r, 1.0), minf(color.g * tint.g, 1.0),
		minf(color.b * tint.b, 1.0), color.a * tint.a)

func repeated(color: Color) -> Array[Color]:
	var colors: Array[Color] = []
	colors.resize(SAMPLE_UV.size())
	colors.fill(color)
	return colors

func blend_samples(base: Array[Color], over: Array[Color]) -> void:
	for index: int in base.size():
		# Texture style modulation can exceed one. Clip the completed draw tint
		# before it is composited onto other canvas layers, as on an SDR output.
		base[index] = base[index].blend(tinted(over[index], Color.WHITE))

func style_samples(style: StyleBox) -> Array[Color]:
	if style is StyleBoxEmpty: return repeated(Color.TRANSPARENT)
	if style is StyleBoxFlat:
		return repeated(style.bg_color if style.draw_center else Color.TRANSPARENT)
	if style is StyleBoxTexture:
		if not style.draw_center: return repeated(Color.TRANSPARENT)
		var texture: Texture2D = style.texture
		var key: int = texture.get_instance_id()
		if not image_cache.has(key):
			var decoded: Image = texture.get_image()
			if decoded.is_compressed(): decoded.decompress()
			image_cache[key] = decoded
		var decoded: Image = image_cache[key]
		var region: Rect2 = style.region_rect
		if region.size == Vector2.ZERO: region = Rect2(Vector2.ZERO, Vector2(decoded.get_size()))
		var start := region.position + Vector2(style.texture_margin_left, style.texture_margin_top)
		var end := region.end - Vector2(style.texture_margin_right, style.texture_margin_bottom)
		var colors: Array[Color] = []
		for uv: Vector2 in SAMPLE_UV:
			var at: Vector2 = start + (end - start) * uv
			colors.append(decoded.get_pixel(clampi(roundi(at.x), 0, decoded.get_width() - 1), clampi(roundi(at.y), 0, decoded.get_height() - 1)) * style.modulate_color)
		return colors
	check(false, "unsupported background style " + style.get_class())
	return repeated(Color.TRANSPARENT)

func luminance(color: Color) -> float:
	var linear: Color = color.srgb_to_linear()
	return 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b

func contrast(first: Color, second: Color) -> float:
	var a: float = luminance(first)
	var b: float = luminance(second)
	return (maxf(a, b) + 0.05) / (minf(a, b) + 0.05)
