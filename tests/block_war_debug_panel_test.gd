extends SceneTree
## Native input, data visibility and layout for the optional battle inspector.
## -- <output-directory> captures GPU frames; headless never waits for drawing.

const DATA := preload("res://scripts/block_war/war_debug_data.gd")
const COMBAT := preload("res://scripts/block_war/war_combat_rules.gd")
var game: Node3D
var panel: Control
var checks := 0
var failures: Array[String] = []
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL DEBUG_PANEL ", label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, label + " (%.5f / %.5f)" % [actual, expected])


func frames(count: int = 3) -> void:
	for index: int in count:
		await process_frame


func key(code: int, down: bool, echo: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.window_id = root.get_window_id()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	event.echo = echo
	event.shift_pressed = shift
	root.push_input(event, true)


func tap(code: int, shift: bool = false) -> void:
	key(code, true, false, shift)
	key(code, false, false, shift)


func motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.relative = relative
	root.push_input(event, true)


func mouse(at: Vector2, button: int, down: bool) -> void:
	motion(at)
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)


func screen_center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func clean() -> void:
	game.marches.clear()
	game.shields.clear()
	game.select_building(null)
	game.morale.configure(game.faction_count)
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.kind = 0
		building.level = 1
		building.faction = building.building_id if building.building_id < 6 else -1
		building.population = 60.0
		building.refresh_visual()
	game.update_hud()


func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await frames(5)
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)


func numeric_checks() -> void:
	for example: Array in [[0, 0.0, 0, 0, 0], [0, 0.9999, 0, 0, 0], [0, 5.0, 25, 100, 50], [1, 0.0, 30, 15, 0], [1, 4.9999, 50, 95, 40], [1, 5.0, 55, 115, 50], [2, 0.0, 50, 25, 0], [3, 0.0, 70, 35, 0], [4, 0.0, 80, 40, 0], [7, 5.0, 105, 140, 50]]:
		clean()
		for index: int in int(example[0]):
			game.by_id[6 + index].faction = game.local_faction
			game.by_id[6 + index].kind = 2
		game.morale.adjust(game.local_faction, WarMorale.points_for_stars(float(example[1])))
		var data: Dictionary = DATA.capture(game)
		var context := "forge %d / stars %s" % [example[0], example[1]]
		near(data.attack_multiplier, 1.0 + float(example[2]) / 100.0, context + " attack")
		near(data.defense_multiplier, 1.0 + float(example[3]) / 100.0, context + " defense")
		near(data.speed_multiplier, 1.0 + float(example[4]) / 100.0, context + " speed")
		near(data.move_speed, WarMarches.SPEED * data.speed_multiplier, context + " metres per second")
		near(data.forge_attack, COMBAT.forge_attack_bonus(int(example[0])), context + " forge attack source")
		near(data.forge_defense, COMBAT.forge_defense_bonus(int(example[0])), context + " forge defense source")
		near(data.morale_attack, floorf(float(example[1])) * 0.05, context + " morale attack source")
		near(data.morale_defense, floorf(float(example[1])) * 0.20, context + " morale defense source")
		near(data.morale_speed, floorf(float(example[1])) * 0.10, context + " morale is the sole permanent speed source")
		check(data.morale_level == floori(float(example[1])) and data.forges_active == int(example[0]), context + " complete level and active forge count")
		check(data.morale_next == (-1 if data.morale_level == 5 else WarMorale.THRESHOLDS[data.morale_level + 1]), context + " next threshold stops at maximum")
	clean()
	for kind: int in [1, 2, 3]:
		game.by_id[6 + kind].faction = game.local_faction
		game.by_id[6 + kind].kind = kind
	var active: Dictionary = DATA.capture(game)
	check(active.buildings == [1, 1, 1, 1] and active.forges_active == 1 and active.energy_towers_active == 1, "owned building kinds and active bonuses are distinct facts")
	game.by_id[8].disruption_remaining = 5.0
	game.by_id[9].disruption_remaining = 5.0
	var disabled: Dictionary = DATA.capture(game)
	check(disabled.buildings == [1, 1, 1, 1] and disabled.forges_active == 0 and disabled.energy_towers_active == 0, "disrupted buildings remain owned while their bonuses stop")
	near(disabled.energy_regen, game.ENERGY_REGEN, "disrupted energy tower no longer increases recovery")
	near(disabled.energy, game.energy, "local energy uses the real account")
	clean()
	game.local_faction = 5
	game.morale.adjust(0, 8000.0)
	game.morale.adjust(5, 2000.0)
	var own: Dictionary = DATA.capture(game)
	near(own.attack_multiplier, 1.15, "last-seat viewer ignores first-seat morale")
	near(own.speed_multiplier, 1.30, "last-seat viewer uses its own movement")
	game.local_faction = 0
	clean()


