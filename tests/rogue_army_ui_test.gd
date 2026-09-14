extends SceneTree
## Bounded integration checks; the isolated checkpoint never touches a real run.
var failures: Array[String] = []
var checks := 0
var panel: RogueArmyPanel
var rogue: RogueSession
var capture_enabled := false

func _initialize() -> void:
	root.visible = false
	root.unfocusable = true
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	if capture_enabled:
		RenderingServer.viewport_set_update_mode(root.get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(50, true, false, true).timeout.connect(func() -> void: quit(3))
	DirAccess.make_dir_recursive_absolute("res://artifacts/rogue_army")
	rogue = root.get_node("Session").rogue
	rogue.save_path = "user://rogue_army_ui_test.json"
	check(rogue.state.start_new("range", "steady", 90256) == OK, "start deterministic army")
	rogue.state.data.bread = 50
	rogue.state.data.tickets[0].candidates = ["swordsman", "archer", "heavy_cannon"]
	var scene: PackedScene = load("res://scenes/rogue/army_panel.tscn")
	panel = scene.instantiate()
	root.add_child(panel)
	root.size = Vector2i(1280, 720)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.open_panel()
	await process_frame
	await process_frame
	check(panel.get_node("%ArmyRoster").item_count == rogue.state.data.roster.size(), "all roster entries appear")
	check(panel.get_node("%ArmyBoard")._models.size() == rogue.state.deployed_units().size(), "one authored model per deployed unit")
	var bounds: Rect2 = root.get_visible_rect()
	check(bounds.encloses(panel.get_node("%CloseArmy").get_global_rect()), "close action within 1280 viewport")
	check(panel.get_node("%ArmyBoard").size.x >= 450, "1280 layout leaves a useful model workspace")
	check(panel.get_node("%ArmyBoard").size.y >= 340, "formation workspace has useful height")
	await _capture("formation_1280")

	var selected_uid: int = int(rogue.state.data.roster[0].uid)
	var original: Array = rogue.state.data.roster[0].layouts.outpost.duplicate()
	panel._select_uid(selected_uid)
	panel._rotate_selected(15)
	check(is_equal_approx(float(rogue.state.data.roster[0].layouts.outpost[2]), wrapf(float(original[2]) + deg_to_rad(15), -PI, PI)), "rotation reaches persistent formation layout")
	var board: RogueArmyBoard = panel.get_node("%ArmyBoard")
	var siege_untouched: Array = rogue.state.data.roster[0].layouts.siege.duplicate()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = _board_position(board, Vector3(-5, 0, -7))
	board._on_surface_input(click)
	check(rogue.state.data.roster[0].layouts.outpost.slice(0, 2) == [-5.0, -7.0], "right click projects to the intended world position")
	click.button_index = MOUSE_BUTTON_LEFT
	board._on_surface_input(click)
	var drag := InputEventMouseMotion.new()
	drag.position = _board_position(board, Vector3(-6, 0, -6))
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	board._on_surface_input(drag)
	check(rogue.state.data.roster[0].layouts.outpost.slice(0, 2) == [-5.0, -7.0], "drag preview does not mutate saved formation")
	click.position = drag.position
	click.pressed = false
	board._on_surface_input(click)
	check(rogue.state.data.roster[0].layouts.outpost.slice(0, 2) == [-6.0, -6.0], "drag release commits the intended world position")
	check(rogue.state.data.roster[0].layouts.siege == siege_untouched, "editing outpost leaves siege layout independent")
	panel._on_map_selected(1)
	var siege_before: Array = rogue.state.data.roster[0].layouts.siege.duplicate()
	panel._save_layout(selected_uid, [0.0, 0.0, 0.0])
	check(rogue.state.data.roster[0].layouts.siege == siege_before, "central base collision rejects placement")
	check(not panel.get_node("%ArmyStatus").text.is_empty(), "placement error is visible")
	check(panel.get_node("%ArmyBoard").get_node("%ArmyFootprint").visible, "siege displays its real base exclusion zone")
	await _capture("siege_1280")

	var population_before: int = rogue.state.population()
	panel._toggle_deployed()
	check(not rogue.state.data.roster[0].deployed, "unit moves into reserve")
	check(rogue.state.population() < population_before, "reserves do not consume population")
	panel._toggle_deployed()
	check(rogue.state.data.roster[0].deployed, "reserve returns to formation")
	check(rogue.state.population() == population_before, "population is restored")
	check(FileAccess.file_exists(rogue.save_path), "formation edit creates isolated checkpoint")

	panel._change_tab("recruit")
	await process_frame
	check(panel.get_node("%ArmyCandidates").item_count == 3, "ticket presents exactly three fixed candidates")
	var bread_before: int = int(rogue.state.data.bread)
	var tickets_before: int = rogue.state.data.tickets.size()
	panel._cancel_recruit()
	check(rogue.state.data.bread == bread_before and rogue.state.data.tickets.size() == tickets_before, "cancel spends neither bread nor ticket")
	check(panel.get_node("%RecruitEmpty").visible, "cancel clears preview selection")
	panel._on_ticket_selected(0)
	panel._on_candidate_selected(1)
	panel.get_node("%Batches").value = 3
	var roster_before: int = rogue.state.data.roster.size()
	await _capture("recruit_1280")
	panel._confirm_recruit()
	check(rogue.state.data.roster.size() == roster_before + 9, "three archer batches recruit nine units")
	check(int(rogue.state.data.bread) == bread_before - 3, "three archer batches consume three bread")
	check(rogue.state.data.tickets.size() == tickets_before - 1, "recruit consumes exactly one ticket")
	check(rogue.state.population() == population_before, "new units remain in unlimited reserve")
	check(panel.get_node("%RecruitEmpty").visible, "last ticket leaves a usable empty state")
	var newly_deployed := 0
	var exceeded_rejected := false
	for unit: Dictionary in rogue.state.data.roster.slice(roster_before):
		if rogue.set_deployed(int(unit.uid), true) == OK:
			newly_deployed += 1
		else:
			exceeded_rejected = true
			break
	check(exceeded_rejected and rogue.state.population() == rogue.state.population_cap(), "full formation rejects excess population")
	panel._change_tab("formation")
	panel.get_node("%RosterFilter").select(2)
	panel._refresh_roster()
	check(panel.get_node("%ArmyRoster").item_count == 9 - newly_deployed, "reserve filter contains all undeployed recruits")
	var closed_count: Array[int] = [0]
	panel.closed.connect(func() -> void: closed_count[0] += 1)
	panel.close_panel()
	check(not panel.visible and closed_count[0] == 1, "close hides panel and emits one signal")
	check(panel.get_node("%ArmyBoard").get_node("%ArmyViewport").render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed preview stops rendering")

	panel.queue_free()
	await process_frame
	for suffix: String in ["", ".tmp"]:
		var path: String = ProjectSettings.globalize_path(rogue.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("ROGUE_ARMY_UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture(name: String) -> void:
	if not capture_enabled:
		return
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/rogue_army/%s.png" % name)

func _board_position(board: RogueArmyBoard, point: Vector3) -> Vector2:
	var camera: Camera3D = board.get_node("%ArmyCamera")
	var viewport: SubViewport = board.get_node("%ArmyViewport")
	var surface: TextureRect = board.get_node("%ArmySurface")
	return camera.unproject_position(point) / Vector2(viewport.size) * surface.size
