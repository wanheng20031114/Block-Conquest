extends SceneTree
## Real input regression for map picking, ownership, dispatch amounts and HUD overlap.

var game: Node3D
var failures: Array[String] = []
var checks := 0
var previous_time_scale := 1.0


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)


func frames(count: int = 2) -> void:
	for frame: int in count:
		await process_frame


func motion(at: Vector2, held: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.relative = at - root.get_mouse_position()
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func button(at: Vector2, down: bool, which: int = MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = which
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down and which == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.window_id = root.get_window_id()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func point(building: Node3D, badge: bool = false) -> Vector2:
	var world: Vector3 = building.get_node("PopulationBadge").global_position if badge else building.global_position + Vector3(0, 1.5, 0)
	return game.camera.unproject_position(world)


func drag_case(source: Node3D, target: Node3D, badge: bool, target_badge: bool = false) -> void:
	source.population = 80.0
	source.refresh_visual()
	key(KEY_2)
	await frames()
	var start := point(source, badge)
	var finish := point(target, target_badge)
	var label := "kind=%d target=%d start=%s finish=%s" % [source.kind, target.faction, "badge" if badge else "body", "badge" if target_badge else "body"]
	check(root.get_visible_rect().has_point(start) and root.get_visible_rect().has_point(finish), label + " has visible screen points")
	motion(start)
	await frames()
	check(not game.hud.is_pointer_blocked(start), label + " map source is not intercepted by decorative HUD")
	check(game.pick_building(start) == source, label + " source native pick")
	button(start, true)
	check(game.drag_source == source, label + " starts allied dispatch")
	motion(finish, true)
	await frames()
	check(not game.hud.is_pointer_blocked(finish), label + " map target is not intercepted by decorative HUD")
	if game.hovered != target or game.order_route.size() < 2:
		print("PREVIEW_DIAGNOSTIC target=", target.building_id, " hovered=", game.hovered.building_id if game.hovered else -999, " mouse=", root.get_mouse_position(), " expected=", finish, " route_points=", game.order_route.size())
	check(game.hovered == target and game.order_route.size() >= 2, label + " displays a route to the target")
	var before: int = game.marches.incoming_for(target.building_id, 0)
	button(finish, false)
	await frames()
	check(game.marches.incoming_for(target.building_id, 0) == before + 40 and is_equal_approx(source.population, 40.0), label + " sends exactly half the garrison")
	check(game.drag_source == null and game.order_route.is_empty(), label + " clears drag after release")
	check(game.map.get_building_route(source, target).size() >= 2, label + " repeated orders retain the cached route")


func _run() -> void:
	previous_time_scale = Engine.time_scale
	create_timer(45.0, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = previous_time_scale
		quit(3)
	)
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	await physics_frame
	# Finish initial native HUD reveal before freezing only simulation time.
	await create_timer(0.8).timeout
	Engine.time_scale = 0.0
	var home: Node3D = game.by_id[0]
	var enemy: Node3D = game.by_id[1]
	var neutral: Node3D = game.by_id[2]
	var sources: Array[Node3D] = [home, game.by_id[6], game.by_id[8]]
	for source: Node3D in sources:
		source.faction = 0
		source.population = 80.0
		source.refresh_visual()
	await frames()
	for source: Node3D in sources:
		for target: Node3D in [enemy, neutral]:
			for badge: bool in [false, true]:
				await drag_case(source, target, badge)
	await drag_case(home, enemy, false, true)
	# No player command can spend an enemy or neutral garrison.
	for hostile: Node3D in [enemy, neutral]:
		var initial: float = hostile.population
		motion(point(hostile))
		button(point(hostile), true)
		check(game.selected == hostile and game.drag_source == null, "hostile/neutral click selects information without starting dispatch")
		motion(point(home), true)
		button(point(home), false)
		check(hostile.population == initial, "hostile/neutral drag cannot spend another faction's population")
	# Every top-row and numpad shortcut is observable, and affects the next order.
	var codes: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4]
	for index: int in codes.size():
		home.population = 80.0
		home.refresh_visual()
		motion(point(home))
		button(point(home), true)
		check(game.drag_source == home, "percentage fixture starts from the allied garrison")
		key(codes[index])
		await frames()
		var ratio := (index % 4 + 1) * 25
		var amount := ratio * 80 / 100
		check(game.percentage == ratio, "shortcut %s selects %d percent" % [OS.get_keycode_string(codes[index]), ratio])
		var send_label: String = game.hud.get_node("%SendAmount").text
		check(send_label.contains(str(ratio)) and send_label.contains(str(amount)), "drag HUD exposes both %d percent and %d troops" % [ratio, amount])
		var ratio_button: Button = game.hud.get_node("UI/Percentages/Stack/P%d" % ratio)
		check(ratio_button.button_pressed, "selected percentage button matches keyboard shortcut")
		motion(point(neutral), true)
		await frames()
		var before: int = game.marches.incoming_for(neutral.building_id, 0)
		button(point(neutral), false)
		check(game.marches.incoming_for(neutral.building_id, 0) == before + amount, "shortcut dispatches %d actual troops" % amount)
	# A held gesture uses the most recently chosen ratio, not the press-time ratio.
	home.population = 80.0
	key(KEY_1)
	motion(point(home))
	button(point(home), true)
	motion(point(enemy), true)
	key(KEY_4)
	await frames()
	var before: int = game.marches.incoming_for(enemy.building_id, 0)
	button(point(enemy), false)
	check(game.marches.incoming_for(enemy.building_id, 0) == before + 80, "mid-drag 25 to 100 percent switch dispatches the final ratio")
	home.population = 80.0
	key(KEY_2)
	motion(point(home))
	button(point(home), true)
	var zoom_before: float = game.camera_rig.zoom_target
	for wheel: int in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		button(point(home), true, wheel)
		button(point(home), false, wheel)
	check(game.percentage == 75 and game.camera_rig.zoom_target == zoom_before, "drag wheel steps ratio and clamps at 100 without zooming")
	motion(point(neutral), true)
	before = game.marches.incoming_for(neutral.building_id, 0)
	button(point(neutral), false)
	check(game.marches.incoming_for(neutral.building_id, 0) == before + 60, "drag wheel ratio controls the dispatched amount")
	home.population = 80.0
	key(KEY_2)
	motion(point(home))
	button(point(home), true)
	for step: int in 4:
		button(point(home), true, MOUSE_BUTTON_WHEEL_DOWN)
		button(point(home), false, MOUSE_BUTTON_WHEEL_DOWN)
	check(game.percentage == 25 and game.camera_rig.zoom_target == zoom_before, "drag wheel clamps at 25 percent")
	button(point(home), false)
	# Release on an interactive UI control must cancel even without a preceding
	# motion event, so the old GUI hovered-control cache cannot decide this.
	home.population = 80.0
	motion(point(home))
	button(point(home), true)
	var percent_button: Button = game.hud.get_node("UI/Percentages/Stack/P25")
	var percent_screen := percent_button.get_global_rect().get_center()
	var total_before: int = game.marches.total_for(0)
	button(percent_screen, false)
	check(game.marches.total_for(0) == total_before and home.population == 80.0 and game.drag_source == null, "release directly over percentage UI cancels map dispatch")
	motion(percent_screen)
	button(percent_screen, true)
	button(percent_screen, false)
	check(game.percentage == 25 and game.marches.total_for(0) == total_before, "real percentage button click changes ratio without map orders")
	# The opposite transition must also use the release coordinates: the last
	# hovered control may still be a button after a rapid UI-to-map release.
	home.population = 80.0
	key(KEY_2)
	motion(point(home))
	button(point(home), true)
	motion(percent_screen, true)
	await frames()
	before = game.marches.incoming_for(enemy.building_id, 0)
	button(point(enemy), false)
	check(game.marches.incoming_for(enemy.building_id, 0) == before + 40, "map release after hovering UI uses the release position and sends troops")
	# Put a real neutral pick area behind Skill0. GUI protection must reject the
	# underlying building, not merely succeed because no building was underneath.
	var covered: Node3D = game.by_id[12]
	var skill: Button = game.hud.get_node("UI/Skills/Row/Skill0")
	var ui_screen := skill.get_global_rect().get_center()
	var delta := point(covered) - ui_screen
	var units_per_pixel: float = game.camera.size / root.get_visible_rect().size.y
	game.camera_rig.position += Vector3(delta.x * units_per_pixel, 0, delta.y * units_per_pixel / absf(sin(game.camera.rotation.x)))
	game.camera_rig.destination = game.camera_rig.position
	await frames()
	check(point(covered).distance_to(ui_screen) < 1.0 and game.pick_building(ui_screen) == covered, "UI overlap fixture contains a real underlying building")
	motion(point(home))
	button(point(home), true)
	check(game.drag_source == home, "UI overlap fixture can begin an allied drag")
	before = game.marches.incoming_for(covered.building_id, 0)
	button(ui_screen, false)
	check(game.marches.incoming_for(covered.building_id, 0) == before and game.drag_source == null, "interactive HUD blocks dispatch to the building directly behind it")
	Engine.time_scale = previous_time_scale
	await game.prepare_shutdown()
	print("BLOCK_WAR_DISPATCH_INPUT_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