func population_checks() -> void:
	var home: WarBuilding = game.by_id[0]
	home.population = 80.0
	check(game.issue_order(home, game.by_id[6], 50) == 40, "fixture queues forty soldiers")
	var queued: Dictionary = DATA.capture(game)
	near(queued.garrison, 80.0, "queued soldiers remain in physical garrison")
	check(queued.queued == 40 and queued.marching == 0, "unpaid queue is not counted as departed army")
	near(queued.army_total, 80.0, "queue cannot duplicate the army total")
	game.marches.tick(0.25)
	var moving: Dictionary = DATA.capture(game)
	check(moving.marching > 0 and moving.queued < 40, "rank departures update both queue and field count")
	near(moving.garrison + moving.marching, 80.0, "real departures conserve physical soldiers")
	near(moving.army_total, 80.0, "total remains stable as a rank departs")
	game.select_building(home)
	var chosen: Dictionary = DATA.capture(game).selected
	check(chosen.population == home.population and chosen.available == home.available_population and chosen.queued == home.queued_population, "selected source explains physical available and reserved soldiers")
	clean()
	var observed: WarBuilding = game.by_id[6]
	observed.population = 73.75
	observed.queued_population = 11
	for viewer: int in [0, 1, 5]:
		game.local_faction = viewer
		for owner: int in range(-1, 6):
			observed.faction = owner
			game.select_building(observed)
			var data: Dictionary = DATA.capture(game)
			var known: bool = owner < 0 or game.FACTIONS.allied(owner, viewer)
			var selected: Dictionary = data.selected
			check(selected.id == observed.building_id and selected.level == observed.level, "viewer %d / owner %d retains public identity" % [viewer, owner])
			check(selected.population == (73.75 if known else -1.0) and selected.available == (62.75 if known else -1.0) and selected.queued == (11 if known else -1), "viewer %d / owner %d enforces population knowledge" % [viewer, owner])
	game.local_faction = 0
	observed.faction = 1
	for population: float in [0.0, 9.0, 9999.0]:
		observed.population = population
		var hidden: Dictionary = DATA.capture(game).selected
		check(hidden.population == -1 and hidden.available == -1 and hidden.queued == -1, "enemy population %s cannot leak through the inspector" % population)
	observed.queued_population = 0
	game.select_building(null)
	check(DATA.capture(game).selected.is_empty(), "deselecting clears previous building information")
	clean()


