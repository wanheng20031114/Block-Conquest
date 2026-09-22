extends SceneTree
## Real mouse input through the selected-building panel; never calls upgrade directly.
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)

func frames(count: int = 2) -> void:
	for frame: int in count:
		await process_frame

func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.window_id = root.get_window_id()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await frames()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.window_id = root.get_window_id()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames()

func center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)

func point(building: Node3D) -> Vector2:
	return game.camera.unproject_position(building.global_position + Vector3(0, 1.5, 0))

func select_on_map(building: Node3D) -> void:
	await click(point(building))
	await create_timer(0.22).timeout
	check(game.selected == building and game.drag_source == null, "map click selects building %d without dispatch" % building.building_id)

func _run() -> void:
	create_timer(40.0).timeout.connect(func(): push_error("UPGRADE_INPUT deadline"); quit(3))
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.camera_rig.set_process(false)
	game.set_process(false)
	await physics_frame
	await create_timer(0.8).timeout
	var upgrade: Button = game.hud.get_node("%Upgrade")
	var hint: Label = game.hud.get_node("%UpgradeHint")
	var title: Label = game.hud.get_node("%SelectedName")
	var manage: Button = game.hud.get_node("%Manage")
	var home: Node3D = game.by_id[0]
	var sources: Array[Node3D] = [home, game.by_id[6], game.by_id[8]]
	for kind: int in sources.size():
		var building: Node3D = sources[kind]
		building.kind = kind
		building.faction = 0
		building.level = 1
		building.population = 120.0
		building.capacity = 200.0
		building.refresh_visual()
		await select_on_map(building)
		check(upgrade.is_visible_in_tree() and not upgrade.disabled and not manage.button_pressed, "kind %d exposes upgrade without opening management" % kind)
		check(upgrade.text.contains("2 级") and upgrade.text.contains("30 驻军"), "kind %d presents next level and 30-garrison cost" % kind)
		await click(center(upgrade))
		check(building.level == 2 and building.population == 90.0 and building.capacity == 300.0, "kind %d actual click upgrades 1 to 2 for exactly 30" % kind)
		check(title.text.contains("己方") and title.text.contains("2 / 3") and upgrade.text.contains("60 驻军"), "kind %d updates ownership, level and next cost" % kind)
		await click(center(upgrade))
		check(building.level == 3 and building.population == 30.0 and building.capacity == 400.0, "kind %d actual click upgrades 2 to 3 for exactly 60" % kind)
		check(upgrade.disabled and upgrade.text.contains("满级") and title.text.contains("3 / 3"), "kind %d visibly reaches its level cap" % kind)
		await click(center(upgrade))
		check(building.level == 3 and building.population == 30.0, "kind %d capped button cannot spend another garrison" % kind)
		check(game.marches.total_for(0) == 0 and game.selected == building, "kind %d upgrade buttons never dispatch or select the map behind them" % kind)
	# Disabled affordability feedback is explicit at both upgrade thresholds.
	home.level = 1
	home.population = 29.0
	home.refresh_visual()
	await select_on_map(home)
	check(upgrade.disabled and hint.text.contains("还差 1"), "level 1 shortfall is visible without hovering")
	await click(center(upgrade))
	check(home.level == 1 and home.population == 29.0, "insufficient level 1 click changes nothing")
	home.level = 2
	home.population = 59.0
	home.refresh_visual()
	game.update_hud()
	check(upgrade.disabled and upgrade.text.contains("60 驻军") and hint.text.contains("还差 1"), "level 2 shortfall uses the unchanged 60 cost")
	await click(center(upgrade))
	check(home.level == 2 and home.population == 59.0, "insufficient level 2 click changes nothing")
	# Ownership is communicated, and neither hostile nor neutral buildings upgrade.
	for hostile: Node3D in [game.by_id[1], game.by_id[2]]:
		hostile.level = 1
		hostile.population = 120.0
		hostile.refresh_visual()
		await select_on_map(hostile)
		var affiliation := "敌方" if hostile.faction == 1 else "中立"
		check(upgrade.disabled and title.text.contains(affiliation) and not manage.visible, affiliation + " has no enabled building actions")
		await click(center(upgrade))
		check(hostile.level == 1 and hostile.population == 120.0, affiliation + " click cannot spend its garrison")
	# Conversion remains a separate available action; opening it never hides upgrade.
	home.level = 1
	home.population = 120.0
	home.refresh_visual()
	await select_on_map(home)
	await click(center(manage))
	await create_timer(0.22).timeout
	check(game.hud.get_node("%BuildingActions").is_visible_in_tree() and upgrade.is_visible_in_tree(), "conversion menu keeps the direct upgrade accessible")
	await click(center(game.hud.get_node("%ConvertTower")))
	check(home.kind == 1 and home.level == 1 and home.population == 90.0, "retained conversion button spends its unchanged 30-garrison cost")
	await click(center(upgrade))
	check(home.level == 2 and home.population == 60.0, "converted building can immediately upgrade through the same direct button")
	await click(center(manage))
	game.set_paused(true)
	game.update_hud()
	await frames()
	check(upgrade.disabled and hint.text == "暂停中", "pause disables and explains the upgrade action")
	await click(center(upgrade))
	check(home.level == 2 and home.population == 60.0 and game._local_menu, "pause overlay rejects an actual upgrade click")
	game.set_paused(false)
	game.update_hud()
	check(not upgrade.disabled, "resume restores an affordable upgrade")
	# Put a real map building under the action's exact screen coordinates.
	var covered: Node3D = game.by_id[12]
	var at := center(upgrade)
	var delta := point(covered) - at
	var units_per_pixel: float = game.camera.size / root.get_visible_rect().size.y
	game.camera_rig.position += Vector3(delta.x * units_per_pixel, 0, delta.y * units_per_pixel / absf(sin(game.camera.rotation.x)))
	game.camera_rig.destination = game.camera_rig.position
	await frames()
	check(point(covered).distance_to(at) < 1.0 and game.pick_building(at) == covered, "upgrade overlap fixture contains a real building underneath")
	check(game.hud.is_pointer_blocked(at), "upgrade coordinates are explicitly blocked from world dispatch")
	await click(at)
	check(home.level == 3 and home.population == 0.0 and game.selected == home and game.marches.total_for(0) == 0, "upgrade over another building neither selects it nor sends troops")
	# A map drag ending on this action cannot upgrade or dispatch to its backdrop.
	home.level = 1
	home.population = 120.0
	home.refresh_visual()
	game.update_hud()
	var start := point(home)
	var press := InputEventMouseButton.new()
	press.window_id = root.get_window_id()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	check(game.drag_source == home, "overlap fixture begins an actual allied map drag")
	var release := InputEventMouseButton.new()
	release.window_id = root.get_window_id()
	release.position = at
	release.global_position = at
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await frames()
	check(home.level == 1 and home.population == 120.0 and game.marches.total_for(0) == 0 and game.drag_source == null, "releasing a map drag over upgrade cancels without upgrade or dispatch")
	await game.prepare_shutdown()
	print("BLOCK_WAR_UPGRADE_INPUT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
