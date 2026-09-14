extends SceneTree
## Real GUI events exercise grouped roster selection and atomic model-table gestures.
var checks := 0
var failures: Array[String] = []
var panel: RogueArmyPanel
var board: RogueArmyBoard
var rogue: RogueSession
var capture_enabled := false
var _last_pointer := Vector2.ZERO

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	root.content_scale_size = Vector2i.ZERO
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled:
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", label)
	if not condition: failures.append(label)

func frames(count: int = 3) -> void:
	for i: int in count: await process_frame

func _run() -> void:
	create_timer(65, true, false, true).timeout.connect(func() -> void: quit(3))
	DirAccess.make_dir_recursive_absolute("res://.local/army_ui")
	rogue = root.get_node("Session").rogue
	var real_save := rogue.save_path
	var real_hash := FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else ""
	rogue.save_path = "user://rogue_army_ui_test.json"
	check(rogue.state.start_new("range", "steady", 90256) == OK, "start deterministic army")
	while not rogue.state.data.pending_recruits.is_empty():
		check(rogue.state.discard_recruit(int(rogue.state.data.pending_recruits[0].uid)) == OK, "fixture completes mandatory initial recruit")
	rogue.state._add_unit("heavy_cannon", false)
	rogue.state._add_unit("heavy_cannon", false)
	check(rogue.state.checkpoint_error().is_empty(), "fixture is a valid complete checkpoint")
	var heavy: Array = rogue.state.data.roster.filter(func(unit: Dictionary) -> bool: return unit.kind == "heavy_cannon")
	var scene: PackedScene = load("res://scenes/rogue/army_panel.tscn")
	panel = scene.instantiate()
	root.add_child(panel)
	root.size = Vector2i(1280, 720)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.open_panel()
	board = panel.get_node("%ArmyBoard")
	await frames(10)
	check(panel.find_child("RecruitTab", true, false) == null and panel.find_child("ArmyTickets", true, false) == null, "formation contains no recruitment tab or ticket inventory")
	check(board._models.size() == rogue.state.deployed_units().size(), "authored models cover deployed roster")
	check(panel._rows.size() == 7, "rows aggregate six deployed kinds and one reserve kind")
	check(panel.get_node("%PopulationValue").text == "18 / 20", "only header presents total deployed population")
	for row: Button in panel._rows.values():
		check(not row.get_node("Margin/Content/Name").text.contains("#") and not row.get_node("Margin/Content/Count").text.contains("人口"), "group row omits per-unit identity and supply")
	var swords: Array = rogue.state.data.roster.filter(func(unit: Dictionary) -> bool: return unit.kind == "swordsman")
	var sword_ids: Array = swords.map(func(unit: Dictionary) -> int: return int(unit.uid))
	await click(panel._rows["out:swordsman"].get_global_rect().get_center())
	check(_same_selection(sword_ids), "real group click selects all four swordsmen")
	check(panel.get_node("%UnitName").text == "剑士" and not panel.get_node("%SelectionSummary").text.contains("#"), "group inspector uses name and selected count")
	await click(panel._rows["out:shield_guard"].get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
	check(panel._selected_uids.size() == 7, "Shift group click adds another kind")
	await click(panel._rows["out:shield_guard"].get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
	check(_same_selection(sword_ids), "Shift group click toggles the entire kind off")
	await click(panel._rows["out:swordsman"].get_global_rect().get_center(), MOUSE_BUTTON_LEFT, false, true)
	check(_deployed_count(sword_ids) == 3, "group double click transfers exactly one soldier")
	await click(panel.get_node("%DeployButton").get_global_rect().get_center())
	check(_deployed_count(sword_ids) == 0 and rogue.state.population() == 14, "selected group button atomically moves remaining soldiers to reserve")
	await click(panel.get_node("%EnlistButton").get_global_rect().get_center())
	check(_deployed_count(sword_ids) == 4 and rogue.state.population() == 18, "selected group button returns the full group to deployment")
	await click(panel._rows["reserve:heavy_cannon"].get_global_rect().get_center())
	var before := rogue.state.data.duplicate(true)
	await click(panel.get_node("%EnlistButton").get_global_rect().get_center())
	check(rogue.state.data == before and _deployed_count(heavy.map(func(unit: Dictionary) -> int: return int(unit.uid))) == 0, "over-population group is wholly rejected")
	check(not panel.get_node("%ArmyStatus").text.is_empty(), "rejected batch explains the population constraint")

	# Place two units in a free lane; all interaction below is injected through the root viewport.
	var first := int(sword_ids[0])
	var second := int(sword_ids[1])
	check(rogue.set_layouts("outpost", [{"uid": first, "layout": [-7.0,-7.0,0.0]}, {"uid": second, "layout": [-3.5,-7.0,0.0]}]) == OK, "fixture creates a separated formation lane")
	await frames(4)
	var first_point := point(Vector3(-7, 0, -7))
	await click(first_point)
	check(_same_selection([first]), "native model ray pick selects one soldier")
	await click(point(Vector3(-3.5,0,-7)), MOUSE_BUTTON_LEFT, true)
	check(_same_selection([first, second]), "Shift model click adds a second soldier")
	var pair_before: Array = [_layout(first), _layout(second)]
	var other_encounter := [_layout(first, "siege"), _layout(second, "siege")]
	await click(point(Vector3(-5.25,0,-4)), MOUSE_BUTTON_RIGHT)
	check(is_equal_approx(_layout(first)[1], -4.0) and is_equal_approx(_layout(second)[1], -4.0), "right click moves the pair by a shared offset")
	check(_layout(second)[0] - _layout(first)[0] == pair_before[1][0] - pair_before[0][0], "group right click preserves spacing")
	check(other_encounter == [_layout(first,"siege"),_layout(second,"siege")], "outpost edit does not alter siege layout")
	var center_before := _center([first, second])
	var distance_before := _distance(first, second)
	await key(KEY_E)
	check(_center([first, second]).distance_to(center_before) < .001 and is_equal_approx(_distance(first, second), distance_before), "E rotates positions about the group center without changing spacing")
	check(is_equal_approx(float(_layout(first)[2]), deg_to_rad(15)) and is_equal_approx(float(_layout(second)[2]), deg_to_rad(15)), "E rotates every facing in the group")
	await key(KEY_Q)
	check(is_zero_approx(float(_layout(first)[2])) and is_zero_approx(float(_layout(second)[2])), "Q reverses group rotation")
	var drag_before := rogue.state.data.duplicate(true)
	var drag_from := point(Vector3(float(_layout(first)[0]),0,float(_layout(first)[1])))
	var drag_to := drag_from + (point(Vector3(0,0,2)) - point(Vector3.ZERO))
	mouse(drag_from, MOUSE_BUTTON_LEFT, true)
	motion(drag_to, MOUSE_BUTTON_MASK_LEFT)
	await frames()
	check(rogue.state.data == drag_before, "drag preview never writes the persistent roster")
	check(board.has_gesture() and board._models[first].position.z > float(_layout(first)[1]) + 1.5, "drag previews the entire selected group")
	mouse(drag_to, MOUSE_BUTTON_LEFT, false)
	await frames(4)
	check(is_equal_approx(float(_layout(first)[1]), -2.0) and is_equal_approx(float(_layout(second)[1]), -2.0), "drag release commits the group exactly once")

	before = rogue.state.data.duplicate(true)
	var saved_hash := FileAccess.get_sha256(rogue.save_path)
	await click(point(Vector3(11.8,0,-2)), MOUSE_BUTTON_RIGHT)
	check(rogue.state.data == before, "out-of-bounds right click rolls back every member")
	check(FileAccess.get_sha256(rogue.save_path) == saved_hash, "invalid group move preserves the checkpoint")
	check(board._models[first].position == Vector3(float(_layout(first)[0]),0,float(_layout(first)[1])), "failed move returns the visible models to their saved positions")
	var target: Dictionary = rogue.state.data.roster.filter(func(unit: Dictionary) -> bool: return unit.deployed and int(unit.uid) not in [first,second])[0]
	var target_layout: Array = target.layouts.outpost
	var delta := Vector2(float(target_layout[0]) - float(_layout(first)[0]), float(target_layout[1]) - float(_layout(first)[1]))
	var center := _center([first,second])
	await click(point(Vector3(center.x + delta.x, 0, center.y + delta.y)), MOUSE_BUTTON_RIGHT)
	check(rogue.state.data == before, "collision against an unselected unit rolls back the whole group")
	check(panel.get_node("%ArmyStatus").text.contains("重叠"), "overlap reason appears beside the board")

	# Empty-ground marquee surrounds just the separated pair.
	var a := point(Vector3(float(_layout(first)[0]),0,float(_layout(first)[1])))
	var b := point(Vector3(float(_layout(second)[0]),0,float(_layout(second)[1])))
	var box_start := Vector2(minf(a.x,b.x)-20, minf(a.y,b.y)-36)
	var box_end := Vector2(maxf(a.x,b.x)+20, maxf(a.y,b.y)+12)
	await click(point(Vector3(-10,0,10)))
	check(panel._selected_uids.is_empty(), "empty click clears selection")
	var before_box_rect := board.get_global_rect()
	mouse(box_start, MOUSE_BUTTON_LEFT, true)
	motion(box_end, MOUSE_BUTTON_MASK_LEFT)
	await frames()
	check(board.get_node("%SelectionBox").visible, "native marquee is visible while selecting")
	check(board.get_global_rect() == before_box_rect, "selection inspector does not resize the board during a marquee")
	mouse(box_end, MOUSE_BUTTON_LEFT, false)
	await frames()
	check(_same_selection([first,second]), "real marquee selects both enclosed models")
	check(not board.has_gesture(), "fast marquee release clears its gesture")
	var unselected: int = int(sword_ids[2])
	await click(point(board._models[unselected].position), MOUSE_BUTTON_LEFT, true)
	check(panel._selected_uids.size() == 3, "Shift click extends a marquee selection")
	mouse(box_start, MOUSE_BUTTON_LEFT, true, true)
	motion(box_end, MOUSE_BUTTON_MASK_LEFT)
	mouse(box_end, MOUSE_BUTTON_LEFT, false, true)
	await frames()
	check(_same_selection([first, second, unselected]) and not board.has_gesture(), "fast Shift marquee keeps the previous selection and finishes in one input frame")
	await click(point(board._models[first].position), MOUSE_BUTTON_LEFT, false, true)
	check(not panel._unit_by_uid(first).deployed and panel._unit_by_uid(second).deployed and panel._unit_by_uid(unselected).deployed, "model double click transfers only its own unit from a multiselection")

	# Shift double click applies to the full aggregate row, independent of current selection.
	await click(panel._rows["out:swordsman"].get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true, true)
	check(_deployed_count(sword_ids) == 0, "Shift double click transfers all members of the clicked kind")
	await click(panel._rows["reserve:swordsman"].get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true, true)
	check(_deployed_count(sword_ids) == 4, "Shift double click restores the reserve kind atomically")
	panel._select_uids([first,second])
	panel._on_map_selected(1)
	await frames(4)
	before = rogue.state.data.duplicate(true)
	var siege_layout: Array = _layout(first, "siege")
	var siege_center := Vector2.ZERO
	for uid: int in [first, second]:
		var layout: Array = _layout(uid, "siege")
		siege_center += Vector2(float(layout[0]), float(layout[1])) * .5
	await click(point(Vector3(siege_center.x-float(siege_layout[0]), 0, siege_center.y-float(siege_layout[1]))), MOUSE_BUTTON_RIGHT)
	check(rogue.state.data == before, "siege central-base exclusion rejects a group move atomically")
	check(board.get_node("%ArmyFootprint").visible and panel.get_node("%ArmyStatus").text.contains("基地"), "siege base footprint and rejection explanation remain visible")
	await _capture("siege_1280")

	panel._on_map_selected(0)
	panel._select_uids([first,second])
	await frames(4)
	before = rogue.state.data.duplicate(true)
	drag_from = point(board._models[first].position)
	var outside := Vector2(4, drag_from.y)
	mouse(drag_from, MOUSE_BUTTON_LEFT, true)
	motion(outside, MOUSE_BUTTON_MASK_LEFT)
	mouse(outside, MOUSE_BUTTON_LEFT, false)
	await frames(4)
	check(not board.has_gesture() and rogue.state.data == before, "release outside the board cancels invalid whole-group placement without a stuck gesture")
	check(board._models[first].position == Vector3(float(_layout(first)[0]),0,float(_layout(first)[1])), "outside release restores the saved model pose")
	panel._select_uids(sword_ids)
	for width: int in [1280,1600,1920]:
		root.size = Vector2i(width, int(width * .5625))
		await frames(6)
		var bounds := root.get_visible_rect()
		for node_name: String in ["CloseArmy","MapChoice","ArmyBoard","DeployButton","EnlistButton","PopulationValue"]:
			check(bounds.encloses(panel.get_node("%"+node_name).get_global_rect()), "%d %s stays in viewport" % [width,node_name])
		check(board.size.x >= 450 and board.size.y >= 340, "%d retains a useful model workspace" % width)
		await _capture("formation_%d" % width)

	# Cancel a live drag before closing; neither gesture nor a hidden viewport can linger.
	panel._select_uid(first)
	await frames(3)
	before = rogue.state.data.duplicate(true)
	drag_from = point(board._models[first].position)
	mouse(drag_from, MOUSE_BUTTON_LEFT, true)
	motion(drag_from + Vector2(18,0), MOUSE_BUTTON_MASK_LEFT)
	await key(KEY_ESCAPE)
	mouse(drag_from + Vector2(18,0), MOUSE_BUTTON_LEFT, false)
	await frames()
	check(panel.visible and not board.has_gesture() and rogue.state.data == before, "Esc cancels a drag without closing or saving")
	await key(KEY_ESCAPE)
	check(not panel.visible, "Esc closes the formation after gesture cancellation")
	check(board.get_node("%ArmyViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed model viewport stops rendering")
	check(FileAccess.file_exists(rogue.save_path), "valid formation edits create the isolated checkpoint")
	check((FileAccess.get_sha256(real_save) if FileAccess.file_exists(real_save) else "") == real_hash, "real player checkpoint is untouched")
	panel.queue_free()
	await frames()
	for suffix: String in ["", ".tmp"]:
		var test_path := ProjectSettings.globalize_path(rogue.save_path + suffix)
		if FileAccess.file_exists(test_path): DirAccess.remove_absolute(test_path)
	print("ROGUE_ARMY_UI: %d checks, %d failures; %s" % [checks, failures.size(), str(failures)])
	quit(0 if failures.is_empty() else 1)

func _same_selection(uids: Array) -> bool:
	return panel._selected_uids.size() == uids.size() and uids.all(func(uid: int) -> bool: return uid in panel._selected_uids)

func _deployed_count(uids: Array) -> int:
	return rogue.state.data.roster.filter(func(unit: Dictionary) -> bool: return int(unit.uid) in uids and unit.deployed).size()

func _layout(uid: int, encounter: String = "outpost") -> Array:
	return panel._unit_by_uid(uid).layouts[encounter].duplicate()

func _center(uids: Array) -> Vector2:
	var center := Vector2.ZERO
	for uid: int in uids:
		var layout := _layout(uid)
		center += Vector2(float(layout[0]), float(layout[1]))
	return center / uids.size()

func _distance(a: int, b: int) -> float:
	var p := _layout(a)
	var q := _layout(b)
	return Vector2(float(p[0]),float(p[1])).distance_to(Vector2(float(q[0]),float(q[1])))

func point(world: Vector3) -> Vector2:
	return board.get_node("%ArmySurface").global_position + board._screen_point(world)

func mouse(position: Vector2, button: int, pressed: bool, shift: bool = false, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	event.shift_pressed = shift
	event.double_click = double_click
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
	root.push_input(event, true)

func motion(position: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - _last_pointer
	event.button_mask = mask
	_last_pointer = position
	root.push_input(event, true)

func click(position: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false, double_click: bool = false) -> void:
	motion(position)
	mouse(position, button, true, shift, double_click)
	mouse(position, button, false, shift)
	await frames(4)

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)
	await frames(4)

func _capture(name: String) -> void:
	if not capture_enabled: return
	await create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/army_ui/%s.png" % name)
