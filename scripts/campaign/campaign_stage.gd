class_name CampaignStage
extends Resource
## Each authored railway station opens one fixed battlefield.

@export_range(1, 6) var number := 1
@export var title := ""
@export var region := ""
@export_multiline var description := ""
@export var map_id := "rift"
@export var opponent_commander: StringName = &"squirrel"
