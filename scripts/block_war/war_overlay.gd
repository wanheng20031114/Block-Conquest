extends Control
## Native canvas feedback projected from the 3D map; never intercepts input.

# Match the population badge's porcelain as it appears after world tonemapping.
const CLOUD_FILL := Color("edecec")
const CLOUD_EDGE_SPEED := 24.0 # UI pixels per second along the outline.
const ADVANTAGE_COLOR := Color("38a9dd")
const DISADVANTAGE_COLOR := Color("d85b52")

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
	if game.skill_is_ground(game.armed_skill):
		var center: Vector3 = game.ground_skill_target
		if center.is_finite():
			var haste: bool = game.faction_skills[0].commander == game.SKILL_RULES.RABBIT or game.armed_skill == 1
			var color := Color(0.65, 0.94, 0.8, 0.9) if haste else Color(1.0, 0.61, 0.25, 0.9)
			if not game.can_cast_skill(game.armed_skill):
				color = Color(0.9, 0.35, 0.27, 0.65)
			_ring(center, game.skill_radius(game.armed_skill), color, 2.5)
			var screen := camera.unproject_position(center + Vector3(0, 0.15, 0))
			draw_line(screen - Vector2(7, 0), screen + Vector2(7, 0), color, 1.5, true)
			draw_line(screen - Vector2(0, 7), screen + Vector2(0, 7), color, 1.5, true)
	elif game.armed_skill >= 0:
		var valid: bool
		if game.faction_skills[0].commander == game.SKILL_RULES.RABBIT and game.armed_skill in [2, 3]:
			valid = not game.recall_preview.is_empty() if game.armed_skill == 2 else not game.rabbit_preview.is_empty()
		else:
			valid = game._valid_skill_target(game.armed_skill, game.hovered)
		var reticle_color := Color(0.95, 0.85, 0.48, 0.9) if valid else Color(0.9, 0.93, 0.87, 0.7)
		var mouse := get_viewport().get_mouse_position()
		draw_arc(mouse, 13.0, 0, TAU, 32, reticle_color, 1.5, true)
		if valid and game.hovered != null:
			_ring(game.hovered.global_position, 3.4, reticle_color, 2.0)
		if game.faction_skills[0].commander == game.SKILL_RULES.RABBIT:
			_draw_rabbit_preview(camera)
	if game.selected != null and game.selected.kind == 1:
		_ring(game.selected.global_position, game.tower_range(game.selected), Color(1.0, 0.81, 0.43, 0.35), 1.5)
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

func _draw_rabbit_preview(camera: Camera3D) -> void:
	var color := Color(0.58, 0.87, 0.70, 0.85)
	if game.armed_skill == 2 and game.hovered != null:
		_ring(game.hovered.global_position, game.SKILL_RULES.RECALL_RADIUS, color, 1.4)
		for plan: Dictionary in game.recall_preview:
			_draw_world_path(plan.route, color)
		_draw_skill_number(game.recall_preview.size(), camera.unproject_position(game.hovered.global_position + Vector3(3, 1, 0)))
	elif game.armed_skill == 3 and not game.rabbit_preview.is_empty():
		var plan: Dictionary = game.rabbit_preview
		_ring(plan.entrance, 1.0, color, 2.0)
		_ring(plan.exit, 1.15, color, 2.0)
		_draw_world_path(plan.route, color)
		draw_dashed_line(camera.unproject_position(plan.entrance + Vector3.UP * 0.1), camera.unproject_position(plan.exit + Vector3.UP * 0.1), Color(color, 0.5), 1.5, 7.0, true)
		_draw_skill_number(plan.count, camera.unproject_position(plan.exit + Vector3(0, 1.5, 0)))

func _draw_world_path(route: PackedVector3Array, color: Color) -> void:
	var points := PackedVector2Array()
	for point: Vector3 in route:
		points.append(game.camera.unproject_position(point + Vector3.UP * 0.15))
	if points.size() >= 2:
		draw_polyline(points, color, 1.7, true)

func _draw_skill_number(count: int, at: Vector2) -> void:
	var font := hint_label.get_theme_font("font")
	var value := str(count)
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var rect := Rect2(at - Vector2(width * 0.5 + 10, 24), Vector2(width + 20, 34))
	draw_colored_polygon(_cloud_outline(rect), CLOUD_FILL)
	draw_string(font, at - Vector2(width * 0.5, -2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("34382e"))

func _draw_dispatch_hint() -> void:
	var outline := _cloud_outline(_hint_rect)
	var shadow := PackedVector2Array()
	for point: Vector2 in outline:
		shadow.append(point + Vector2(0.0, 2.0))
	draw_colored_polygon(shadow, Color(0.10, 0.15, 0.12, 0.16))
	draw_colored_polygon(outline, CLOUD_FILL)
	outline.append(outline[0])
	draw_polyline(outline, CLOUD_FILL, 1.0, true)
	var advantage := dispatch_advantage()
	if advantage == 0:
		return
	var color := ADVANTAGE_COLOR if advantage > 0 else DISADVANTAGE_COLOR
	var tip := -4.0 if advantage > 0 else 4.0
	# A small corner annotation; the cached number and cloud keep their layout
	# when the target's coefficient changes or returns to an even exchange.
	for index: int in absi(advantage):
		var at := _hint_rect.end - Vector2(12.0, 13.0 + index * 5.0)
		if advantage < 0:
			at.y -= 4.0
		draw_polyline(PackedVector2Array([at + Vector2(-4, 0), at + Vector2(0, tip), at + Vector2(4, 0)]), color, 2.0, true)

func dispatch_advantage() -> int:
	if game.drag_source == null or game.hovered == null or game.FACTIONS.allied(game.drag_source.faction, game.hovered.faction):
		return 0
	# Integer percentage points avoid floating-point noise at 100/120/140%.
	var difference := roundi((game.combat_multiplier(game.drag_source.faction, game.hovered) - 1.0) * 100.0)
	return signi(difference) * ceili(absi(difference) / 20.0)

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
