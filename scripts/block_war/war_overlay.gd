extends Control
## Native canvas feedback projected from the 3D map; never intercepts input.

# Match the population badge's porcelain as it appears after world tonemapping.
const CLOUD_FILL := Color("edecec")
const CLOUD_EDGE_SPEED := 24.0 # UI pixels per second along the outline.

var _hint_time := 0.0
var _hint_rect := Rect2()

@onready var game: Node3D = get_parent().get_parent()
@onready var hint_label: Label = $DispatchText

func _process(delta: float) -> void:
	hint_label.visible = game._match_ready and game.drag_source != null and get_viewport().get_mouse_position().distance_to(game._drag_start) > 6.0
	if hint_label.visible:
		_hint_time += delta
		_update_dispatch_hint()
	else:
		_hint_time = 0.0

func _draw() -> void:
	if not game._match_ready:
		return
	var camera: Camera3D = game.camera
	if game.armed_skill == 3:
		var center: Vector3 = game.ground_skill_target
		if center.is_finite():
			var color := Color(1.0, 0.61, 0.25, 0.9) if game.can_cast_skill(3) else Color(0.9, 0.35, 0.27, 0.65)
			_ring(center, game.IMPACT_RADIUS, color, 2.5)
			var screen := camera.unproject_position(center + Vector3(0, 0.15, 0))
			draw_line(screen - Vector2(7, 0), screen + Vector2(7, 0), color, 1.5, true)
			draw_line(screen - Vector2(0, 7), screen + Vector2(0, 7), color, 1.5, true)
	elif game.armed_skill >= 0:
		var valid: bool = game.ground_skill_target.is_finite() if game.armed_skill == 1 else game._valid_skill_target(game.armed_skill, game.hovered)
		var reticle_color := Color(0.95, 0.85, 0.48, 0.9) if valid else Color(0.9, 0.93, 0.87, 0.7)
		var mouse := get_viewport().get_mouse_position()
		draw_arc(mouse, 13.0, 0, TAU, 32, reticle_color, 1.5, true)
		if valid and game.hovered != null:
			_ring(game.hovered.global_position, 3.4, reticle_color, 2.0)
	if game.selected != null and game.selected.kind == 1:
		_ring(game.selected.global_position, game.tower_range(game.selected), Color(1.0, 0.81, 0.43, 0.35), 1.5)
	for id: int in game.shields:
		var building: Node3D = game.by_id[id]
		_ring(building.global_position, 3.2, Color(0.47, 0.82, 1.0, 0.8), 3.0)
		_ring(building.global_position + Vector3(0, 2.8, 0), 2.6, Color(0.47, 0.82, 1.0, 0.3), 1.5)
	if game.drag_source != null and get_viewport().get_mouse_position().distance_to(game._drag_start) > 6.0:
		var points := PackedVector2Array()
		var color := Color(1.0, 0.81, 0.32, 0.9)
		if game.hovered != null and game.FACTIONS.allied(game.hovered.faction, 0):
			color = Color(0.55, 0.93, 0.7, 0.9)
		if game.order_route.size() >= 2:
			for point: Vector3 in game.order_route:
				points.append(camera.unproject_position(point + Vector3(0, 0.4, 0)))
		else:
			points.append(camera.unproject_position(game.drag_source.global_position + Vector3.UP))
			points.append(get_viewport().get_mouse_position())
		if points.size() >= 2:
			color.a = 0.75
			draw_polyline(points, color, 3.5, true)
			var end: Vector2 = points[-1]
			var direction: Vector2 = (end - points[-2]).normalized()
			var side := Vector2(-direction.y, direction.x)
			draw_polyline(PackedVector2Array([end - direction * 16 + side * 8, end, end - direction * 16 - side * 8]), color, 3.5, true)
		if hint_label.visible:
			_draw_dispatch_hint()
	for shot: Dictionary in game.projectiles:
		# The trail belongs to the actual 3D ball and its current live target.
		var at: Vector2 = camera.unproject_position(shot.position)
		var before: Vector2 = camera.unproject_position(shot.previous)
		draw_line(before, at, Color(1.0, 0.73, 0.32, 0.82), 2.8, true)
	for effect: Dictionary in game.effects:
		var progress: float = 1.0 - effect.life / effect.duration
		var color: Color = effect.color
		color.a = 1.0 - progress
		var radius: float = lerpf(0.5, effect.radius if effect.kind != "hit" else 0.85, progress)
		_ring(effect.at, radius, color, 2.5)

