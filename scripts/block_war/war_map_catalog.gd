extends RefCounted

const MAPS: Array[Resource] = [
	preload("res://data/block_war/maps/rift.tres"),
	preload("res://data/block_war/maps/lake.tres"),
	preload("res://data/block_war/maps/rivers.tres"),
	preload("res://data/block_war/maps/ridges.tres"),
	preload("res://data/block_war/maps/islands.tres"),
	preload("res://data/block_war/maps/highland.tres"),
]

static func find_map(map_id: String) -> Resource:
	for definition: Resource in MAPS:
		if definition.map_id == map_id:
			return definition
	return null
