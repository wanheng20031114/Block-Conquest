extends RefCounted

const MAPS: Array[Resource] = [
	preload("res://data/block_war/maps/rift.tres"),
	preload("res://data/block_war/maps/lake.tres"),
	preload("res://data/block_war/maps/rivers.tres"),
	preload("res://data/block_war/maps/ridges.tres"),
	preload("res://data/block_war/maps/islands.tres"),
	preload("res://data/block_war/maps/highland.tres"),
	preload("res://data/block_war/maps/terraces.tres"),
	preload("res://data/block_war/maps/switchback.tres"),
	preload("res://data/block_war/maps/crown.tres"),
	preload("res://data/block_war/maps/flower_pool.tres"),
	preload("res://data/block_war/maps/forest_fork.tres"),
]

static func find_map(map_id: String) -> Resource:
	for definition: Resource in MAPS:
		if definition.map_id == map_id:
			return definition
	return null
