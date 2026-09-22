extends SceneTree
## Exercise native GUI event routing and scene transitions, not direct order calls.

var game: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func frames(count: int = 3) -> void:
	for frame: int in count:
		await process_frame

func move_mouse(at: Vector2, relative: Vector2 = Vector2.ZERO, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = mask
	root.push_input(event, true)

func mouse(at: Vector2, button: int, down: bool) -> void:
	move_mouse(at)
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	root.push_input(event, true)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func run() -> void:
	var initial_taa: bool = root.use_taa
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	await frames(5)
	var button: Button = current_scene.get_node("%BlockWarMode")
	check(button.is_visible_in_tree(), "new mode is accessible from lobby")
	var at := button.get_global_rect().get_center()
	mouse(at, MOUSE_BUTTON_LEFT, true)
	mouse(at, MOUSE_BUTTON_LEFT, false)
	await scene_changed
	game = current_scene
	check(game.scene_file_path == "res://scenes/block_war/block_war.tscn", "native lobby click enters war mode")
	check(not root.use_taa, "war mode avoids temporal ghosting on population badges")
	while root.get_node("Session").transition.busy:
		await process_frame
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	game.set_process(false)
	await physics_frame
	await frames()
	var home: Node3D = game.by_id[0]
	var target: Node3D = game.by_id[2]
	var source_screen: Vector2 = game.camera.unproject_position(home.global_position + Vector3(0, 1.5, 0))
	var target_screen: Vector2 = game.camera.unproject_position(target.global_position + Vector3(0, 1.5, 0))
	check(game.pick_building(source_screen) == home and game.pick_building(target_screen) == target, "native 3D ray picks authored building areas")
	home.population = 60.0
	key(KEY_3)
	check(game.percentage == 75, "percentage shortcut routes through HUD")
	mouse(source_screen, MOUSE_BUTTON_LEFT, true)
	check(game.drag_source == home, "mouse press selects allied drag source")
	move_mouse(target_screen, target_screen - source_screen, MOUSE_BUTTON_MASK_LEFT)
	mouse(target_screen, MOUSE_BUTTON_LEFT, false)
	check(game.marches.incoming_for(target.building_id, 0) == 45 and home.population == 15.0, "dragging from building to building dispatches selected percentage")
	check(game.drag_source == null and game.order_route.is_empty(), "release clears drag preview")
	var percent_button: Button = game.hud.get_node("UI/Percentages/Stack/P25")
	var percent_screen := percent_button.get_global_rect().get_center()
	mouse(percent_screen, MOUSE_BUTTON_LEFT, true)
	mouse(percent_screen, MOUSE_BUTTON_LEFT, false)
	check(game.percentage == 25 and game.marches.incoming_for(target.building_id, 0) == 45, "HUD click changes percent without issuing a map order")
	key(KEY_R)
	check(game.armed_skill == 3, "hostile skill waits for a valid target")
	mouse(target_screen, MOUSE_BUTTON_LEFT, true)
	mouse(target_screen, MOUSE_BUTTON_LEFT, false)
	check(game.armed_skill == -1 and game.cooldowns[3] == 60.0 and target.population == 0.0, "armed skill targets native picked building")
	key(KEY_W)
	check(game.cooldowns[1] == 28.0 and game.active_durations[1] == 8.0, "keyboard haste casts independently")
	var previous: Vector3 = game.camera_rig.destination
	var ground := Vector2(800, 470)
	mouse(ground, MOUSE_BUTTON_MIDDLE, true)
	move_mouse(ground + Vector2(60, 25), Vector2(60, 25), MOUSE_BUTTON_MASK_MIDDLE)
	mouse(ground + Vector2(60, 25), MOUSE_BUTTON_MIDDLE, false)
	check(game.camera_rig.destination.distance_to(previous) > 0.1 and not game.camera_rig.dragging, "native middle-button input pans camera and releases")
	key(KEY_ESCAPE)
	check(game._local_menu and game.hud.get_node("%PauseOverlay").visible, "escape opens pause")
	key(KEY_ESCAPE)
	check(not game._local_menu, "escape resumes")
	key(KEY_F1)
	check(game._local_menu and game.hud.help_visible(), "F1 opens instructions and pauses simulation")
	key(KEY_F1)
	check(not game._local_menu and not game.hud.help_visible(), "closing help restores running state")
	game.restart()
	await scene_changed
	while root.get_node("Session").transition.busy:
		await process_frame
	game = current_scene
	game.ai_enabled = false
	check(game.by_id[0].population < 62.0 and game.marches.total_for(0) == 0 and game.cooldowns[3] == 0.0, "restart resets match and cooldown state")
	game.exit_to_lobby()
	await scene_changed
	while root.get_node("Session").transition.busy:
		await process_frame
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "return transitions to lobby")
	check(root.use_taa == initial_taa, "leaving war mode restores the previous viewport antialiasing")
	await frames(5)
	print("BLOCK_WAR_INPUT_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
