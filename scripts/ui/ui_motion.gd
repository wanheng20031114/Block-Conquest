class_name UIMotion
extends RefCounted
## Small, interruptible material motions shared by menus and in-game panels.
## References: GodotGameUI's hover/show binding; native Godot 4.6 Control/Tween.

const BUTTON_META: StringName = &"ui_motion_button"
const PANEL_META: StringName = &"ui_motion_panel"
const BUTTON_DURATION: float = 0.12
const REVEAL_DURATION: float = 0.18

static func bind_buttons(root: Node, theme_colors: bool = false) -> void:
	_bind_buttons(root, false, theme_colors)

## Opt-in menu profile; battle controls retain bind_buttons() unchanged.
static func bind_menu_buttons(root: Node) -> void:
	_bind_buttons(root, true, true)

static func _bind_buttons(root: Node, menu: bool, theme_colors: bool) -> void:
	if root is BaseButton:
		_bind_button(root as BaseButton, menu, theme_colors)
	for child: Node in root.get_children():
		_bind_buttons(child, menu, theme_colors)

static func _bind_button(button: BaseButton, menu: bool = false, theme_colors: bool = false) -> void:
	if button.has_meta(BUTTON_META):
		return
	var state: Dictionary = {"scale": button.scale, "color": button.self_modulate,
		"hover": false, "focus": button.has_focus(true), "down": false,
		"disabled": button.disabled, "tween": null, "menu": menu, "theme_colors": theme_colors,
		"hover_scale": float(button.get_meta(&"ui_motion_hover_scale", 1.025 if menu else 1.02))}
	button.set_meta(BUTTON_META, state)
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_button_state.bind(button, "hover", true))
	button.mouse_exited.connect(_button_state.bind(button, "hover", false))
	button.focus_entered.connect(_button_focus_changed.bind(button))
	button.focus_exited.connect(_button_focus_changed.bind(button))
	button.button_down.connect(_button_state.bind(button, "down", true))
	button.button_up.connect(_button_state.bind(button, "down", false))
	button.resized.connect(_button_resized.bind(button))
	button.visibility_changed.connect(_button_visibility.bind(button))
	# BaseButton has no disabled_changed signal. Its native redraw notification
	# catches that change without adding a polling node to every button.
	button.draw.connect(_button_draw.bind(button))
	button.tree_exiting.connect(_button_reset.bind(button))

static func _button_state(button: BaseButton, key: String, value: bool) -> void:
	var state: Dictionary = button.get_meta(BUTTON_META)
	state[key] = value
	if not button.is_visible_in_tree() or button.disabled:
		_button_reset(button)
		return
	# A user's interaction takes precedence over a delayed menu entrance.
	if state.menu and value and button.has_meta(PANEL_META):
		_panel_cleanup(button)
	_kill(state)
	# Queue slots may opt into a fixed hover footprint with scene-authored
	# metadata/ui_motion_hover_scale = 1.0; their light and press feedback remain.
	# Native hidden focus remembers a mouse user's keyboard return target without
	# highlighting the button. Only visible keyboard focus adds material feedback.
	var strength: float = (0.96 if state.menu else 0.98) if state.down else (float(state.hover_scale) if state.hover else 1.0)
	var light: float = 0.91 if state.down else (1.10 if state.hover or state.focus else 1.0)
	# Menu themes own their state palette; RGB multiplication washes out pastels.
	# Battle buttons retain the original light response.
	if state.theme_colors:
		light = 1.0
	var color: Color = state.color
	color = Color(color.r * light, color.g * light, color.b * light, color.a)
	var tween: Tween = _tween(button).set_parallel(true)
	if state.menu and not state.down:
		tween.set_trans(Tween.TRANS_BACK)
	state.tween = tween
	var duration: float = 0.18 if state.menu and not state.down else BUTTON_DURATION
	tween.tween_property(button, "scale", state.scale * strength, duration)
	tween.tween_property(button, "self_modulate", color, duration)

static func _button_resized(button: BaseButton) -> void:
	button.pivot_offset = button.size * 0.5

static func _button_focus_changed(button: BaseButton) -> void:
	if not button.has_focus():
		button.get_meta(BUTTON_META).down = false
	_button_state(button, "focus", button.has_focus(true))

static func _button_visibility(button: BaseButton) -> void:
	if not button.is_visible_in_tree():
		_button_reset(button)

static func _button_draw(button: BaseButton) -> void:
	var state: Dictionary = button.get_meta(BUTTON_META)
	if state.disabled != button.disabled:
		state.disabled = button.disabled
		_button_reset(button)
	elif not button.disabled and state.focus != button.has_focus(true):
		# Changing hidden focus on the same owner redraws it without emitting
		# focus_entered/focus_exited (including a mouse click on keyboard focus).
		_button_focus_changed(button)

static func _button_reset(button: BaseButton) -> void:
	var state: Dictionary = button.get_meta(BUTTON_META)
	_kill(state)
	state.hover = false
	state.focus = false
	state.down = false
	button.scale = state.scale
	button.self_modulate = state.color