func input_checks() -> void:
	check(InputMap.has_action("debug") and InputMap.action_get_events("debug").any(func(event: InputEvent): return event is InputEventKey and event.physical_keycode == KEY_F4), "debug is a native project action bound to physical F4")
	check(not game.hud.debug_visible() and not panel.visible, "inspector is hidden at match startup")
	check(not game.hud.has_node("UI/Player/ForgeBonus") and not game.hud.has_node("UI/QuickHint"), "both obsolete HUD text regions are absent")
	var timer: Timer = game.hud.get_node("%DebugRefresh")
	near(timer.wait_time, 0.25, "data refresh uses the authored quarter-second timer")
	game.energy = 100.0
	game.request_skill(0, true)
	check(game.armed_skill == 0, "fixture starts a real unspent skill gesture")
	game.drag_source = game.by_id[0]
	game.camera_rig.dragging = true
	var energy_before: float = game.energy
	key(KEY_F4, true)
	check(game.hud.debug_visible() and not game._local_menu, "F4 opens a local non-pausing inspector")
	check(game.armed_skill == -1 and game.drag_source == null and not game.camera_rig.dragging and game.energy == energy_before, "opening cancels all unfinished gestures without spending energy")
	key(KEY_F4, true, true)
	key(KEY_F4, false)
	check(game.hud.debug_visible(), "key echo and release do not toggle the inspector")
	tap(KEY_F4)
	check(not game.hud.debug_visible(), "second physical press closes the inspector")
	var events := InputMap.action_get_events("debug")
	InputMap.action_erase_events("debug")
	var alternate := InputEventKey.new()
	alternate.physical_keycode = KEY_F8
	InputMap.action_add_event("debug", alternate)
	tap(KEY_F4)
	check(not game.hud.debug_visible(), "unbound F4 is inert")
	tap(KEY_F8)
	check(game.hud.debug_visible(), "remapped F8 drives the same native action")
	check(panel.get_node("%Close").text.contains("F8"), "remapping also updates the visible close shortcut")
	tap(KEY_F8)
	InputMap.action_erase_events("debug")
	for event: InputEvent in events:
		InputMap.action_add_event("debug", event)
	tap(KEY_F4)
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and not game._local_menu, "Esc closes debug before opening the local pause menu")
	game.set_paused(true)
	tap(KEY_F4)
	check(game.hud.debug_visible() and game._local_menu, "F4 is available over the local pause menu")
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and game._local_menu, "Esc closes debug while preserving local pause")
	game.set_paused(false)
	game.match_paused = true
	game.update_hud()
	tap(KEY_F4)
	check(game.hud.debug_visible() and game.match_paused, "global pause permits inspection without altering authority")
	tap(KEY_F4)
	game.match_paused = false
	game.update_hud()
	tap(KEY_F4)
	await frames()
	var obscured_close := screen_center(panel.get_node("%Close"))
	tap(KEY_F1)
	await create_timer(0.25).timeout
	var help_close: Button = game.hud.get_node("%HelpClose")
	check(game.hud.help_visible() and game.hud.debug_visible() and help_close.has_focus(), "help opens above an already visible inspector and takes focus")
	for reverse: bool in [false, true]:
		var confined := true
		for step: int in 8:
			tap(KEY_TAB, reverse)
			confined = confined and root.gui_get_focus_owner() == help_close
		check(confined, "help keeps " + ("Shift Tab" if reverse else "Tab") + " away from obscured inspector controls")
	for direction: int in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		tap(direction)
		check(root.gui_get_focus_owner() == help_close, "help owns directional focus " + OS.get_keycode_string(direction))
	mouse(obscured_close, MOUSE_BUTTON_LEFT, true)
	mouse(obscured_close, MOUSE_BUTTON_LEFT, false)
	check(game.hud.help_visible() and game.hud.debug_visible(), "clicking the obscured debug close position cannot close the lower panel")
	tap(KEY_F4)
	check(game.hud.help_visible() and game.hud.debug_visible(), "help ignores F4 while preserving the already open inspector")
	tap(KEY_ESCAPE)
	check(not game.hud.help_visible() and game.hud.debug_visible() and not game._local_menu, "first Esc closes help and restores the still-open inspector")
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and not game._local_menu, "second Esc closes restored debug without opening pause")
	var settings: GameSettings = root.get_node("Session/Settings")
	tap(KEY_F4)
	settings.open_menu()
	tap(KEY_F4)
	check(settings.is_open() and game.hud.debug_visible(), "settings ignores F4 while preserving the already open inspector")
	tap(KEY_ESCAPE)
	check(not settings.is_open() and game.hud.debug_visible() and not game._local_menu, "settings owns the first Esc and leaves debug open")
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and not game._local_menu, "next Esc closes debug after settings without pausing")
	tap(KEY_F4)
	game.hud._show_online_confirm("leave", "确认离开？", "测试确认窗口", "确认离开")
	tap(KEY_F4)
	check(game.hud.get_node("%OnlineConfirm").visible and game.hud.debug_visible(), "online confirmation ignores F4 while preserving the already open inspector")
	tap(KEY_ESCAPE)
	check(not game.hud.get_node("%OnlineConfirm").visible and game.hud.debug_visible(), "confirmation owns the first Esc and leaves debug open")
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and not game._local_menu, "next Esc closes debug after confirmation without pausing")
	game.set_paused(false)


