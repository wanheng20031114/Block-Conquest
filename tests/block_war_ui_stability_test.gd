extends SceneTree
## Regression for camera-boundary menu chatter, stale exit focus and moving hint text.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count: int = 3) -> void:
	for frame: int in count:
		await process_frame

func key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.window_id = root.get_window_id()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func pointer(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func place_camera(offset: Vector2) -> void:
	game.camera_rig.position = game.by_id[0].global_position + Vector3(offset.x, 0, offset.y)
	game.camera.force_update_transform()
	game.hud._position_selection()

func contrast(ink: Color, paper: Color) -> float:
	var first := ink.srgb_to_linear().get_luminance()
	var second := paper.srgb_to_linear().get_luminance()
	return (maxf(first, second) + 0.05) / (minf(first, second) + 0.05)

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.get_node("Session").block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	await create_timer(0.8).timeout
	var home: Node3D = game.by_id[0]
	var menu: Control = game.hud.get_node("%Selection")
	game.camera.size = 37.0
	pointer(Vector2(1500, 850))
	# These 0.1 m camera boundaries previously flipped the menu by 158–352 px.
	for edge: Vector2 in [Vector2(28, -12.6), Vector2(18, -11.4), Vector2(22, -6.5), Vector2(26, 12.4)]:
		game.select_building(null)
		place_camera(edge)
		game.select_building(home)
		var previous := menu.position
		var largest_step := 0.0
		var switches := 0
		for sample: int in 30:
			place_camera(edge + Vector2(0, 0.1 if sample % 2 == 0 else 0.0))
			var step := menu.position.distance_to(previous)
			largest_step = maxf(largest_step, step)
			if step > 8.0:
				switches += 1
			previous = menu.position
		check(menu.visible and switches <= 1, "small camera reversals settle without repeated flips at %s (%d switches, largest step %.1f px)" % [edge, switches, largest_step])
	# Reflow is still available when a full pan makes the old side unsuitable.
	game.select_building(null)
	place_camera(Vector2.ZERO)
	game.select_building(home)
	var anchor: Vector2 = game.camera.unproject_position(home.global_position)
	check(menu.get_rect().end.x < anchor.x, "centered fixture uses the clear left side")
	place_camera(Vector2(29, 0))
	anchor = game.camera.unproject_position(home.global_position)
	check(menu.position.x > anchor.x and Rect2(Vector2.ZERO, game.hud.get_node("UI").size).encloses(menu.get_rect()), "large pan can reflow to the right and keeps every action on screen")
	# A button under the pointer must not escape to another placement slot.
	game.select_building(null)
	place_camera(Vector2(28, -12.6))
	game.select_building(home)
	pointer(menu.get_global_rect().get_center())
	var before := menu.position
	place_camera(Vector2(28, -12.4))
	check(menu.position.distance_to(before) < 5.0, "hovering actions keeps the same slot across a placement boundary")
	pointer(Vector2(1500, 850))
	# Cancel a keyboard-highlighted Exit, then reopen using actual Esc events.
	key(KEY_ESCAPE)
	game.hud.get_node("%PauseExit").grab_focus()
	key(KEY_ESCAPE)
	key(KEY_ESCAPE)
	await frames()
	var resume: Button = game.hud.get_node("%Resume")
	check(game._local_menu and resume.has_focus() and not resume.has_focus(true), "Esc reopens with a hidden Continue focus instead of remembered Exit")
	key(KEY_DOWN)
	await frames()
	check(game.hud.get_node("%PauseHelp").has_focus(true), "arrow keys still expose and move native keyboard focus")
	for name: String in ["Resume", "PauseHelp", "PauseRestart", "PauseExit"]:
		var button: Button = game.hud.get_node("%" + name)
		for state: String in ["normal", "hover", "pressed"]:
			var background: StyleBoxFlat = button.get_theme_stylebox(state)
			check(contrast(button.get_theme_color("font_focus_color"), background.bg_color) >= 4.5, name + " focused text stays readable on " + state)
	key(KEY_F1)
	check(game.hud.help_visible() and game.hud.get_node("%HelpClose").has_focus(), "help moves keyboard focus into its own visible dialog")
	key(KEY_F1)
	check(not game.hud.help_visible() and game.hud.get_node("%PauseHelp").has_focus(), "closing help returns to its pause-menu entry")
	key(KEY_ESCAPE)
	key(KEY_ESCAPE)
	key(KEY_ENTER)
	await frames()
	check(not game._local_menu and current_scene == game, "Enter after reopening Esc continues the battle without exiting")
	# Ten seconds of perimeter motion may not modify native label geometry/text.
	place_camera(Vector2.ZERO)
	game.select_building(null)
	game.overlay.set_process(false)
	pointer(Vector2(800, 450))
	home.population = 64.0
	game.drag_source = home
	game.hovered = game.by_id[1]
	game.percentage = 75
	game._drag_start = Vector2.ZERO
	game.overlay._process(0.0)
	var label: Label = game.overlay.get_node("DispatchText")
	var original_rect := label.get_rect()
	var original_background_width: float = game.overlay._hint_rect.size.x
	var stable := true
	var valid_outline := true
	for sample: int in 200:
		game.overlay._process(0.05)
		stable = stable and label.get_rect() == original_rect and label.text == "48"
		var outline: PackedVector2Array = game.overlay._cloud_outline(game.overlay._hint_rect)
		valid_outline = valid_outline and Geometry2D.triangulate_polygon(outline).size() == (outline.size() - 2) * 3
		for point: Vector2 in outline:
			valid_outline = valid_outline and game.overlay._hint_rect.has_point(point)
	check(stable, "ten seconds of edge flow leave every label coordinate and glyph unchanged")
	check(valid_outline, "the moving cloud stays well formed and within its reserved screen bounds")
	check(label.get_theme_font("font") == home.get_node("PopulationLabel").font, "dispatch count uses the same numeric font as building population")
	game.hovered = home
	home.population = 1234.0
	game.percentage = 50
	game.overlay._process(0.0)
	check(label.text == "617" and game.overlay._hint_rect.size.x > original_background_width, "reinforcement shows only the dispatched count and expands for extra digits")
	game._cancel_drag()
	game.overlay._process(0.0)
	check(not label.visible, "cancelling dispatch hides the separately drawn text too")
	await game.prepare_shutdown()
	print("BLOCK_WAR_UI_STABILITY checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
