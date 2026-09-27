extends SceneTree
## Native picker input, readable map geometry and hover inspection at desktop sizes.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const PREVIEW := preload("res://scripts/block_war/war_map_preview.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _settle() -> void:
	for frame: int in 6:
		await process_frame

func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func _run() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func(): quit(3))
	_check_shorelines()
	var capture := OS.get_cmdline_user_args().has("--capture")
	var capture_directory := "res://artifacts/block_war_maps_preview"
	if capture:
		for argument: String in OS.get_cmdline_user_args():
			if argument.is_empty() or argument.begins_with("--"):
				continue
			capture_directory = argument if argument.is_absolute_path() else "res://" + argument
			break
		var directory_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_directory))
		check(directory_result == OK, "screenshot output directory can be created: %s" % capture_directory)
		if directory_result != OK:
			quit(1)
			return
	var session := root.get_node("Session")
	var remembered: String = session.block_war_map_id
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	var picker := current_scene
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = resolution
		await _settle()
		for index: int in CATALOG.MAPS.size():
			var definition: Resource = CATALOG.MAPS[index]
			_click(picker.get_node("%%Size%d" % definition.size_class))
			_click(picker.get_node("%%Map%d" % (index % 2)))
			await _settle()
			var preview: Control = picker.get_node("%Preview")
			check(picker.selected == definition and preview.definition == definition, "native clicks show %s at %s" % [definition.map_id, resolution])
			check(picker.get_node("%MapInfo").text.contains("%d × %d" % [definition.half_size.x * 2, definition.half_size.y * 2]), "dimensions follow the playable map")
			var bounds: Rect2 = preview.map_rect()
			check(is_equal_approx(bounds.size.x / bounds.size.y, definition.half_size.x / definition.half_size.y), "terrain retains its real aspect ratio")
			check(Rect2(Vector2.ZERO, preview.size).encloses(bounds.grow(12)), "map frame fits the preview")
			for node_name: String in ["Preview", "MapName", "MapInfo", "Inspection", "SpawnLegend", "Description", "Teams", "Start", "OpponentCommander3"]:
				var control: Control = picker.get_node("%" + node_name)
				check(picker.get_global_rect().encloses(control.get_global_rect()), "%s stays inside the viewport" % node_name)
			for building: int in definition.building_positions.size():
				check(bounds.has_point(preview.building_screen_position(building)), "every real building lies inside the preview")
			_move(preview.global_position + preview.building_screen_position(0))
			await _settle()
			check(preview.hovered_building == 0 and picker.get_node("%Inspection").text.contains("出生据点"), "native hover inspects the player's actual spawn")
			var neutral_index: int = definition.building_factions.find(-1)
			_move(preview.global_position + preview.building_screen_position(neutral_index))
			await _settle()
			check(preview.hovered_building == neutral_index and picker.get_node("%Inspection").text.contains("中立"), "neutral hover shows its actual ownership")
			_move(picker.get_node("%Back").get_global_rect().get_center())
			await _settle()
			check(preview.hovered_building == -1 and picker.get_node("%Inspection").text.contains("悬停"), "leaving the map clears the last inspection")
			if capture:
				await RenderingServer.frame_post_draw
				var output_path := capture_directory.path_join("%s-%d.png" % [definition.map_id, resolution.x])
				check(root.get_texture().get_image().save_png(output_path) == OK, "screenshot saved: %s" % output_path)
	session.block_war_map_id = remembered
	print("BLOCK_WAR_MAP_PREVIEW checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_shorelines() -> void:
	var regions: Array[Rect2] = [Rect2(0, 0, 30, 10), Rect2(0, 10, 10, 10), Rect2(20, 10, 10, 10), Rect2(0, 20, 30, 10), Rect2(25, 5, 15, 8)]
	var edges: Array[PackedVector2Array] = PREVIEW._shore_edges(regions)
	var island_edges := 0
	for edge: PackedVector2Array in edges:
		for i: int in edge.size() - 1:
			var middle := (edge[i] + edge[i + 1]) * 0.5
			var normal := (edge[i + 1] - edge[i]).normalized().orthogonal() * 0.1
			var side_a := false
			var side_b := false
			for region: Rect2 in regions:
				side_a = side_a or region.has_point(middle + normal)
				side_b = side_b or region.has_point(middle - normal)
			check(side_a != side_b, "water outlines only separate land and water, including adjacent/overlapping regions")
			if Rect2(9.9, 9.9, 10.2, 10.2).has_point(middle):
				island_edges += 1
	check(island_edges >= 4, "shoreline clipping retains all sides of an island hole")
