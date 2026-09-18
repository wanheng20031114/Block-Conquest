extends SceneTree
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures.append(text); printerr("FAIL ",text)
func frames(count: int = 3) -> void:
	for index: int in count: await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	var release: InputEventKey = event.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
func button(at: Vector2, pressed: bool, code: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
func drag(at: Vector2, to: Vector2) -> void:
	button(at,true)
	await frames()
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to-at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames()
func run() -> void:
	create_timer(60,true,false,true).timeout.connect(func():quit(3))
	root.size = Vector2i(1600,900)
	change_scene_to_file("res://scenes/moba/test1.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.edge_scroll = false
	var card: Control = game.hud.cards[0]
	var origin: Vector2 = card.get_global_rect().get_center()
	var destination := Vector2(800,350)
	await drag(origin,destination)
	check(root.gui_is_dragging() and game.hud.get_node("%DropHint").visible,"native card dragging activates battlefield drop target")
	check(game.players[0].gold == 240,"dragging alone never spends gold")
	button(destination,true,MOUSE_BUTTON_RIGHT)
	await frames()
	check(not root.gui_is_dragging() and not game.hud.get_node("%DropHint").visible,"right click cancels native drag and preview")
	check(game.players[0].gold == 240 and game.card_plays[0] == 0,"cancel leaves economy and card intact")
	button(destination,false)
	button(destination,false,MOUSE_BUTTON_RIGHT)
	await drag(origin,destination)
	button(destination,false)
	await frames()
	check(game.players[0].gold == 120 and game.card_plays[0] == 1,"native drop submits one army purchase")
	check(not root.gui_is_dragging() and not game.hud.get_node("%DropHint").visible,"successful drop releases drag state")
	button(destination,true,MOUSE_BUTTON_RIGHT)
	button(destination,false,MOUSE_BUTTON_RIGHT)
	await frames()
	check(game.local_hero().order == BattleUnit.Order.MOVE,"world right click passes through idle drop surface")
	key(KEY_F5)
	await frames()
	check(game.hero_controller.first_person,"actual F5 event enters first person once")
	game.local_hero().hp = 80
	key(KEY_E)
	key(KEY_R)
	await frames()
	check(game.local_hero().recovery_ticks == 5 and game.local_hero().morale_cooldown > 24,"actual E/R events cast independent skills")
	check(game.local_hero().weapon.reload_remaining == 0,"R never reloads in test1")
	key(KEY_ESCAPE)
	await frames()
	check(not game.running and game.hud.help_visible() and not game.hero_controller.captured,"Escape pauses simulation and frees mouse")
	var clock: float = game.elapsed
	key(KEY_E)
	await frames(10)
	check(game.elapsed == clock,"pause blocks gameplay input")
	game.hud.get_node("%Settings").pressed.emit()
	await frames()
	check(game.settings.is_open() and not game.running,"settings can open while paused")
	game.settings.close_menu()
	check(not game.running and game.hud.help_visible(),"closing settings returns to pause without resuming")
	game.hud.get_node("%Resume").pressed.emit()
	check(game.running and game.hero_controller.first_person,"resume retains perspective")
	key(KEY_F5)
	await frames()
	check(not game.hero_controller.first_person,"actual F5 returns to RTS")
	for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]:
		root.size = resolution
		await frames()
		var map_panel: Control = game.hud.get_node("%MapPanel")
		var hero_panel: Control = game.hud.get_node("%HeroPanel")
		check(not map_panel.get_global_rect().intersects(game.hud.cards[0].get_global_rect()),"minimap and cards do not overlap %s"%resolution)
		check(not hero_panel.get_global_rect().intersects(game.hud.cards[4].get_global_rect()),"hero and cards do not overlap %s"%resolution)
		check(root.get_visible_rect().encloses(hero_panel.get_global_rect()),"hero panel remains on screen %s"%resolution)
	game.restart()
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	check(game.elapsed < 1 and game.players[0].gold == 240 and game.army_counts[0] == 0,"restart creates a fresh match without old entities")
	game.return_to_menu()
	await scene_changed
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn" and get_nodes_in_group("entities").is_empty(),"return-to-menu releases all battle entities")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"menu regains the mouse")
	current_scene.queue_free()
	await create_timer(1).timeout
	print("MOBA_UI ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
