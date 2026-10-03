extends "res://tools/bake_block_war_heights.gd"
## Native offline bake for this battlefield; never rewrites another map.

func _initialize() -> void:
	_bake("forest_fork")
	_bake_routes.call_deferred()

func _bake_routes() -> void:
	var map: WarMap = load("res://scenes/block_war/maps/forest_fork.tscn").instantiate()
	map.bake_routes = true
	root.add_child(map)
	var buildings := map.get_node("Buildings").get_children()
	for first: int in buildings.size():
		for second: int in range(first + 1, buildings.size()):
			var route := map.get_building_route(buildings[first], buildings[second])
			if route.size() < 2:
				printerr("FOREST_NO_ROUTE ", first, " -> ", second)
				map.free()
				quit(1)
				return
		print("FOREST_ROUTES source=", first, " pairs=", map._route_cache.size())
	var routes := preload("res://scripts/block_war/war_map_routes.gd").new()
	routes.routes = map._route_cache
	routes.distances = map._route_distances
	assert(ResourceSaver.save(routes, "res://data/block_war/routes/forest_fork.res", ResourceSaver.FLAG_COMPRESS) == OK)
	print("FOREST_BAKED buildings=", buildings.size(), " pairs=", routes.routes.size())
	map.free()
	quit()
