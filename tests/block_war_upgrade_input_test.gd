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
	var menu: Control = game.hud.get_node("%Selection")
	var cost: Label = upgrade.get_node("Cost/Amount")
	var next_level: Label = upgrade.get_node("NextLevel")
	var home: Node3D = game.by_id[0]
	var sources: Array[Node3D] = [home, game.by_id[6], game.by_id[8]]
	for kind: int in sources.size():
		var building: Node3D = sources[kind]
		building.kind = kind
		building.faction = 0
		building.level = 1
		building.population = 120.0
		building.refresh_visual()
		await select_on_map(building)
		if kind == 2:
			check(not upgrade.is_visible_in_tree() and upgrade.disabled, "forge hides its upgrade and cannot start construction through that action")
			check(menu.size.x == 134.0 and game.hud.get_node("%ConvertHouse").is_visible_in_tree() and game.hud.get_node("%ConvertTower").is_visible_in_tree(), "forge menu fits exactly two compact conversion actions")
			continue
		check(upgrade.is_visible_in_tree() and not upgrade.disabled, "kind %d exposes upgrade beside the selected building" % kind)
		var expected_costs := [10, 20, 30] if kind == 0 else [30, 60]
		var expected_max := 4 if kind == 0 else 3
		var remaining := 120.0
		for tier: int in expected_costs.size():
			check(next_level.text == str(tier + 2) and cost.text == str(expected_costs[tier]) and upgrade.text.is_empty(), "kind %d tier %d shows the actual next level and cost" % [kind, tier + 1])
			await click(center(upgrade))
			remaining -= expected_costs[tier]
			check(building.level == tier + 1 and building.is_constructing and building.population == remaining, "kind %d click pays exactly %d and starts construction" % [kind, expected_costs[tier]])
			check(upgrade.disabled and cost.text == "10s" and not upgrade.get_node("Cost/Population").visible, "construction replaces cost with a disabled ten-second countdown")
			await click(center(upgrade))
			check(building.population == remaining and building.construction_remaining == 10.0, "repeated construction click neither pays again nor restarts the timer")
			game.simulate(10.0)
			game.update_hud()
			check(building.level == tier + 2 and not building.is_constructing, "kind %d completes its paid level after ten seconds" % kind)
		check(upgrade.disabled and next_level.text == str(expected_max) and cost.text == "—", "kind %d visibly reaches its correct maximum level" % kind)
		check(upgrade.tooltip_text.contains("已达 %d 级" % expected_max), "max-level tooltip matches the building kind")
		await click(center(upgrade))
		check(building.level == expected_max and building.population == remaining, "kind %d capped button cannot spend another garrison" % kind)
		check(game.marches.total_for(0) == 0 and game.selected == building, "kind %d upgrade buttons never dispatch or select the map behind them" % kind)
	# Every residential upgrade rejects even a one-person shortfall.
	for tier: int in [1, 2, 3]:
		home.level = tier
		home.population = tier * 10 - 1
		home.refresh_visual()
		await select_on_map(home)
		check(upgrade.disabled and cost.text == str(tier * 10) and upgrade.tooltip_text.contains("还差 1"), "house level %d explains its actual shortfall" % tier)
		await click(center(upgrade))
		check(home.level == tier and home.population == tier * 10 - 1, "insufficient house level %d click changes nothing" % tier)
	# Ownership is communicated, and neither hostile nor neutral buildings upgrade.
	for hostile: Node3D in [game.by_id[1], game.by_id[2]]:
		hostile.level = 1
		hostile.population = 120.0
		hostile.refresh_visual()
		await select_on_map(hostile)
		var affiliation := "敌方" if hostile.faction == 1 else "中立"
		check(not menu.is_visible_in_tree(), affiliation + " has no building action menu")
		check(hostile.level == 1 and hostile.population == 120.0, affiliation + " selection cannot spend its garrison")
	# Only the two different building kinds appear alongside the direct upgrade.
	home.level = 4
	home.population = 120.0
	home.refresh_visual()
	await select_on_map(home)
	check(not game.hud.get_node("%ConvertHouse").is_visible_in_tree() and game.hud.get_node("%ConvertTower").is_visible_in_tree() and game.hud.get_node("%ConvertForge").is_visible_in_tree(), "house exposes exactly its two alternative conversions")
	await click(center(game.hud.get_node("%ConvertTower")))
	check(home.kind == 0 and home.level == 4 and home.population == 100.0 and home.conversion_target == 1, "level-four house pays twenty and starts conversion through real input")
	game.simulate(10.0)
	game.update_hud()
	check(home.kind == 1 and home.level == 1, "ten seconds completes a level-one tower conversion")
	var conversions: Array[Button] = [game.hud.get_node("%ConvertHouse"), game.hud.get_node("%ConvertTower"), game.hud.get_node("%ConvertForge")]
	for kind: int in [2, 0, 1]:
		home.population = 120.0
		game.update_hud()
		await frames()
		await click(center(conversions[kind]))
		check(home.conversion_target == kind and home.population == 100.0, "conversion icon %d charges twenty and shows the chosen construction" % kind)
		game.simulate(10.0)
		game.update_hud()
		check(home.kind == kind and home.level == 1 and not conversions[kind].visible, "conversion icon %d completes and leaves the alternatives" % kind)
	home.population = 90.0
	game.update_hud()
	await click(center(upgrade))
	check(home.level == 1 and home.is_constructing and home.population == 60.0, "converted building starts construction through the same direct button")
	game.simulate(10.0)
	game.update_hud()
	game.set_paused(true)
	game.update_hud()
	await frames()
	check(upgrade.disabled and not menu.visible, "pause hides and disables the contextual actions")
	await click(center(upgrade))
	check(home.level == 2 and home.population == 60.0 and game._local_menu, "pause overlay rejects an actual upgrade click")
	game.set_paused(false)
	game.update_hud()
	check(not upgrade.disabled, "resume restores an affordable upgrade")
	# The panel follows camera motion every frame, independently of the 10 Hz HUD refresh.
	game.camera_rig.focus_at(home.global_position, true)
	await frames()
	var before := menu.position
	game.camera_rig.position.x += 2.0
	await frames()
	check(menu.visible and menu.position.distance_to(before) > 10.0, "camera pan moves the menu with its building without a state refresh")
	game.camera.size = 37.0
	await frames()
	check(menu.visible and not menu.get_global_rect().has_point(point(home)), "zoom keeps the action strip beside the building without covering it")
	# Both screen edges and a smaller window retain the entire menu.
	for direction: float in [-1.0, 1.0]:
		game.camera_rig.focus_at(home.global_position + Vector3(direction * 22.0, 0, 0), true)
		await frames()
		check(menu.visible and Rect2(Vector2.ZERO, game.hud.get_node("UI").size).encloses(menu.get_rect()), "screen edge %s keeps all actions reachable" % direction)
	game.camera_rig.focus_at(home.global_position, true)
	root.size = Vector2i(1280, 720)
	await frames(4)
	check(menu.visible and Rect2(Vector2.ZERO, game.hud.get_node("UI").size).encloses(menu.get_rect()), "resizing retains the complete contextual menu")
	game.camera_rig.position.x += 150.0
	await frames()
	check(not menu.visible, "an offscreen building cannot leave detached clickable actions")
	game.camera_rig.focus_at(home.global_position, true)
	game.armed_skill = 0
	game.update_hud()
	check(not menu.visible, "targeting a skill hides building actions so they cannot block targets")
	game.armed_skill = -1
	game.update_hud()
	root.size = Vector2i(1600, 900)
	await frames(4)
	# Put a real map building under the action's exact screen coordinates.
	var covered: Node3D = game.by_id[12]
	game.hud.set_process(false)
	var at := center(upgrade)
	covered.global_position = Plane(Vector3.UP, 1.5).intersects_ray(game.camera.project_ray_origin(at), game.camera.project_ray_normal(at)) - Vector3(0, 1.5, 0)
	await physics_frame
	await frames()
	check(point(covered).distance_to(at) < 1.0 and game.pick_building(at) == covered, "upgrade overlap fixture contains a real building underneath")
	check(game.hud.is_pointer_blocked(at), "upgrade coordinates are explicitly blocked from world dispatch")
	await click(at)
	check(home.level == 2 and home.is_constructing and home.population == 0.0 and game.selected == home and game.marches.total_for(0) == 0, "upgrade over another building neither selects it nor sends troops")
	game.simulate(10.0)
	check(home.level == 3, "overlapping upgrade still completes its ten-second construction")
	# A map drag ending on this action cannot upgrade or dispatch to its backdrop.
	home.level = 1
	home.population = 120.0
	home.refresh_visual()
	game.update_hud()
	await frames()
	at = center(upgrade)
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
	# Pressing the source refreshes its actions and may reflow around the moved
	# obstacle. Drop on the current action, with the real pick area beneath it.
	at = center(upgrade)
	covered.global_position = Plane(Vector3.UP, 1.5).intersects_ray(game.camera.project_ray_origin(at), game.camera.project_ray_normal(at)) - Vector3(0, 1.5, 0)
	await physics_frame
	await frames()
	check(game.pick_building(at) == covered and game.hud.is_pointer_blocked(at), "dispatch-drop fixture overlaps the current action rather than its previous position")
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
