extends SceneTree
## The standalone settings draft, native mixer, persistence and display rollback.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func key(code: int, shift: bool = false) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		event.shift_pressed = shift
		root.push_input(event, true)

func _run() -> void:
	create_timer(25.0, true, false, true).timeout.connect(func(): quit(3))
	var settings: GameSettings = root.get_node("Session/Settings")
	var original := settings.snapshot()
	settings.settings_path = "res://.local/settings-test-%d.cfg" % OS.get_process_id()
	settings._apply_values(settings.defaults(), false)
	var bgm_bus := AudioServer.get_bus_index(&"BGM")
	check(settings.music_enabled and settings.music_volume_percent == 50.0 and not AudioServer.is_bus_mute(bgm_bus), "music defaults to enabled at 50 percent")
	for action: String in GameSettings.PAN_ACTIONS:
		check(InputMap.has_action(action), "native camera action exists: " + action)
		var event := InputEventKey.new()
		event.physical_keycode = GameSettings.PAN_ACTIONS[action]
		check(InputMap.event_is_action(event, action), "arrow key resolves its camera action: " + action)
	check(not settings.snapshot().has("bindings") and not settings.snapshot().has("fp_sensitivity"), "standalone preferences contain no unrelated controls")
	settings.open_menu()
	check(settings.is_open() and not paused, "opening settings preserves gameplay pause state")
	check(settings.menu.get_node("%Categories").get_child_count() == 4, "settings contain exactly four relevant categories")
	check(not settings.menu.has_node("%Categories/FirstPerson") and not settings.menu.has_node("%HotkeyRows"), "first-person and RTS binding controls are absent")
	settings.menu.show_page("Hotkeys")
	var reference: Control = settings.menu.get_node("%Pages/Hotkeys")
	check(reference.get_node("Row1/Key").text.contains("Q / W / E / R"), "skill reference follows the battle key contract")
	check(reference.get_node("Row5/Key").text == "Esc" and reference.get_node("Row6/Key").text == "F1", "pause and help reference follows the battle key contract")
	check(reference.get_node("Row7/Key").text == "Space", "focus reference follows the battle key contract")
	settings.menu.show_page("Audio")
	settings.menu.get_node("%Volume").value = 43
	settings.menu.get_node("%MusicVolume").value = 31
	settings.menu.get_node("%MusicEnabled").button_pressed = false
	check(settings.volume_percent == 50.0 and settings.music_enabled, "controls edit only the draft before Apply")
	settings.menu.draft.muted = true
	settings.menu.draft.camera_speed = 1.65
	settings.menu.draft.zoom_speed = 0.75
	settings.menu.draft.edge_scroll_enabled = false
	settings.menu.draft.fps_limit = 90
	settings.menu._apply(false)
	check(Engine.max_fps == 90, "frame cap reaches the native engine")
	check(AudioServer.is_bus_mute(0) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.43), "master volume and mute reach the real mixer")
	check(not settings.music_enabled and AudioServer.is_bus_mute(bgm_bus) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bgm_bus)), 0.31), "music preferences reach the independent bus")
	check(not settings.edge_scroll_enabled and is_equal_approx(settings.camera_speed, 1.65), "camera preferences are applied")
	var saved := ConfigFile.new()
	check(saved.load(settings.settings_path) == OK and saved.get_value("settings", "fps_limit") == 90, "native settings persist")
	check(not saved.has_section("hotkeys") and not saved.has_section_key("settings", "fp_sensitivity"), "saved settings contain only this product's values")
	var restored: GameSettings = load("res://scenes/settings_menu.tscn").instantiate()
	restored.settings_path = settings.settings_path
	root.add_child(restored)
	check(restored.muted and restored.fps_limit == 90 and restored.music_volume_percent == 31.0, "a fresh settings scene restores the saved preferences")
	restored.queue_free()
	await process_frame
	var before := settings.snapshot()
	var candidate := before.duplicate(true)
	candidate.resolution = Vector2i(1280, 720)
	candidate.volume_percent = 10.0
	candidate.music_enabled = true
	candidate.music_volume_percent = 75.0
	settings.menu.get_node("%Apply").grab_focus()
	settings.apply_preferences(candidate)
	check(not settings.display_timer.is_stopped() and settings.display_timer.wait_time == 15, "display changes start a 15-second confirmation")
	check(settings.menu.get_node("%DisplayConfirm").visible, "display confirmation owns the modal")
	for reverse: bool in [false, true]:
		var confined := true
		for _step: int in 8:
			key(KEY_TAB, reverse)
			confined = confined and root.gui_get_focus_owner() in [settings.menu.get_node("%KeepDisplay"), settings.menu.get_node("%RevertDisplay")]
		check(confined, "display confirmation traps native " + ("Shift Tab" if reverse else "Tab"))
	paused = true
	settings.display_timer.start(0.05)
	await create_timer(0.12, true, false, true).timeout
	check(settings.snapshot() == before, "timeout restores all previous preference values together")
	check(root.gui_get_focus_owner() == settings.menu.get_node("%Apply"), "display rollback restores focus to the original settings action")
	check(AudioServer.is_bus_mute(bgm_bus) and paused, "rollback preserves the old mixer and gameplay pause")
	paused = false
	settings.apply_preferences(candidate)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	settings.menu._input(escape)
	check(settings.is_open() and settings.snapshot() == before, "Esc first reverts an unconfirmed display change")
	settings.apply_preferences(candidate)
	settings.confirm_display()
	check(settings.resolution == Vector2i(1280, 720) and settings.display_timer.is_stopped(), "confirmation keeps the selected display settings")
	settings.menu.draft.camera_speed = 2.8
	settings.menu.get_node("%MusicVolume").value = 5
	settings.menu._input(escape)
	check(not settings.is_open() and settings.camera_speed == before.camera_speed and settings.music_volume_percent == 75.0, "Esc discards unapplied changes")
	settings.open_menu()
	settings.menu._restore_defaults()
	check(settings.menu.draft == settings.defaults(), "Restore Defaults changes only the complete draft")
	check(settings.music_volume_percent == 75.0, "Restore Defaults does not apply prematurely")
	settings.close_menu()
	var sanitized := settings._sanitize({"camera_speed": NAN, "zoom_speed": 999, "music_volume_percent": INF, "volume_percent": -1, "fp_fov": 110, "bindings": {}})
	check(sanitized.camera_speed == 1.0 and sanitized.zoom_speed == 3.0 and sanitized.music_volume_percent == 50.0 and sanitized.volume_percent == 0.0, "non-finite and out-of-range preferences cannot corrupt camera or mixer")
	check(not sanitized.has("fp_fov") and not sanitized.has("bindings"), "legacy unrelated keys are discarded")
	var silent := settings.snapshot()
	silent.music_volume_percent = 0.0
	settings.apply_preferences(silent)
	check(settings.music_enabled and AudioServer.is_bus_mute(bgm_bus), "zero music volume is silent without clearing the preference")
	settings._apply_values(original, false)
	root.get_node("Session/UIFeedback").stop_all()
	await create_timer(0.12, true, false, true).timeout
	check(DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.settings_path)) == OK, "isolated settings fixture is removed")
	print("SETTINGS_RESULT ", checks, " checks / ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
