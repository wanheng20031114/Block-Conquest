extends SceneTree
## Native gesture routing across skill aiming, modal UI and scene transitions.

var game: Node3D
var settings: GameSettings
var checks := 0
var failures: Array[String] = []
var pointer := Vector2(800, 420)
var held_buttons := 0
var view_samples := 0
var view_errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)


func _view_error() -> String:
	var camera: Camera3D = game.camera
	camera.force_update_transform()
	var rect := root.get_visible_rect()
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for height: float in [0.0, -1.18]:
		var bounds: Rect2 = game.map.definition.camera_bounds
		bounds = bounds.grow(-2.0 if height == 0.0 else 0.0).grow(0.03)
		var plane := Plane(Vector3.UP, height)
		for corner: Vector2 in corners:
			var hit: Variant = plane.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
			if hit == null:
				return "corner %s misses plane y=%s" % [corner, height]
			var point: Vector3 = hit
			if not point.is_finite() or not bounds.has_point(Vector2(point.x, point.z)):
				return "corner %s hits %s outside %s" % [corner, point, bounds]
	return ""


func _observe(label: String) -> void:
	if game == null:
		return
	view_samples += 1
	var error := _view_error()
	if not error.is_empty():
		view_errors.append(label + ": " + error)


func _motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	pointer = at
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = held_buttons
	root.push_input(event, true)
	_observe("native mouse motion")


func _button(which: int, down: bool) -> void:
	if which in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var bit := 1 << (which - 1)
		held_buttons = held_buttons | bit if down else held_buttons & ~bit
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = pointer
	event.global_position = pointer
	event.button_index = which
	event.button_mask = held_buttons
	event.pressed = down
	root.push_input(event, true)
	_observe("native mouse button %d" % which)


func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.window_id = root.get_window_id()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	root.push_input(event, true)
	_observe("native key %s" % OS.get_keycode_string(code))


func _tap(code: int) -> void:
	_key(code, true)
	_key(code, false)


func _wheel(which: int) -> void:
	_button(which, true)
	_button(which, false)


func _click(control: Control) -> void:
	_motion(control.get_global_rect().get_center())
	_button(MOUSE_BUTTON_LEFT, true)
	_button(MOUSE_BUTTON_LEFT, false)


func _advance(count: int = 12) -> void:
	for frame: int in count:
		game.camera_rig._process([1.0 / 120.0, 1.0 / 30.0, 0.1][frame % 3])
		_observe("camera easing frame %d" % frame)


func _reset_view() -> void:
	game.select_building(null)
	game.camera.size = 37.0
	game.camera_rig.zoom_target = 37.0
	game.camera_rig.focus_at(Vector3.ZERO, true)
	_motion(Vector2(800, 420))
	_observe("gesture fixture starts centered")


func _check_aim(label: String) -> void:
	var expected: Vector3 = game.skill_ground_at(pointer)
	check(game.armed_skill == 1 and game.ground_skill_target.is_finite() and expected.is_finite() and game.ground_skill_target.distance_to(expected) < 0.001, label + " retains ground-skill aiming at the native pointer")


func _skill_gesture(skill_first: bool) -> void:
	_reset_view()
	var label := "skill then middle" if skill_first else "middle then skill"
	if skill_first:
		_key(KEY_W, true)
		_button(MOUSE_BUTTON_MIDDLE, true)
	else:
		_button(MOUSE_BUTTON_MIDDLE, true)
		_key(KEY_W, true)
	check(game.camera_rig.dragging and game.armed_skill == 1, label + " starts both requested gestures")
	var before: Vector3 = game.camera_rig.destination
	_motion(pointer + Vector2(48, 24), Vector2(48, 24))
	check(game.camera_rig.destination.distance_to(before) > 0.1, label + " pans without dropping the skill")
	_check_aim(label)
	_advance()
	_motion(pointer)
	_check_aim(label + " after camera easing")
	var energy_before: float = game.energy
	_button(MOUSE_BUTTON_RIGHT, true)
	_button(MOUSE_BUTTON_RIGHT, false)
	check(game.armed_skill == -1 and game.camera_rig.dragging and game.energy == energy_before and game.cooldowns[1] == 0.0, label + " right-click cancels only the unspent skill")
	before = game.camera_rig.destination
	_motion(pointer + Vector2(-36, -18), Vector2(-36, -18))
	check(game.camera_rig.destination.distance_to(before) > 0.1, label + " keeps panning while middle is still held")
	_button(MOUSE_BUTTON_MIDDLE, false)
	_key(KEY_W, false)
	before = game.camera_rig.destination
	_motion(pointer + Vector2(60, 30), Vector2(60, 30))
	check(not game.camera_rig.dragging and game.camera_rig.destination.is_equal_approx(before) and game.armed_skill == -1 and game.energy == energy_before, label + " release ends panning and the cancelled skill cannot fire later")
	_advance()


