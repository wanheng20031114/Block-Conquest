class_name WarSelectionMotionPreset
extends Resource
## Comparison data; candidate 01 shares its curve with the live building motion.

const FLAT: Curve = preload("res://tests/block_war_selection/presets/flat.tres")
@export var number := 1
@export var title := ""
@export var description := ""
@export var duration := 0.38
@export var stretch: Curve = FLAT
@export var lift: Curve = FLAT
@export var roll: Curve = FLAT
@export var yaw: Curve = FLAT
@export var pitch: Curve = FLAT
@export var upper: Curve = FLAT
