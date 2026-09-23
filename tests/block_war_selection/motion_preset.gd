class_name WarSelectionMotionPreset
extends Resource
## Preview-only motion data. No candidate is wired into gameplay yet.

const FLAT: Curve = preload("res://tests/block_war_selection/presets/flat.tres")
@export var number := 1
@export var title := ""
@export var description := ""
@export var duration := 0.54
@export var stretch: Curve = FLAT
@export var lift: Curve = FLAT
@export var roll: Curve = FLAT
@export var yaw: Curve = FLAT
@export var pitch: Curve = FLAT
@export var upper: Curve = FLAT
