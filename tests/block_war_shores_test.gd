extends "res://tools/bake_block_war_shores.gd"
## Narrow coves must keep ordered bank layers and join their straight shores.

var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func _initialize() -> void:
	var bridges: Array[Rect2] = []
	for lake: Rect2 in [Rect2(), Rect2(-8, -11, 16, 22)]:
		for radius: float in [0.76, 1.52, 3.2]:
			for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
				var incoming := Vector2.RIGHT.rotated(angle)
				var outgoing := incoming.rotated(PI * 0.5)
				var corner := Vector2(8, 4)
				var first_normal := incoming.rotated(PI * 0.5)
				var last_normal := outgoing.rotated(PI * 0.5)
				var center := corner + (first_normal + last_normal) * radius
				for ratio: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var row := _convex_corner_row(corner, incoming, outgoing, radius, ratio, bridges, lake)
					var radial := (-first_normal).rotated(PI * 0.5 * ratio)
					var previous_radius := radius + 0.001
					for index: int in range(1, row.size()):
						var offset := Vector2(row[index].x, row[index].z) - center
						check(row[index].is_finite() and offset.dot(radial) > 0.0 and offset.length() < previous_radius,
							"bank layers stay ordered without crossing the small cove's center")
						previous_radius = offset.length()
					if ratio == 0.0 or ratio == 1.0:
						var point := corner - incoming * radius if ratio == 0.0 else corner + outgoing * radius
						var normal := first_normal if ratio == 0.0 else last_normal
						var straight := _straight_row(point, normal, bridges, lake, radius * 0.85)
						for band: int in row.size():
							check(row[band].distance_to(straight[band]) < 0.00001, "arc and straight bank meet at every grass and rock layer")
	print("BLOCK_WAR_SHORES checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
