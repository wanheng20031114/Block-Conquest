extends "res://tests/block_war_dispatch_input_test.gd"
## Native box/Shift gestures, real queues and private-desktop visual review.

var sources: Array[Node3D] = []
var sounds: Array[StringName] = []
var dispatches: Array[Dictionary] = []
var output := ""

func shifted_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.window_id = root.get_window_id()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.shift_pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func clear_feedback() -> void:
	for branch: String in ["UI", "Combat", "Foley"]:
		for voice: Node in game.audio.get_node(branch).get_children(): voice.stop()
	game.audio._next_sound_ms.clear()
	sounds.clear()
	dispatches.clear()
	game.effects.clear()

func rectangle(values: Array[Node3D]) -> Rect2:
	var at: Vector2 = game.camera.unproject_position(values[0].global_position)
	var rect := Rect2(at, Vector2.ZERO)
	for building: Node3D in values: rect = rect.expand(game.camera.unproject_position(building.global_position))
	for x_padding: float in [32.0, 64.0, 96.0, 128.0]:
		for y_padding: float in [32.0, 64.0, 96.0]:
			var padding := Vector2(x_padding, y_padding)
			var candidate := Rect2(rect.position - padding, rect.size + padding * 2)
			if root.get_visible_rect().encloses(candidate) and game.pick_building(candidate.position) == null and game.pick_building(candidate.end) == null and not game.hud.is_pointer_blocked(candidate.position) and not game.hud.is_pointer_blocked(candidate.end): return candidate
	check(false, "fixture has an empty-ground rectangle start")
	return rect.grow(32)

func box(rect: Rect2, additive: bool = false, reverse: bool = false) -> void:
	var start := rect.end if reverse else rect.position
	var finish := rect.position if reverse else rect.end
	motion(start)
	if additive: shifted_button(start, true)
	else: button(start, true)
	motion(finish, true)
	if additive: shifted_button(finish, false)
	else: button(finish, false)

func replenish() -> void:
	game.marches.clear()
	for index: int in sources.size():
		sources[index].faction = 0
		sources[index].population = [20.0, 31.0, 50.0][index]
		sources[index].clear_burrow()
		sources[index].refresh_visual()
	game.select_buildings(sources)
	game.set_percentage(50)
	game.energy = 100.0
	game.cooldowns.fill(0.0)
	clear_feedback()