func _restart_middle(label: String) -> void:
	var before: Vector3 = game.camera_rig.destination
	_button(MOUSE_BUTTON_MIDDLE, true)
	_motion(pointer + Vector2(24, 12), Vector2(24, 12))
	check(game.camera_rig.dragging and game.camera_rig.destination.distance_to(before) > 0.1, label + " accepts a fresh middle press")
	_button(MOUSE_BUTTON_MIDDLE, false)


func _focus_loss() -> void:
	_reset_view()
	_button(MOUSE_BUTTON_MIDDLE, true)
	_key(KEY_W, true)
	_motion(pointer + Vector2(32, 16), Vector2(32, 16))
	# Exercise the real Window signal connection without moving OS focus away
	# from the user's editor or activating an automated test window.
	root.focus_exited.emit()
	check(not game.camera_rig.dragging and game.armed_skill == -1, "window focus loss cancels middle pan and skill together")
	var before: Vector3 = game.camera_rig.destination
	_motion(pointer + Vector2(48, 24), Vector2(48, 24))
	check(game.camera_rig.destination.is_equal_approx(before), "focus loss leaves no latched pan even before the old button release")
	_button(MOUSE_BUTTON_MIDDLE, false)
	_key(KEY_W, false)
	root.focus_entered.emit()
	_restart_middle("focus return")


func _modal_gesture(kind: String) -> void:
	_reset_view()
	_button(MOUSE_BUTTON_MIDDLE, true)
	_key(KEY_W, true)
	_motion(pointer + Vector2(30, 15), Vector2(30, 15))
	_tap(KEY_F1 if kind == "help" else KEY_ESCAPE)
	check(game._local_menu and not game.camera_rig.dragging and game.armed_skill == -1, kind + " opens through native input and cancels both gestures")
	if kind == "settings":
		await create_timer(0.35).timeout
		_click(game.hud.get_node("%PauseSettings"))
		check(settings.is_open() and game._local_menu, "normal settings entry keeps the local pause menu active")
	var before: Vector3 = game.camera_rig.destination
	var zoom_before: float = game.camera_rig.zoom_target
	_button(MOUSE_BUTTON_MIDDLE, false)
	_motion(Vector2(12, 440))
	_button(MOUSE_BUTTON_MIDDLE, true)
	_motion(pointer + Vector2(14, 10), Vector2(14, 10))
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.camera_rig.zoom_target, zoom_before), kind + " blocks wheel-up immediately")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.camera_rig.zoom_target, zoom_before), kind + " blocks wheel-down immediately")
	_advance()
	check(not game.camera_rig.dragging and game.camera_rig.destination.is_equal_approx(before) and is_equal_approx(game.camera_rig.zoom_target, zoom_before), kind + " blocks middle, motion and wheel behind its native overlay")
	if kind == "settings":
		_tap(KEY_ESCAPE)
		check(not settings.is_open() and game._local_menu, "closing settings returns only to pause")
	_tap(KEY_F1 if kind == "help" else KEY_ESCAPE)
	check(not game._local_menu and not game.hud.help_visible(), kind + " closes through its normal shortcut")
	_motion(Vector2(800, 420), Vector2(40, 20))
	check(not game.camera_rig.dragging and game.camera_rig.destination.is_equal_approx(before), kind + " does not resurrect the held pre-menu gesture")
	_button(MOUSE_BUTTON_MIDDLE, false)
	_key(KEY_W, false)
	_restart_middle(kind + " resume")


func _persistent_settings() -> void:
	check(settings.is_open() and not game._local_menu, "scene replacement preserves the real Session settings layer over an unpaused battle")
	var before: Vector3 = game.camera_rig.destination
	var zoom_before: float = game.camera_rig.zoom_target
	var selected_before: Node3D = game.selected
	var energy_before: float = game.energy
	var ratio_before: int = game.percentage
	var troops_before: int = game.marches.total_for(game.local_faction)
	_motion(Vector2(12, 440))
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_button(MOUSE_BUTTON_MIDDLE, true)
	_motion(pointer + Vector2(20, 10), Vector2(20, 10))
	_button(MOUSE_BUTTON_MIDDLE, false)
	_click(settings.menu.get_node("%Categories/Controls"))
	var slider: Control = settings.menu.get_node("%CameraSpeed")
	for step: int in 32:
		if root.gui_get_focus_owner() == slider:
			break
		_tap(KEY_TAB)
	check(root.gui_get_focus_owner() == slider, "native settings navigation places focus on a non-button control")
	_tap(KEY_SPACE)
	_tap(KEY_W)
	_tap(KEY_1)
	_advance()
	check(settings.is_open() and not game._local_menu and not game.camera_rig.dragging and game.camera_rig.destination.is_equal_approx(before) and is_equal_approx(game.camera_rig.zoom_target, zoom_before), "inherited settings block native wheel, middle, motion and Space from the battle camera")
	check(game.selected == selected_before and game.armed_skill == -1 and game.drag_source == null and game.energy == energy_before and game.percentage == ratio_before and game.marches.total_for(game.local_faction) == troops_before, "inherited settings leave selection, skills and orders unchanged")
	_tap(KEY_ESCAPE)
	check(not settings.is_open() and not game._local_menu, "Esc closes inherited settings without opening a second battle menu")


