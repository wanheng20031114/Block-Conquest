class_name BuildingWeaponState
extends RefCounted
## Authority-owned state; replacing a target never resets this gun's reload.
var target: Node3D
var cooldown: float = 1.0
var last_fired: float = -1.0
