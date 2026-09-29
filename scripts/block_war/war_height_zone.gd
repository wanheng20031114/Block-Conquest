class_name WarHeightZone
extends Resource
## One authored plateau or straight ramp; terrain has one walkable surface per X/Z.

@export var region := Rect2(0, 0, 1, 1)
@export var start_height := 0.0
@export var end_height := 0.0
@export_enum("X", "Z") var axis := 0

func contains(point: Vector2) -> bool:
	# Include shared edges: adjoining ramps/plateaus must meet at the same height.
	return point.x >= region.position.x and point.x <= region.end.x and point.y >= region.position.y and point.y <= region.end.y

func gradient() -> float:
	var span := region.size.x if axis == 0 else region.size.y
	assert(span > 0.0, "A height zone needs a positive extent along its ramp axis.")
	return (end_height - start_height) / span

func height_at(point: Vector2) -> float:
	var coordinate := point.x - region.position.x if axis == 0 else point.y - region.position.y
	var span := region.size.x if axis == 0 else region.size.y
	return lerpf(start_height, end_height, clampf(coordinate / span, 0.0, 1.0))

func surface_plane() -> Plane:
	var slope := gradient()
	var normal := Vector3(-slope, 1.0, 0.0) if axis == 0 else Vector3(0.0, 1.0, -slope)
	normal = normal.normalized()
	return Plane(normal, normal.dot(Vector3(region.position.x, start_height, region.position.y)))
