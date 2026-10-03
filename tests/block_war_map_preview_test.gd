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
	create_timer(75.0, true, false, true).timeout.connect(func(): quit(3))
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
	var requested_maps := PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):
			requested_maps.append(argument.trim_prefix("--map="))
	change_scene_to_file("res://scenes/block_war/map_select.tscn")
	await scene_changed
	var picker := current_scene
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = resolution
		await _settle()
		for index: int in CATALOG.MAPS.size():
			var definition: Resource = CATALOG.MAPS[index]
			if not requested_maps.is_empty() and definition.map_id not in requested_maps:
				continue
			var size_maps: Array[Resource] = []
			for candidate: Resource in CATALOG.MAPS:
				if candidate.size_class == definition.size_class:
					size_maps.append(candidate)
			_click(picker.get_node("%%Size%d" % definition.size_class))
			_click(picker.get_node("%%Map%d" % size_maps.find(definition)))
			await _settle()
			var preview: Control = picker.get_node("%Preview")
			check(picker.selected == definition and preview.definition == definition, "native clicks show %s at %s" % [definition.map_id, resolution])
			check(picker.get_node("%MapInfo").text.contains("%d × %d" % [definition.half_size.x * 2, definition.half_size.y * 2]), "dimensions follow the playable map")
			var bounds: Rect2 = preview.map_rect()
			check(is_equal_approx(bounds.size.x / bounds.size.y, definition.half_size.x / definition.half_size.y), "terrain retains its real aspect ratio")
			check(Rect2(Vector2.ZERO, preview.size).encloses(bounds.grow(12)), "map frame fits the preview")
			for node_name: String in ["Preview", "MapName", "MapInfo", "Inspection", "SpawnLegend", "Description", "Teams", "Start", "OpponentCommander3", "Map0", "Map1", "Map2"]:
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
			if definition.has_elevation():
				await _check_height_preview(picker, preview, definition)
			_move(picker.get_node("%Back").get_global_rect().get_center())
			await _settle()
			check(preview.hovered_building == -1 and not preview.hovered_terrain and picker.get_node("%Inspection").text.contains("悬停"), "leaving the map clears the last building or terrain inspection")
			if capture:
				await RenderingServer.frame_post_draw
				var output_path := capture_directory.path_join("%s-%d.png" % [definition.map_id, resolution.x])
				check(root.get_texture().get_image().save_png(output_path) == OK, "screenshot saved: %s" % output_path)
	session.block_war_map_id = remembered
	print("BLOCK_WAR_MAP_PREVIEW checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_height_preview(picker: Control, preview: Control, definition: Resource) -> void:
	var bounds: Rect2 = preview.map_rect()
	var surface: WarTerrainSurface = definition.terrain
	check(surface.preview_texture.get_size() == Vector2(surface.width, surface.depth), "%s preview uses the same complete height grid" % definition.map_id)
	check(surface.bounds().encloses(Rect2(-definition.half_size, definition.half_size * 2.0)), "height texture covers the playable crop")
	for guide: Vector4 in surface.ramp_guides:
		check(surface.sample(Vector2(guide.z, guide.w)) > surface.sample(Vector2(guide.x, guide.y)), "preview ramp arrow points uphill on the actual ground")
	for terrain_name: String in ["台地", "土坡", "陡崖"]:
		var sample := _terrain_sample(preview, definition, terrain_name)
		check(sample.is_finite(), "%s has an inspectable %s outside building hit areas" % [definition.map_id, terrain_name])
		if not sample.is_finite():
			continue
		var pointer := {"at": Vector2.INF}
		var capture_pointer := func(event: InputEvent) -> void:
			if event is InputEventMouseMotion:
				pointer.at = event.position
		preview.gui_input.connect(capture_pointer)
		_move((preview.global_position + sample).round())
		await _settle()
		preview.gui_input.disconnect(capture_pointer)
		var text: String = picker.get_node("%Inspection").text
		check(preview.hovered_building == -1 and preview.hovered_terrain, "native terrain hover inspects the continuous heightfield")
		# Native input uses viewport pixels; derive the expected elevation from
		# the delivered GUI event rather than the ideal fractional test sample.
		check(pointer.at.is_finite(), "native terrain hover delivers local pointer coordinates")
		var world: Vector2 = (pointer.at - bounds.position) * definition.half_size * 2.0 / bounds.size - definition.half_size
		var expected_height := _triangle_height(surface, world)
		var displayed_height := text.get_slice("海拔 ", 1).get_slice(" 米", 0).to_float()
		check(text.contains(terrain_name) and text.contains("海拔 ") and absf(displayed_height - expected_height) <= 0.051, "%s %s inspection reports actual pointer elevation %.3f: %s (requested %s, delivered %s)" % [definition.map_id, terrain_name, expected_height, text, sample, pointer.at])
	var elevated := -1
	for building: int in definition.building_positions.size():
		if definition.building_positions[building].y > 0.1:
			elevated = building
			break
	check(elevated >= 0, "%s has an actual elevated building to inspect" % definition.map_id)
	if elevated >= 0:
		_move(preview.global_position + preview.building_screen_position(elevated))
		await _settle()
		check(preview.hovered_building == elevated and not preview.hovered_terrain, "building inspection takes priority over the raised terrain beneath it")
		check(picker.get_node("%Inspection").text.contains("海拔 %.1f 米" % definition.building_positions[elevated].y), "elevated building inspection uses its authored Y coordinate")

func _terrain_sample(preview: Control, definition: Resource, wanted: String) -> Vector2:
	var bounds: Rect2 = preview.map_rect()
	# Search actual preview pixels, including curved cliff edges. Check the full
	# two-pixel neighborhood so input rounding cannot cross a triangle boundary.
	for y: int in range(ceili(bounds.position.y) + 2, floori(bounds.end.y) - 2, 2):
		for x: int in range(ceili(bounds.position.x) + 2, floori(bounds.end.x) - 2, 2):
			var screen := Vector2(x, y)
			var free := true
			for building: int in definition.building_positions.size():
				if screen.distance_to(preview.building_screen_position(building)) <= 24.0:
					free = false
					break
			if not free:
				continue
			for offset: Vector2 in [Vector2.ZERO, Vector2(-2, -2), Vector2(0, -2), Vector2(2, -2), Vector2(-2, 0), Vector2(2, 0), Vector2(-2, 2), Vector2(0, 2), Vector2(2, 2)]:
				var world: Vector2 = (screen + offset - bounds.position) * definition.half_size * 2.0 / bounds.size - definition.half_size
				var height: float = definition.surface_height(world)
				var gradient: float = definition.terrain.gradient_at(world).length()
				var category := "台地" if gradient <= 0.03 else ("土坡" if gradient <= 0.5001 else "陡崖")
				if height <= 0.1 or category != wanted:
					free = false
					break
			if free:
				return screen
	return Vector2.INF

func _triangle_height(surface: WarTerrainSurface, world: Vector2) -> float:
	# Reconstruct the selected mesh triangle as a plane; do not call the product
	# sampler or reuse its interpolation weights for the expected elevation.
	var grid := (world - surface.origin) / surface.cell_size
	var cell := Vector2i(mini(floori(grid.x), surface.width - 2), mini(floori(grid.y), surface.depth - 2))
	var corners: Array[Vector2i] = [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN]
	if grid.x - cell.x + grid.y - cell.y > 1.0:
		corners[0] = cell + Vector2i.ONE
	var points: Array[Vector3] = []
	for corner: Vector2i in corners:
		var xz := surface.origin + Vector2(corner) * surface.cell_size
		points.append(Vector3(xz.x, surface.heights[corner.y * surface.width + corner.x], xz.y))
	var normal := (points[1] - points[0]).cross(points[2] - points[0])
	return points[0].y - (normal.x * (world.x - points[0].x) + normal.z * (world.y - points[0].z)) / normal.y

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