func _update_dispatch_hint() -> void:
	var count := floori(game.drag_source.population * game.percentage / 100.0)
	hint_label.text = str(count)
	var font := hint_label.get_theme_font("font")
	var font_size := hint_label.get_theme_font_size("font_size")
	var text_size := font.get_string_size(hint_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var extent := Vector2(maxf(72.0, ceilf(text_size.x) + 36.0), 50.0)
	var at := get_viewport().get_mouse_position() + Vector2(20.0, -extent.y - 12.0)
	at.x = clampf(at.x, 8.0, size.x - extent.x - 8.0)
	at.y = clampf(at.y, 8.0, size.y - extent.y - 10.0)
	_hint_rect = Rect2(at.round(), extent)
	# Native Label caches its glyphs independently of the animated background.
	hint_label.position = _hint_rect.position + Vector2(14.0, 2.0)
	hint_label.size = extent - Vector2(28.0, 2.0)

func _draw_dispatch_hint() -> void:
	var outline := _cloud_outline(_hint_rect)
	var shadow := PackedVector2Array()
	for point: Vector2 in outline:
		shadow.append(point + Vector2(0.0, 2.0))
	draw_colored_polygon(shadow, Color(0.10, 0.15, 0.12, 0.16))
	draw_colored_polygon(outline, CLOUD_FILL)
	outline.append(outline[0])
	draw_polyline(outline, CLOUD_FILL, 1.0, true)

func _cloud_outline(rect: Rect2) -> PackedVector2Array:
	var profile := _cloud_profile(rect.size)
	var distances := PackedFloat32Array([0.0])
	for index: int in profile.size():
		distances.append(distances[-1] + profile[index].distance_to(profile[(index + 1) % profile.size()]))
	var perimeter := distances[-1]
	var outline := PackedVector2Array()
	for index: int in profile.size():
		var tangent := (profile[(index + 1) % profile.size()] - profile[posmod(index - 1, profile.size())]).normalized()
		var normal := Vector2(tangent.y, -tangent.x)
		# One broad, 1 px deformation travels in one direction at constant arc
		# speed. The phase has no easing, reversals, stops or extra small ripples.
		var drift := sin(TAU * (distances[index] - _hint_time * CLOUD_EDGE_SPEED) / perimeter)
		outline.append(rect.position + profile[index] + normal * drift)
	return outline

func _cloud_profile(extent: Vector2) -> PackedVector2Array:
	var width := extent.x
	var height := extent.y
	# Three generous cloud lobes: a broad crown, two lower shoulders and one
	# rounded underside. Shared tangents soften the shallow joins between lobes.
	var anchors := PackedVector2Array([
		Vector2(1.5, height * 0.63), Vector2(width * 0.18, height * 0.24),
		Vector2(width * 0.29, height * 0.29), Vector2(width * 0.49, 1.5),
		Vector2(width * 0.71, height * 0.29), Vector2(width * 0.82, height * 0.23),
		Vector2(width - 1.5, height * 0.60), Vector2(width * 0.53, height - 1.5),
	])
	var tangents := PackedVector2Array([
		Vector2(0, -height * 0.25), Vector2(width * 0.08, 0),
		Vector2(width * 0.04, 0), Vector2(width * 0.13, 0),
		Vector2(width * 0.04, 0), Vector2(width * 0.08, 0),
		Vector2(0, height * 0.25), Vector2(-width * 0.32, 0),
	])
	var points := PackedVector2Array()
	for arc: int in anchors.size():
		var next := (arc + 1) % anchors.size()
		for step: int in 16:
			points.append(anchors[arc].bezier_interpolate(anchors[arc] + tangents[arc], anchors[next] - tangents[next], anchors[next], step / 16.0))
	return points

func _ring(center: Vector3, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index: int in 65:
		var angle: float = index * TAU / 64.0
		points.append(game.camera.unproject_position(center + Vector3(cos(angle) * radius, 0.15, sin(angle) * radius)))
	draw_polyline(points, color, width, true)
