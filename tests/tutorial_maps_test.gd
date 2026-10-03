extends SceneTree
## Repeatable acceptance of the eleven authored practice grounds. Load each
## native scene, validate every directed building route, and save its overview.
## Run on the private-desktop renderer; an optional first argument selects the
## screenshot directory. The fixture never opens or simulates a player battle.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
var route_checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func(): quit(3))
	root.gui_disable_input = true
	change_scene_to_file("res://tests/tutorial_maps_review.tscn")
	await scene_changed
	var studio: Node3D = current_scene
	var output := "res://.local/tutorial/maps-review"
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	for lesson: String in CATALOG.IDS:
		var packed: PackedScene = load("res://scenes/tutorial/maps/%s.tscn" % lesson)
		assert(packed != null)
		var map: WarMap = packed.instantiate()
		studio.add_child(map)
		assert(map.bake_routes)
		assert(map.definition.half_size == Vector2(32, 24))
		assert(map.definition.camera_bounds == Rect2(-64, -54, 128, 108))
		var ids := []
		for building: WarBuilding in map.get_node("Buildings").get_children():
			assert(building.building_id not in ids)
			ids.append(building.building_id)
			assert(map.is_walkable(building.position))
			for target: WarBuilding in map.get_node("Buildings").get_children():
				if building == target: continue
				var route: PackedVector3Array = map.get_building_route(building, target)
				assert(route.size() >= 2, "%s %d to %d" % [lesson, building.building_id, target.building_id])
				assert(is_finite(map.get_building_distance(building, target)))
				for point: Vector3 in route:
					assert(map.is_walkable(point))
				route_checks += 1
		for frame: int in 6: await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output.path_join(lesson + ".png")) == OK)
		print("TUTORIAL_MAP ", lesson, " buildings=", ids.size(), " render=true routes=true")
		map.queue_free()
		await process_frame
	print("TUTORIAL_MAPS_TEST maps=", CATALOG.IDS.size(), " directed_routes=", route_checks)
	quit()
