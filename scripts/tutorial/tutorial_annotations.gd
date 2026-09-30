extends Control
## Six scene-authored labels identify the exact object being explained.
## Positions and targets use the tutorial overlay's viewport coordinates.

const SLOT_COUNT := 6
const MARGIN := 14.0
const GAP := 22.0

@onready var _slots: Array[Control] = [$Slot1, $Slot2, $Slot3, $Slot4, $Slot5, $Slot6]

var _items: Array[Dictionary] = []
var _rects: Array[Rect2] = []
var _lines: Array[PackedVector2Array] = []


func set_annotations(items: Array[Dictionary]) -> bool:
	assert(items.size() <= SLOT_COUNT, "Tutorial annotations exceed the authored slots")
	if items == _items:
		return false
	_items.assign(items.duplicate(true))
	for index: int in SLOT_COUNT:
		var slot := _slots[index]
		slot.visible = index < _items.size()
		if not slot.visible:
			continue
		var badge := bool(_items[index].get("badge", false))
		slot.get_node("Paper").visible = not badge
		slot.get_node("Badge").visible = badge
		slot.get_node("Text").text = str(_items[index]["text"])
	if _items.is_empty():
		_rects.clear()
		_lines.clear()
		queue_redraw()
	return true


func layout_annotations(viewport_size: Vector2, avoid: Array[Rect2]) -> void:
	_rects.clear()
	_lines.clear()
	var compact := viewport_size.x < 1150.0
	var bounds := Rect2(Vector2.ONE * MARGIN, (viewport_size - Vector2.ONE * MARGIN * 2.0).max(Vector2.ONE))
	for index: int in _items.size():
		var item := _items[index]
		var target: Rect2 = item["target"]
		var badge := bool(item.get("badge", false))
		var label: Label = _slots[index].get_node("Text")
		var font_size := (19 if compact else 21) if badge else (17 if compact else 19)
		label.add_theme_font_size_override("font_size", font_size)
		var text_size := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
		var label_size := Vector2(maxf(70.0, text_size.x + 28.0), 36.0 if compact else 40.0)
		if badge:
			label_size = Vector2.ONE * maxf(74.0 if compact else 82.0, text_size.x * 1.64)
		label_size = label_size.min(bounds.size)
		var occupied: Array[Rect2] = avoid.duplicate()
		occupied.append_array(_rects)
		var placed := _place_label(target, label_size, str(item.get("side", "auto")), bounds, occupied)
		_slots[index].position = placed.position
		_slots[index].size = placed.size
		_rects.append(placed)
		var tip := _edge_towards(target, placed.get_center())
		var start := _edge_towards(placed, target.get_center())
		# The four-petal silhouette has transparent corners; connect through its
		# center so the visible line always meets the porcelain, never empty UVs.
		if badge:
			start = placed.get_center()
		_lines.append(PackedVector2Array([start, tip]))
	queue_redraw()


func annotation_rects() -> Array[Rect2]:
	return _rects.duplicate()


func _place_label(target: Rect2, label_size: Vector2, side: String, bounds: Rect2, occupied: Array[Rect2]) -> Rect2:
	var sides: Array[String] = ["right", "left", "below", "above"]
	if side in sides:
		sides.erase(side)
		sides.push_front(side)
	var candidates: Array[Vector2] = []
	var preferences: Array[float] = []
	for direction: String in sides:
		var start_index := candidates.size()
		var centered := target.get_center() - label_size * 0.5
		if direction == "left" or direction == "right":
			centered.x = target.position.x - GAP - label_size.x if direction == "left" else target.end.x + GAP
			candidates.append(centered)
			candidates.append(Vector2(centered.x, target.position.y))
			candidates.append(Vector2(centered.x, target.end.y - label_size.y))
			# Slide along the same edge before abandoning an otherwise nearby
			# position when a panel or another annotation occupies the middle.
			for rect: Rect2 in occupied:
				candidates.append(Vector2(centered.x, rect.position.y - label_size.y - MARGIN))
				candidates.append(Vector2(centered.x, rect.end.y + MARGIN))
		else:
			centered.y = target.position.y - GAP - label_size.y if direction == "above" else target.end.y + GAP
			candidates.append(centered)
			candidates.append(Vector2(target.position.x, centered.y))
			candidates.append(Vector2(target.end.x - label_size.x, centered.y))
			for rect: Rect2 in occupied:
				candidates.append(Vector2(rect.position.x - label_size.x - MARGIN, centered.y))
				candidates.append(Vector2(rect.end.x + MARGIN, centered.y))
		for _index: int in range(start_index, candidates.size()):
			preferences.append(float(sides.find(direction)) * 100.0 if side != "auto" else 0.0)
	var best := Rect2(bounds.position, label_size)
	var best_overlap := INF
	var best_distance := INF
	for index: int in candidates.size():
		var position_on_screen := candidates[index].clamp(bounds.position, (bounds.end - label_size).max(bounds.position))
		var candidate := Rect2(position_on_screen, label_size)
		var overlap := 0.0
		for rect: Rect2 in occupied:
			overlap += candidate.grow(6.0).intersection(rect).get_area()
		for other: Dictionary in _items:
			var other_target: Rect2 = other["target"]
			overlap += candidate.intersection(other_target.grow(8.0)).get_area() * 3.0
		# Strictly prefer clear space, then proximity. The candidate index is a
		# deterministic tie-breaker so labels do not flip sides each frame.
		var distance := candidate.get_center().distance_to(target.get_center()) + preferences[index] + float(index) * 0.05
		if overlap < best_overlap or (is_equal_approx(overlap, best_overlap) and distance < best_distance):
			best = candidate
			best_overlap = overlap
			best_distance = distance
	return best


func _edge_towards(rect: Rect2, point: Vector2) -> Vector2:
	var center := rect.get_center()
	var delta := point - center
	if delta.length_squared() < 0.001:
		return center
	var horizontal := rect.size.x * 0.5 / absf(delta.x) if absf(delta.x) > 0.001 else INF
	var vertical := rect.size.y * 0.5 / absf(delta.y) if absf(delta.y) > 0.001 else INF
	return center + delta * minf(horizontal, vertical)


func _draw() -> void:
	for line: PackedVector2Array in _lines:
		draw_polyline(line, Color(0.10, 0.17, 0.11, 0.70), 4.0, true)
		draw_polyline(line, Color(0.98, 0.97, 0.87, 0.97), 1.6, true)
		draw_circle(line[1], 3.1, Color(0.98, 0.97, 0.87), true, -1.0, true)
