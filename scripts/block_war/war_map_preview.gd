extends Control
## A native tactical diagram, using the same terrain and spawn data as the scene.

const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
var definition: Resource

func show_map(value: Resource) -> void:
	definition = value
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	if definition == null:
		return
	var extent: Vector2 = definition.half_size * 2.0
	var scale_factor := minf((size.x - 48.0) / extent.x, (size.y - 48.0) / extent.y)
	var origin := (size - extent * scale_factor) * 0.5
	var bounds := Rect2(origin, extent * scale_factor)
	draw_rect(bounds.grow(10), Color("f2efdb"))
	draw_rect(bounds, definition.ground_color.lightened(0.48).lerp(Color("c6d1a6"), 0.55))
	for x: int in range(1, 8):
		var at := origin.x + bounds.size.x * x / 8.0
		draw_line(Vector2(at, origin.y), Vector2(at, bounds.end.y), Color(1, 1, 1, 0.12))
	for y: int in range(1, 8):
		var at := origin.y + bounds.size.y * y / 8.0
		draw_line(Vector2(origin.x, at), Vector2(bounds.end.x, at), Color(1, 1, 1, 0.12))
	for region: Rect2 in definition.water_regions:
		var rectangle := Rect2(origin + (region.position + definition.half_size) * scale_factor, region.size * scale_factor)
		draw_rect(rectangle.intersection(bounds), Color("81b4b5"))
	for region: Rect2 in definition.mountain_regions:
		var rectangle := Rect2(origin + (region.position + definition.half_size) * scale_factor, region.size * scale_factor)
		draw_rect(rectangle.intersection(bounds), Color("959b7d"))
		for i: int in 4:
			var at := rectangle.position + Vector2(rectangle.size.x * 0.5, rectangle.size.y * (i + 0.5) / 4.0)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-10, 8), at + Vector2(0, -9), at + Vector2(10, 8)]), Color("e0e0c2"))
	for region: Rect2 in definition.bridges:
		var rectangle := Rect2(origin + (region.position + definition.half_size) * scale_factor, region.size * scale_factor)
		draw_rect(rectangle.intersection(bounds), Color("ece0b1"))
	for i: int in definition.building_positions.size():
		var world: Vector3 = definition.building_positions[i]
		var at: Vector2 = origin + (Vector2(world.x, world.z) + definition.half_size) * scale_factor
		var faction: int = definition.building_factions[i]
		var color: Color = Color("e0e0ca") if faction < 0 else FACTIONS.COLORS[faction]
		var radius := 4.0 if faction < 0 else 8.0
		draw_circle(at + Vector2(0, 2), radius + 3.0, Color(0.29, 0.30, 0.22, 0.22), true, -1.0, true)
		draw_circle(at, radius + 2.0, Color("f9f4df"), true, -1.0, true)
		if definition.building_kinds[i] == 1:
			draw_rect(Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), color)
		elif definition.building_kinds[i] == 2:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -radius - 1), at + Vector2(radius + 1, 0), at + Vector2(0, radius + 1), at + Vector2(-radius - 1, 0)]), color)
		else:
			draw_circle(at, radius, color, true, -1.0, true)
		if faction == 0:
			draw_arc(at, 12.0, 0, TAU, 32, Color.WHITE, 1.5, true)
	draw_rect(bounds, Color("819571"), false, 1.5)
