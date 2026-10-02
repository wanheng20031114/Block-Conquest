class_name CampaignStage
extends Resource
## Authored stops on the campaign atlas. Battle missions are a later milestone.

@export_range(1, 6) var number := 1
@export var title := ""
@export var region := ""
@export_multiline var description := ""
@export var atlas_position := Vector2.ZERO
