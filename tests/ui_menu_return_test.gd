extends SceneTree
## Native pointer/keyboard regression for returning from the four lobby menus.
## Run with --headless for checks, or -- --menu-capture --label=before for one GPU image.
## Only opens/closes panels: never starts a match, connects, applies or saves settings.

class OfflineRelay extends RelayClient:
	var connection_attempts: int = 0
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func connect_relay(_endpoint: String, _endpoint_port: int = 24571) -> Error:
		connection_attempts += 1
		return ERR_UNAUTHORIZED

class MenuSession extends Node:
	signal load_failed(message: String)
	var settings: GameSettings
	var relay: OfflineRelay

const ENTRY_NAMES: Array[String] = ["Multiplayer", "SoloMenu", "Codex", "Settings"]
const USER_FILES: Array[String] = ["user://settings.cfg", "user://lobby_preferences.cfg", "user://rogue_run.json"]
var checks: int = 0
var failures: Array[String] = []
var lobby: Node3D
var session: MenuSession
var neutral: Dictionary = {}
var capture: bool = false
var label: String = "current"

func _initialize() -> void:
	capture = "--menu-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	if DisplayServer.get_name() != "headless":
		root.visible = false
		root.unfocusable = true
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=").validate_filename()
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL ", message)

func settle() -> void:
	await create_timer(0.25, true, false, true).timeout

func move_pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)
	await settle()

func click(button: BaseButton) -> void:
	await move_pointer(button.get_global_rect().get_center())
	check(root.gui_get_hovered_control() == button, "native pointer reaches " + str(button.name))
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func press_key(key_code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key_code
		event.physical_keycode = key_code
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await settle()

func open_panel(entry_name: String) -> Control:
	match entry_name:
		"Multiplayer": return lobby.get_node("%OnlinePanel")
		"SoloMenu": return lobby.get_node("%SoloPanel")
		"Codex": return lobby.get_node("%UnitCodex")
		"Settings": return session.settings.menu
	return null

func close_button(entry_name: String) -> BaseButton:
	match entry_name:
		"Multiplayer": return lobby.get_node("%CloseOnline")
		"SoloMenu": return lobby.get_node("CanvasLayer/UI/SoloPanel/SoloScroll/Content/Heading/CloseSolo")
		"Codex": return lobby.get_node("%UnitCodex").get_node("%CloseCodex")
		"Settings": return session.settings.menu.get_node("%Close")
	return null

func report(button: BaseButton, route: String) -> void:
	var motion: Dictionary = button.get_meta(UIMotion.BUTTON_META)
	var focus: Control = root.gui_get_focus_owner()
	print("MENU_RETURN_STATE ", JSON.stringify({"entry": button.name, "route": route,
		"scale": [button.scale.x, button.scale.y],
		"self_modulate": [button.self_modulate.r, button.self_modulate.g, button.self_modulate.b, button.self_modulate.a],
		"focused": button.has_focus(), "visible_focus": button.has_focus(true), "focus_owner": str(focus.name) if focus != null else "",
		"hovered": button.is_hovered(), "pressed": button.button_pressed, "draw_mode": button.get_draw_mode(),
		"motion_hover": motion.hover, "motion_focus": motion.focus, "motion_down": motion.down}))
	check(not button.is_hovered(), route + " " + str(button.name) + " pointer has left")
	check(not button.button_pressed, route + " " + str(button.name) + " press is released")
	check(button.get_draw_mode() == BaseButton.DRAW_NORMAL, route + " " + str(button.name) + " native draw returns to normal")
	check(not button.has_focus(true), route + " " + str(button.name) + " returned pointer focus has no persistent highlight")
	check(button.scale.is_equal_approx(neutral[button.name].scale), route + " " + str(button.name) + " scale returns to authored size")
	check(button.self_modulate.is_equal_approx(neutral[button.name].color), route + " " + str(button.name) + " brightness returns to authored color")

func user_file_fingerprints() -> Dictionary:
	var result: Dictionary = {}
	for path: String in USER_FILES:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	return result

func _run() -> void:
	create_timer(35.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var original_files: Dictionary = user_file_fingerprints()
	var original_session: Node = root.get_node("Session")
	original_session.name = "OriginalSession"
	session = MenuSession.new()
	session.name = "Session"
	session.settings = original_session.settings
	session.relay = OfflineRelay.new()
	session.add_child(session.relay)
	root.add_child(session)
	lobby = load("res://scenes/lobby.tscn").instantiate()
	for entry_name: String in ENTRY_NAMES:
		var button: BaseButton = lobby.get_node("%" + entry_name)
		neutral[button.name] = {"scale": button.scale, "color": button.self_modulate}
	root.add_child(lobby)
	current_scene = lobby
	await settle()
	for entry_name: String in ENTRY_NAMES:
		var button: BaseButton = lobby.get_node("%" + entry_name)
		for route: String in ["mouse_close", "escape"]:
			await click(button)
			check(open_panel(entry_name).is_visible_in_tree(), entry_name + " opens through mouse input")
			if route == "mouse_close":
				await click(close_button(entry_name))
			else:
				await move_pointer(Vector2(1500, 850))
				await press_key(KEY_ESCAPE)
			await move_pointer(Vector2(1500, 850))
			check(not open_panel(entry_name).is_visible_in_tree(), route + " " + entry_name + " panel closes")
			report(button, route)
			if capture and entry_name == "Multiplayer" and route == "mouse_close":
				DirAccess.make_dir_recursive_absolute("res://.local")
				await RenderingServer.frame_post_draw
				var path: String = "res://.local/menu_return_" + label + ".png"
				check(root.get_texture().get_image().save_png(path) == OK, "capture multiplayer return")
	# Seed the same hidden entry focus as the real menu, then navigate and activate
	# safe panel entries. Enter is never sent to QuitGame, SoloStart or Apply.
	lobby.get_node("%SoloMenu").grab_focus(true)
	await press_key(KEY_TAB)
	var multiplayer: BaseButton = lobby.get_node("%Multiplayer")
	check(multiplayer.has_focus(true), "native Tab shows keyboard focus on multiplayer")
	if multiplayer.has_focus():
		await press_key(KEY_ENTER)
		check(open_panel("Multiplayer").is_visible_in_tree(), "native Enter opens keyboard-focused multiplayer")
		await click(close_button("Multiplayer"))
	await press_key(KEY_UP)
	var solo: BaseButton = lobby.get_node("%SoloMenu")
	check(solo.has_focus(true), "native up arrow shows keyboard focus on solo")
	if solo.has_focus():
		await press_key(KEY_ENTER)
		check(open_panel("SoloMenu").is_visible_in_tree(), "native Enter opens keyboard-focused solo")
		var difficulty: OptionButton = lobby.get_node("%SoloDifficulty")
		await click(difficulty)
		check(difficulty.get_popup().visible, "native mouse opens difficulty dropdown")
		await press_key(KEY_ESCAPE)
		check(not difficulty.get_popup().visible, "Escape dismisses the difficulty dropdown")
		check(open_panel("SoloMenu").is_visible_in_tree(), "dropdown Escape keeps the solo panel open")
		await click(close_button("SoloMenu"))
	check(session.relay.connection_attempts == 0, "menus make no connection attempts")
	check(user_file_fingerprints() == original_files, "settings, lobby preferences and rogue save stay unchanged")
	print("UI_MENU_RETURN ", checks - failures.size(), "/", checks, " passed; label=", label, "; failures=", failures)
	quit(0 if failures.is_empty() else 1)
