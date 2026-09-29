extends SceneTree
## Private desktop only: native menu states, no saved preferences or battle input.
var output: String
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func capture(label: String) -> void:
	for frame: int in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, label)
	print("PALETTE_CAPTURE ", label)

func hover(control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion, true)

func contrast(ink: Color, paper: Color) -> float:
	var a := ink.srgb_to_linear()
	var b := paper.srgb_to_linear()
	var x := a.r * 0.2126 + a.g * 0.7152 + a.b * 0.0722
	var y := b.r * 0.2126 + b.g * 0.7152 + b.b * 0.0722
	return (maxf(x, y) + 0.05) / (minf(x, y) + 0.05)

func check_button_text(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var color_name := "font_color" if state == "normal" else "font_" + state + "_color"
		var paper: StyleBoxFlat = button.get_theme_stylebox(state)
		var ratio := contrast(button.get_theme_color(color_name), paper.bg_color)
		check(ratio >= 4.5, "%s/%s text contrast %.2f" % [button.name, state, ratio])

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	var session := root.get_node("Session")
	var settings: GameSettings = session.settings
	var original := settings.snapshot()
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	if OS.get_cmdline_user_args().has("--baseline"):
		settings.open_menu()
		settings.menu.refresh(settings.defaults())
		settings.menu.show_page("Audio")
		await capture("audio_before")
		settings.close_menu()
		quit()
		return
	await capture("01_lobby")
	session.block_war_commander = &"squirrel"
	change_scene_to_file("res://scenes/block_war/commander_select.tscn")
	await scene_changed
	await capture("02_commander")
	check_button_text(current_scene.get_node("%Next"))
	check_button_text(current_scene.get_node("%Back"))
	check_button_text(current_scene.get_node("%Animal0"))
	check(not current_scene.get_node("%Animal3").disabled and not current_scene.get_node("%Animal4").disabled, "pig and fox roster slots are available")
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	await capture("03_map")
	check_button_text(current_scene.get_node("%Map0"))
	check_button_text(current_scene.get_node("%Start"))
	settings.open_menu()
	var menu := settings.menu
	menu.refresh(settings.defaults())
	menu.show_page("Audio")
	var sound: Button = menu.get_node("%Mute")
	var music: Button = menu.get_node("%MusicEnabled")
	check(sound.button_pressed and music.button_pressed, "both enabled audio controls are selected")
	check(sound.text == "开启" and music.text == "开启", "enabled audio controls use matching labels")
	check_button_text(sound)
	check_button_text(menu.get_node("%Categories/Audio"))
	await capture("04_audio_on")
	sound.button_pressed = false
	music.button_pressed = false
	check(menu.draft.muted and not menu.draft.music_enabled, "off controls edit mute and music with correct polarity")
	check(sound.text == "关闭" and music.text == "关闭", "off labels match")
	await capture("05_audio_off")
	sound.button_pressed = true
	check(not menu.draft.muted, "enabling sound clears mute")
	await capture("06_audio_mixed")
	check(settings.snapshot() == original, "draft interaction does not apply preferences")
	menu.refresh(settings.defaults())
	hover(sound)
	await capture("07_audio_hover")
	check(sound.self_modulate.is_equal_approx(Color.WHITE), "hover keeps the authored menu palette")
	menu.get_node("%Apply").grab_focus()
	await capture("08_keyboard_focus")
	root.gui_release_focus()
	hover(menu.get_node("%Status"))
	menu.show_page("Graphics")
	await capture("09_graphics")
	var option: OptionButton = menu.get_node("%WindowMode")
	hover(option)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = option.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
	await capture("10_dropdown")
	option.get_popup().hide()
	hover(menu.get_node("%Status"))
	for page: String in ["Controls", "Hotkeys"]:
		menu.show_page(page)
		await capture("11_" + page.to_lower())
	root.size = Vector2i(1280, 720)
	menu.show_page("Audio")
	await capture("12_audio_720")
	settings.close_menu()
	settings.open_menu()
	check(menu.draft == original, "cancel and reopen restore the original preferences")
	settings.close_menu()
	await capture("13_map_720")
	print("MENU_PALETTE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
