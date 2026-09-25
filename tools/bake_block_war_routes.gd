extends SceneTree
## Bake after changing map layouts, scenery or route-clearance rules.
## Godot --headless --path . --script res://tools/bake_block_war_routes.gd

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const ROUTES := preload("res://scripts/block_war/war_map_routes.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/block_war/routes")
	for definition: Resource in CATALOG.MAPS:
		var arguments := OS.get_cmdline_user_args()
		if not arguments.is_empty() and definition.map_id not in arguments:
			continue
		var started := Time.get_ticks_msec()
		var map: WarMap = load(definition.scene_path).instantiate()
		map.bake_routes = true
		root.add_child(map)
		var buildings := map.get_node("Buildings").get_children()
		for i: int in buildings.size():
			for j: int in range(i + 1, buildings.size()):
				var route := map.get_building_route(buildings[i], buildings[j])
				if route.size() < 2:
					printerr("No safe route: ", definition.map_id, " ", i, " -> ", j)
					map.queue_free()
					quit(1)
					return
		var saved := ROUTES.new()
		saved.routes = map._route_cache
		saved.distances = map._route_distances
		var error := ResourceSaver.save(saved, definition.routes_path, ResourceSaver.FLAG_COMPRESS)
		assert(error == OK, "Route resource must be saved before running a match.")
		print("ROUTES_BAKED ", definition.map_id, " pairs=", saved.routes.size(), " ms=", Time.get_ticks_msec() - started)
		map.queue_free()
		await process_frame
	quit()
