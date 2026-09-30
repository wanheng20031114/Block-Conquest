extends ColorRect
## Control's native hit test lets only the current exercise reach the HUD/world.
## https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-private-method-has-point

var interaction_regions: Array[Rect2] = []

func _has_point(point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return false
	for region: Rect2 in interaction_regions:
		if region.has_point(point):
			return false
	return true
