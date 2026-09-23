class_name WarMapDefinition
extends Resource
## Authored map metadata shared by navigation, camera limits and the map picker.

@export var map_id := "rift"
@export var title := "裂谷交汇"
@export_enum("小", "中", "大") var size_class := 0
@export_range(1, 3) var team_size := 1
@export_file("*.tscn") var scene_path := "res://scenes/block_war/map.tscn"
@export_file("*.res") var routes_path := "res://data/block_war/routes/rift.res"
@export_multiline var description := "两道溪谷与四座石桥，围绕中央据点展开争夺。"
@export var half_size := Vector2(40, 28)
@export var ground_color := Color("799077")
@export var water_regions: Array[Rect2] = []
@export var mountain_regions: Array[Rect2] = []
@export var bridges: Array[Rect2] = []
@export var building_positions := PackedVector3Array()
@export var building_kinds := PackedInt32Array()
@export var building_factions := PackedInt32Array()

func is_walkable(point: Vector2) -> bool:
	if absf(point.x) > half_size.x or absf(point.y) > half_size.y:
		return false
	for bridge: Rect2 in bridges:
		if _inside(bridge, point):
			return true
	for region: Rect2 in water_regions:
		if _inside(region, point):
			return false
	for region: Rect2 in mountain_regions:
		if _inside(region, point):
			return false
	return true

func mode_label() -> String:
	return "%dv%d" % [team_size, team_size]

static func _inside(region: Rect2, point: Vector2) -> bool:
	return point.x > region.position.x and point.x < region.end.x and point.y > region.position.y and point.y < region.end.y