func capture_image(name: String) -> void:
	await frames(3)
	game.overlay._process(0.0)
	game.overlay.queue_redraw()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, name + " screenshot saved")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.ai_enabled = false
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	await create_timer(0.8).timeout
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool): sounds.append(kind))
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind == "dispatch": dispatches.append(payload)
	)
	sources.assign([game.by_id[0], game.by_id[6], game.by_id[8]])
	for building: WarBuilding in game.buildings:
		building.faction = -1
		building.refresh_visual()
	var target: WarBuilding = game.by_id[1]
	target.faction = 1
	target.refresh_visual()
	var teammate: WarBuilding = game.by_id[2]
	teammate.faction = 1
	teammate.refresh_visual()
	replenish()
	game.select_building(null)
	await physics_frame
	var rect := rectangle(sources)
	var empty := rect.position
	clear_feedback()
	motion(empty)
	button(empty, true)
	check(game.box_selecting and game.camera_rig.selection_dragging, "empty-ground press starts selection and holds camera")
	motion(rect.end, true)
	check(game.box_preview.size() == 3 and sounds.is_empty(), "box previews only three owned buildings without drag audio")
	check(sources.all(func(building: Node3D): return building.get_node("SelectionRing").visible and not building._is_selected), "preview shows existing rings without committing selection")
	var pose: Transform3D = game.camera_rig.transform
	game.camera_rig._process(1.0)
	check(game.camera_rig.transform == pose, "camera remains stable while drawing the rectangle")
	await capture_image("01-box-preview")
	button(rect.end, false)
	check(game.selected_buildings.size() == 3 and sources.all(func(building: Node3D): return building in game.selected_buildings), "box release commits the group")
	check(game.marches._units.is_empty() and dispatches.is_empty(), "box release never dispatches")
	check(sounds == [&"war_select"] and not game.box_selecting and not game.camera_rig.selection_dragging, "group confirmation has one ta and releases camera")
	game.hud._position_selection()
	check(not game.hud.get_node("%Selection").visible, "group selection hides single-building actions")
	var motions: Array[Tween] = []
	for source: Node3D in sources: motions.append(source._selection_body_tween)
	box(rect)
	for index: int in sources.size(): check(sources[index]._selection_body_tween == motions[index], "reconfirming a member does not restart its rebound")
	clear_feedback()
	button(point(sources[1]), true)
	check(game.selected_buildings.size() == 3 and game.drag_sources.size() == 3, "pressing any selected member preserves the group")
	motion(point(target), true)
	check(game.order_previews.size() == 3 and game.dispatch_preview_count() == 50, "three actual routes preview floor(20/2)+floor(31/2)+floor(50/2)=50")
	check(sounds.is_empty(), "group route drag is silent")
	game.overlay.queue_redraw()
	await capture_image("02-group-routes")
	button(point(target), false)
	check(game.marches.incoming_for(target.building_id, 0) == 50, "release dispatches all fifty soldiers")
	check(sources[0].queued_population == 10 and sources[1].queued_population == 15 and sources[2].queued_population == 25, "each source reserves its own floored share")
	check(sounds == [&"war_order"] and dispatches.size() == 1 and game.effects.size() == 1, "one group order emits one confirmation, one marker and one network event")
	check(game.selected_buildings.size() == 3 and game.drag_source == null and game.order_previews.is_empty(), "dispatch keeps selection and clears its gesture")
	replenish()
	button(point(sources[1]), true)
	button(point(sources[1]), false)
	game.hud._position_selection()
	check(game.selected_buildings == [sources[1]] and game.hud.get_node("%Selection").visible, "short click collapses the group and restores native actions")
	shifted_button(point(sources[0]), true)
	shifted_button(point(sources[0]), false)
	check(game.selected_buildings.size() == 2, "Shift click adds a building")
	shifted_button(point(sources[1]), true)
	shifted_button(point(sources[1]), false)
	check(game.selected_buildings == [sources[0]], "Shift click removes a building")
	shifted_button(point(teammate), true)
	shifted_button(point(teammate), false)
	check(game.selected_buildings == [sources[0]], "Shift never adds another faction's building")
	box(rectangle([sources[2]]), true, true)
	check(sources[0] in game.selected_buildings and sources[2] in game.selected_buildings, "reverse Shift box appends to existing selection")
	replenish()
	button(point(sources[0]), true)
	motion(point(sources[1]), true)
	check(game.dispatch_preview_count() == 35, "selected destination excludes its own fifteen soldiers")
	button(point(sources[1]), false)
	check(game.marches.incoming_for(sources[1].building_id, 0) == 35 and sources[1].queued_population == 0, "group can reinforce one of its own members")
	replenish()
	button(point(sources[0]), true)
	motion(point(target), true)
	motion(point(sources[0]), true)
	check(game.dispatch_preview_count() == 40, "the original drag anchor can itself be the reinforcement target")
	button(point(sources[0]), false)
	check(game.marches.incoming_for(sources[0].building_id, 0) == 40 and game.selected_buildings.size() == 3, "returning a moved gesture does not collapse to a click")
	replenish()
	button(point(sources[0]), true)
	motion(point(target), true)
	button(point(target), true, MOUSE_BUTTON_RIGHT)
	button(point(target), false)
	check(game.marches._units.is_empty() and game.selected_buildings.size() == 3 and sounds.is_empty(), "right-click cancels a group order but retains selection silently")
	button(empty, true, MOUSE_BUTTON_RIGHT)
	check(game.selected_buildings.is_empty(), "idle right-click clears selection")
	replenish()
	button(empty, true)
	motion(rect.end, true)
	button(rect.end, true, MOUSE_BUTTON_RIGHT)
	button(rect.end, false)
	check(game.selected_buildings.size() == 3 and not game.box_selecting and not game.camera_rig.selection_dragging, "right-click cancels box preview and restores committed selection")
	button(empty, true)
	button(empty, false)
	check(game.selected_buildings.is_empty(), "empty short click clears selection")
	replenish()
	var ratio: Button = game.hud.get_node("UI/Percentages/Stack/P25")
	button(point(sources[0]), true)
	button(ratio.get_global_rect().get_center(), false)
	button(point(sources[0]), true)
	button(Vector2(-20, 450), false)
	check(game.marches._units.is_empty() and game.drag_source == null and game.selected_buildings.size() == 3, "releasing outside the viewport cancels without losing the group")
	check(game.marches._units.is_empty() and game.selected_buildings.size() == 3, "HUD release cancels group dispatch without changing selection")
	button(ratio.get_global_rect().get_center(), true)
	check(not game.box_selecting and game.drag_source == null, "HUD press never begins map box selection")
	button(ratio.get_global_rect().get_center(), false)
	for cancel: String in ["focus", "menu", "middle", "skill"]:
		replenish()
		button(empty, true)
		motion(rect.end, true)
		match cancel:
			"focus": game._on_focus_exited()
			"menu": game.set_paused(true)
			"middle": button(empty, true, MOUSE_BUTTON_MIDDLE)
			"skill": game.request_skill(0)
		check(not game.box_selecting and not game.camera_rig.selection_dragging and game.selected_buildings.size() == 3, cancel + " cancels box and preserves group")
		game._cancel_skill_drag()
		game.set_paused(false)
		button(empty, false, MOUSE_BUTTON_MIDDLE)
		button(empty, false)
	replenish()
	button(point(sources[0]), true)
	sources[0].faction = 1
	sources[0].refresh_visual()
	game.update_hud()
	motion(point(target), true)
	check(game.selected_buildings.size() == 2 and game.dispatch_preview_count() == 40, "captured drag anchor is pruned while other members remain eligible")
	button(point(target), false)
	check(sources[0].queued_population == 0 and game.marches.incoming_for(target.building_id, 0) == 40, "capturing the anchor cannot spend enemy troops or block other sources")
	replenish()
	sources[1].population = 0.0
	var route_key: Vector4 = game.map._route_key(sources[2], target)
	var saved: PackedVector3Array = game.map._route_cache[route_key]
	game.map._route_cache[route_key] = PackedVector3Array()
	button(point(sources[0]), true)
	motion(point(target), true)
	check(game.dispatch_preview_count() == 10 and game.order_previews.size() == 1, "empty and unreachable sources are omitted from routes and total")
	button(point(target), false)
	check(game.marches.incoming_for(target.building_id, 0) == 10, "remaining valid source still dispatches")
	game.map._route_cache[route_key] = saved
	replenish()
	sources[0].population = 120.0
	sources[0].begin_burrow(15.0)
	game.set_percentage(100)
	clear_feedback()
	button(point(sources[1]), true)
	motion(point(target), true)
	check(game.dispatch_preview_count() == 131, "mixed tunnel group uses the fifty-soldier tunnel cap plus ordinary sources")
	button(point(target), false)
	check(sources[0].queued_population == 50 and sources[0].burrow_remaining == 0.0 and sources[1].queued_population == 31 and sources[2].queued_population == 50, "group preserves per-building tunnel and ordinary queues")
	check(dispatches.size() == 1, "mixed tunnel group still confirms only once")
	game.hud._open_help()
	await capture_image("03-controls-help")
	var help: Label = game.hud.get_node("%HelpCard/Detail0")
	check(help.get_line_count() <= 4 and help.get_minimum_size().y <= 103, "group controls fit the existing help area")
	await game.prepare_shutdown()
	print("BLOCK_WAR_GROUP_SELECTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