func pointer_and_layout_checks() -> void:
	game.hud.toggle_debug_panel()
	await frames()
	game.morale.adjust(0, 500.0)
	await create_timer(0.32).timeout
	check(panel.get_node("%AttackValue").text == "105%" and panel.get_node("%SpeedValue").text == "110%", "authored timer refreshes changed battle values without reopening")
	var centre := screen_center(panel)
	check(game.hud.is_pointer_blocked(centre) and game.hud.is_pointer_over_hud(centre), "panel blocks battlefield targeting and teammate pointer broadcasts")
	var selected_before: Node3D = game.selected
	var zoom_before: float = game.camera_rig.zoom_target
	for button: int in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		mouse(centre, button, true)
		mouse(centre, button, false)
	check(game.selected == selected_before and game.drag_source == null and not game.camera_rig.dragging and is_equal_approx(game.camera_rig.zoom_target, zoom_before), "panel clicks middle button and scroll never reach the battlefield")
	var outside := Vector2(800, 400)
	check(not game.hud.is_pointer_blocked(outside), "uncovered battlefield remains interactive")
	mouse(outside, MOUSE_BUTTON_MIDDLE, true)
	motion(outside + Vector2(20, 10), Vector2(20, 10))
	check(game.camera_rig.dragging, "fresh middle drag outside the panel works")
	mouse(outside, MOUSE_BUTTON_MIDDLE, false)
	check(not game.camera_rig.dragging, "middle release does not latch after inspecting data")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2560, 1080)]:
		root.size = resolution
		await frames(5)
		game.by_id[0].population = 99999.75
		game.morale.adjust(0, 8000.0)
		game.select_building(game.by_id[0])
		panel.update_data(DATA.capture(game))
		await frames()
		check(Rect2(Vector2.ZERO, game.hud.get_node("UI").size).encloses(panel.get_global_rect()), "panel fits logical viewport at " + str(resolution))
		for value_name: String in ["AttackValue", "DefenseValue", "SpeedValue"]:
			var value: Label = panel.get_node("%" + value_name)
			check(panel.get_global_rect().encloses(value.get_global_rect()), value_name + " stays within panel at " + str(resolution))
		await capture("debug_%dx%d" % [resolution.x, resolution.y])
		var scroll: ScrollContainer = panel.get_node("%Scroll")
		scroll.scroll_vertical = 100000
		await frames()
		var final_detail: Label = panel.get_node("%PerformanceValue")
		check(scroll.get_global_rect().intersects(final_detail.get_global_rect()), "scroll reaches the final data section at " + str(resolution))
		if resolution == Vector2i(960, 540):
			await capture("debug_960x540_scrolled")
		scroll.scroll_vertical = 0
	root.size = Vector2i(1600, 900)
	await frames()
	var close_at := screen_center(panel.get_node("%Close"))
	mouse(close_at, MOUSE_BUTTON_LEFT, true)
	mouse(close_at, MOUSE_BUTTON_LEFT, false)
	check(not game.hud.debug_visible(), "native close button dismisses the inspector")
	check(not game.hud.is_pointer_blocked(screen_center(panel)), "hidden panel leaves no invisible input shield")
	game._finish_match(game.local_team)
	tap(KEY_F4)
	check(game.hud.debug_visible() and game.finished, "completed match remains inspectable")
	tap(KEY_ESCAPE)
	check(not game.hud.debug_visible() and game.finished and game.hud.get_node("%ResultOverlay").visible, "Esc closes final inspection without disturbing results")


func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
		DirAccess.make_dir_recursive_absolute(output)
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	panel = game.hud.get_node("%DebugPanel")
	await frames(8)
	numeric_checks()
	population_checks()
	await input_checks()
	await pointer_and_layout_checks()
	await game.prepare_shutdown()
	print("BLOCK_WAR_DEBUG_PANEL_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