func _dispatch_wheel() -> void:
	_reset_view()
	var home: Node3D = game.by_id[0]
	game.camera_rig.focus_at(home.global_position, true)
	var at: Vector2 = game.camera.unproject_position(home.global_position + Vector3.UP * 1.5)
	_motion(at)
	_tap(KEY_2)
	_button(MOUSE_BUTTON_LEFT, true)
	check(game.drag_source == home and game.percentage == 50, "native left press starts a dispatch at the selected ratio")
	var zoom_before: float = game.camera_rig.zoom_target
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.percentage == 75 and is_equal_approx(game.camera_rig.zoom_target, zoom_before), "wheel up during dispatch adjusts troops without camera zoom")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(game.percentage == 50 and is_equal_approx(game.camera_rig.zoom_target, zoom_before), "wheel down during dispatch restores the ratio without camera zoom")
	_button(MOUSE_BUTTON_LEFT, false)
	check(game.drag_source == null, "same-building release clears the dispatch gesture")
	_motion(Vector2(800, 420))
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	check(game.camera_rig.zoom_target < zoom_before, "wheel resumes camera zoom after dispatch release")
	_advance()


func _boundary_gesture() -> void:
	_reset_view()
	_key(KEY_W, true)
	_button(MOUSE_BUTTON_MIDDLE, true)
	for relative: Vector2 in [Vector2(-10000, -10000), Vector2(10000, -10000), Vector2(10000, 10000), Vector2(-10000, 10000)]:
		# Native mouse capture can deliver relative movement outside the window.
		_motion(Vector2(800, 420) + relative, relative)
		_advance(18)
		check(game.camera_rig.dragging and game.armed_skill == 1, "captured skill-pan remains active at map boundary %s" % relative)
	_button(MOUSE_BUTTON_RIGHT, true)
	_button(MOUSE_BUTTON_RIGHT, false)
	_button(MOUSE_BUTTON_MIDDLE, false)
	_key(KEY_W, false)
	_motion(Vector2(800, 420))


func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	settings = session.get_node("Settings")
	var old_map: String = session.block_war_map_id
	var old_commander: StringName = session.block_war_commander
	var old_size := root.size
	var old_camera_speed := settings.camera_speed
	var old_zoom_speed := settings.zoom_speed
	root.size = Vector2i(1600, 900)
	session.block_war_map_id = "rift"
	session.block_war_commander = &"squirrel"
	settings.camera_speed = 1.0
	settings.zoom_speed = 1.0
	# Existing authored picker + persistent Session settings reproduce a host
	# starting a match while a ready guest is still looking at room settings.
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await create_timer(0.8).timeout
	_click(current_scene.get_node("%Settings"))
	check(settings.is_open(), "native picker Settings button opens the persistent layer")
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.update_hud()
	await physics_frame
	await create_timer(0.8).timeout
	_persistent_settings()
	_skill_gesture(false)
	_skill_gesture(true)
	_focus_loss()
	for kind: String in ["pause", "help", "settings"]:
		await _modal_gesture(kind)
	_dispatch_wheel()
	_boundary_gesture()
	check(view_samples > 100 and view_errors.is_empty(), "all %d native-input and easing samples keep the four ground/water corners inside scenery; first=%s" % [view_samples, view_errors[0] if not view_errors.is_empty() else "none"])
	settings.camera_speed = old_camera_speed
	settings.zoom_speed = old_zoom_speed
	session.block_war_map_id = old_map
	session.block_war_commander = old_commander
	await game.prepare_shutdown()
	root.size = old_size
	print("BLOCK_WAR_CAMERA_GESTURES checks=", checks, " failures=", failures.size(), " view_samples=", view_samples)
	quit(0 if failures.is_empty() else 1)
