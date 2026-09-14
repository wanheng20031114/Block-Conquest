extends SceneTree
## Authored combat sheets at common client sizes, with real UI input and GPU captures.
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks: int = 0
var failures: Array[String] = []
var visual: bool = false
var game: Node3D

func _initialize() -> void:
	visual = DisplayServer.get_name() != "headless"
	if visual:
		root.visible = false
		root.unfocusable = true
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func settle() -> void:
	await create_timer(0.45, true, false, true).timeout

func shot(label: String) -> void:
	if visual:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/medieval_combat/" + label + ".png") == OK, "capture " + label)

func panel_bounds(panel: Control, label: String) -> void:
	if not root.get_visible_rect().encloses(panel.get_global_rect()):
		print("PANEL_BOUNDS ", label, " panel=", panel.get_global_rect(), " viewport=", root.get_visible_rect(), " minimum=", panel.get_combined_minimum_size())
	check(root.get_visible_rect().encloses(panel.get_global_rect()), label + " stays within screen")
	for item: Node in panel.find_children("*", "Button", true, false):
		var button: Button = item
		if not button.is_visible_in_tree():
			continue
		check(panel.get_global_rect().encloses(button.get_global_rect()), label + "/" + str(button.name) + " remains inside panel")

func click(button: BaseButton) -> void:
	var at: Vector2 = button.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		root.push_input(event, true)
		await process_frame

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute("res://artifacts/medieval_combat")
	var session: Node = root.get_node("Session")
	session.start_offline("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready:
		await process_frame
	if session.transition.busy:
		await session.transition.completed
	game.tests_running = true
	game.bots.clear()
	game.set_physics_process(false)
	game.camera_rig.edge_scroll = false
	game.get_node("Audio").set_volume_percent(0)
	game.get_node("IncomeTimer").stop()
	game.get_node("EnemyTimer").stop()
	for size_pixels: Vector2i in SIZES:
		root.size = size_pixels
		await settle()
		panel_bounds(game.hud.get_node("CommandBar"), "commands %d" % size_pixels.x)
		check(game.hud.get_node("CommandBar").size.y <= 158.0, "battle command bar keeps original height")
		check(game.hud.get_node("%Minimap").size == Vector2(174, 160), "minimap keeps its original useful map area")
		await shot("battle_%d" % size_pixels.x)
		await click(game.hud.get_node("%PauseButton"))
		await settle()
		check(paused, "native pause input pauses simulation")
		panel_bounds(game.hud.get_node("PauseOverlay/Paper"), "pause %d" % size_pixels.x)
		await shot("battle_pause_%d" % size_pixels.x)
		await click(game.hud.get_node("%ResumeButton"))
		check(not paused, "native resume remains usable during paused tree")
	game.hud.toggle_help()
	await settle()
	panel_bounds(game.hud.get_node("HelpOverlay/Paper"), "field manual")
	await shot("battle_manual")
	game.hud.toggle_help()
	game.hud.show_result(true, 82.0, 17)
	await settle()
	panel_bounds(game.hud.get_node("ResultOverlay/Paper"), "battle result")
	await shot("battle_result")
	await game.prepare_shutdown()
	change_scene_to_file("res://scenes/unit_codex.tscn")
	await scene_changed
	var codex: Control = current_scene
	codex.open_codex()
	for size_pixels: Vector2i in SIZES:
		root.size = size_pixels
		codex.select_entry(0, "heavy_cannon")
		await settle()
		panel_bounds(codex, "codex %d" % size_pixels.x)
		var stats: RichTextLabel = codex.get_node("%Stats")
		check(stats.get_parsed_text().contains("人口"), "parchment statistics retain gameplay data")
		await shot("codex_%d" % size_pixels.x)
	codex.close_codex()
	check(not codex.visible and codex.get_node("%CodexViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "codex close still stops viewport work")
	session.start_sandbox("1v1")
	await scene_changed
	game = current_scene
	while not game._match_ready:
		await process_frame
	game.camera_rig.edge_scroll = false
	for size_pixels: Vector2i in SIZES:
		root.size = size_pixels
		await settle()
		panel_bounds(game.hud.get_node("Top"), "sandbox header %d" % size_pixels.x)
		check(game.hud.get_node("Sidebar").size.x <= 278.0, "sandbox sidebar keeps original battlefield width")
		await shot("sandbox_%d" % size_pixels.x)
	await game.prepare_shutdown()
	session.rogue.state = RogueRunState.new()
	session.rogue.state.start_new("ranged", "steady", 24681)
	session.rogue.state.data.phase = "battle"
	session.rogue.state.data.battle_kind = "outpost"
	change_scene_to_file("res://scenes/rogue/battle.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready:
		await process_frame
	game.camera_rig.edge_scroll = false
	await settle()
	panel_bounds(game.hud.get_node("%IntroPanel"), "outpost briefing")
	await shot("rogue_intro")
	game.skip_intro()
	for size_pixels: Vector2i in SIZES:
		root.size = size_pixels
		await settle()
		panel_bounds(game.hud.get_node("%Objectives"), "rogue objectives %d" % size_pixels.x)
		panel_bounds(game.hud.get_node("%Commands"), "rogue commands %d" % size_pixels.x)
		await shot("rogue_battle_%d" % size_pixels.x)
	game.handle_pause_action()
	await settle()
	panel_bounds(game.hud.get_node("%PausePanel"), "rogue pause")
	await shot("rogue_pause")
	game.handle_pause_action()
	game.hud.show_result(true, 93.0, 16)
	await settle()
	panel_bounds(game.hud.get_node("%ResultPanel"), "rogue result")
	await shot("rogue_result")
	await game.prepare_shutdown()
	print("MEDIEVAL_COMBAT_UI ", checks - failures.size(), "/", checks, " passed; failures=", failures)
	quit(0 if failures.is_empty() else 1)