## Call after show() and the panel's content/layout update. Calling repeatedly
## interrupts the previous reveal and never compounds position or opacity.
static func reveal(control: Control, direction: Vector2 = Vector2(0, 12)) -> Tween:
	return _reveal(control, direction, REVEAL_DURATION, 0.0, 0.985, true, Tween.TRANS_CUBIC, false)

## GodotGameUI-inspired stagger and soft overshoot, enabled only by menus.
static func reveal_menu(control: Control, direction: Vector2 = Vector2(0, 18), delay: float = 0.0) -> Tween:
	return _reveal(control, direction, 0.30, delay, 0.96, control is not BaseButton, Tween.TRANS_BACK, true)

static func _reveal(control: Control, direction: Vector2, duration: float, delay: float, start_scale: float, animate_scale: bool, transition: Tween.TransitionType, follow_layout: bool) -> Tween:
	var state: Dictionary = _panel_state(control)
	_panel_restore(control, state)
	control.show()
	state.active = true
	state.direction = Vector2.ZERO if control.get_parent() is Container else direction
	state.progress = 0.0
	state.alpha = control.modulate.a
	state.scale = control.scale
	state.start_scale = start_scale
	state.animate_scale = animate_scale
	state.follow_layout = follow_layout
	control.pivot_offset = control.size * 0.5
	# A Container owns a child's offsets. Its reveal only changes visual scale
	# and opacity; independent panels may additionally move a few pixels.
	_panel_step(0.0, control)
	var tween: Tween = _tween(control).set_trans(transition)
	state.tween = tween
	tween.tween_method(_panel_step.bind(control), 0.0, 1.0, duration).set_delay(delay)
	tween.tween_callback(_panel_finished.bind(control, false))
	return tween

static func dismiss(control: Control, direction: Vector2 = Vector2(0, 8)) -> Tween:
	var state: Dictionary = _panel_state(control)
	_panel_restore(control, state)
	state.active = true
	state.direction = Vector2.ZERO if control.get_parent() is Container else direction
	state.progress = 1.0
	state.alpha = control.modulate.a
	state.scale = control.scale
	state.start_scale = 0.985
	state.animate_scale = true
	state.follow_layout = false
	var tween: Tween = _tween(control)
	state.tween = tween
	tween.tween_method(_panel_step.bind(control), 1.0, 0.0, 0.12)
	tween.tween_callback(_panel_finished.bind(control, true))
	return tween

static func _panel_state(control: Control) -> Dictionary:
	if not control.has_meta(PANEL_META):
		control.set_meta(PANEL_META, {"tween": null, "active": false,
			"offset": Vector2.ZERO, "alpha": control.modulate.a,
			"scale": control.scale, "direction": Vector2.ZERO, "progress": 1.0,
			"start_scale": 0.985, "animate_scale": true, "follow_layout": false})
		control.visibility_changed.connect(_panel_visibility.bind(control))
		control.tree_exiting.connect(_panel_cleanup.bind(control))
		control.resized.connect(_panel_resized.bind(control))
	return control.get_meta(PANEL_META)

static func _panel_step(progress: float, control: Control) -> void:
	var state: Dictionary = control.get_meta(PANEL_META)
	state.progress = progress
	control.modulate.a = float(state.alpha) * clampf(progress, 0.0, 1.0)
	if state.animate_scale:
		control.scale = state.scale * lerpf(float(state.start_scale), 1.0, progress)
	if state.direction != Vector2.ZERO:
		# Apply only our visual displacement. Native anchor movement caused by
		# window resizing remains intact instead of snapping to an old position.
		var next_offset: Vector2 = state.direction * (1.0 - progress)
		control.position += next_offset - state.offset
		state.offset = next_offset

static func _panel_restore(control: Control, state: Dictionary) -> void:
	_kill(state)
	if state.active:
		control.modulate.a = state.alpha
		if state.animate_scale:
			control.scale = state.scale
		if state.direction != Vector2.ZERO:
			control.position -= state.offset
	state.offset = Vector2.ZERO
	state.active = false

static func _panel_finished(control: Control, hide_after: bool) -> void:
	var state: Dictionary = control.get_meta(PANEL_META)
	state.tween = null
	_panel_restore(control, state)
	if hide_after:
		control.hide()

static func _panel_visibility(control: Control) -> void:
	if not control.is_visible_in_tree():
		_panel_cleanup(control)

static func _panel_cleanup(control: Control) -> void:
	_panel_restore(control, control.get_meta(PANEL_META))

static func _panel_resized(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var state: Dictionary = control.get_meta(PANEL_META)
	if state.active:
		# Scale/opacity-only menu reveals can follow a Container's new size.
		# Cancelling here would skip every newly opened settings page's entrance.
		if state.follow_layout and state.direction == Vector2.ZERO:
			_panel_step(float(state.progress), control)
		else:
			# Positional reveals and the original combat profile yield to layout.
			_panel_restore(control, state)

static func _tween(control: Control) -> Tween:
	return control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

static func _kill(state: Dictionary) -> void:
	var previous: Tween = state.tween
	if previous != null and previous.is_valid():
		previous.kill()
	state.tween = null
