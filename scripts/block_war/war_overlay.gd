extends Control
## Native canvas feedback projected from the 3D map; never intercepts input.

const DISPATCH_HINT: StyleBox = preload("res://assets/ui/block_war/dispatch_hint.tres")

@onready var game: Node3D = get_parent().get_parent()

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
		var count := floori(game.drag_source.population * game.percentage / 100.0)
		var verb := "增援" if game.hovered != null and game.FACTIONS.allied(game.hovered.faction, 0) else "进攻"
		var label := "%s %d 人 · %d%%" % [verb, count, game.percentage]
		if game.hovered != null and game.hovered.faction != 0 and game.FACTIONS.allied(game.hovered.faction, 0):
			label += " · 抵达后归队友"
		var font: Font = ThemeDB.fallback_font
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
		var at := get_viewport().get_mouse_position() + Vector2(20, -24)
		at.x = clampf(at.x, 8.0, size.x - text_size.x - 20.0)
		at.y = clampf(at.y, text_size.y + 8.0, size.y - 8.0)
		draw_style_box(DISPATCH_HINT, Rect2(at - Vector2(9, text_size.y), text_size + Vector2(18, 8)))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)
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

func _ring(center: Vector3, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index: int in 65:
		var angle: float = index * TAU / 64.0
		points.append(game.camera.unproject_position(center + Vector3(cos(angle) * radius, 0.15, sin(angle) * radius)))
	draw_polyline(points, color, width, true)
