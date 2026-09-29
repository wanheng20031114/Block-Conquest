extends Control
## A map drawn from the same authored bounds, terrain and buildings as the battle.

signal inspected(text: String)

const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const KIND_NAMES: Array[String] = ["住宅", "炮塔", "铁匠铺"]
const INK := Color("344b43")
const PAPER := Color("eee8cf")
const DEFAULT_HINT := "悬停据点或地形查看详情 · 带编号的据点为各玩家出生点"
var definition: Resource
var hovered_building := -1
var hovered_terrain := false
var local_faction := 0
var seat_names: Dictionary = {}
var _paper := StyleBoxFlat.new()
var _shadow := StyleBoxFlat.new()
var _inspection_text := DEFAULT_HINT

func _ready() -> void:
	_paper.bg_color = PAPER
	_paper.set_corner_radius_all(9)
	_shadow.bg_color = Color(0, 0, 0, 0.13)
	_shadow.set_corner_radius_all(9)
	mouse_exited.connect(_clear_inspection)

func show_map(value: Resource) -> void:
	definition = value
	_clear_inspection()
	queue_redraw()

func map_rect() -> Rect2:
	var extent: Vector2 = definition.half_size * 2.0
	var available := (size - Vector2(72, 66)).max(Vector2.ONE)
	var factor := minf(available.x / extent.x, available.y / extent.y)
	return Rect2((size - extent * factor) * 0.5, extent * factor)

func building_screen_position(index: int) -> Vector2:
	var bounds := map_rect()
	var world: Vector3 = definition.building_positions[index]
	return bounds.position + (Vector2(world.x, world.z) + definition.half_size) * bounds.size / (definition.half_size * 2.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseMotion or definition == null:
		return
	var closest := -1
	var distance := 20.0
	for i: int in definition.building_positions.size():
		var candidate: float = event.position.distance_to(building_screen_position(i))
		if candidate < distance:
			distance = candidate
			closest = i
	var terrain_hover := false
	var inspection := DEFAULT_HINT
	if closest < 0:
		var bounds := map_rect()
		if bounds.has_point(event.position):
			var world: Vector2 = (event.position - bounds.position) * definition.half_size * 2.0 / bounds.size - definition.half_size
			if definition.has_elevation():
				var height: float = definition.surface_height(world)
				if height > 0.05:
					var gradient: float = definition.terrain.gradient_at(world).length()
					var terrain_name := "台地" if gradient <= 0.03 else "土坡"
					if gradient > WarMapDefinition.MAX_WALKABLE_GRADIENT + WarTerrainSurface.HEIGHT_EPSILON:
						terrain_name = "陡崖"
					terrain_hover = true
					inspection = "%s · 海拔 %.1f 米" % [terrain_name, height]
	else:
		var faction: int = definition.building_factions[closest]
		var owner_name: String = "中立" if faction < 0 else str(seat_names.get(faction, FACTIONS.NAMES[faction]))
		inspection = "%s · %s%s" % [owner_name, KIND_NAMES[definition.building_kinds[closest]], " · 出生据点" if faction >= 0 else " · 可争夺"]
		if definition.has_elevation():
			inspection += " · 海拔 %.1f 米" % definition.building_positions[closest].y
	if closest == hovered_building and terrain_hover == hovered_terrain and inspection == _inspection_text:
		return
	hovered_building = closest
	hovered_terrain = terrain_hover
	_inspection_text = inspection
	inspected.emit(inspection)
	queue_redraw()

func _clear_inspection() -> void:
	hovered_building = -1
	hovered_terrain = false
	_inspection_text = DEFAULT_HINT
	inspected.emit(DEFAULT_HINT)
	queue_redraw()

func _region_rect(region: Rect2, bounds: Rect2) -> Rect2:
	var factor: Vector2 = bounds.size / (definition.half_size * 2.0)
	return Rect2(bounds.position + (region.position + definition.half_size) * factor, region.size * factor).intersection(bounds)

func _draw() -> void:
	if definition == null:
		return
	var bounds := map_rect()
	draw_style_box(_shadow, Rect2(bounds.position + Vector2(0, 7), bounds.size).grow(13))
	draw_style_box(_paper, bounds.grow(12))
	var ground: Color = definition.ground_color.lerp(Color("c5cd9e"), 0.78)
	draw_rect(bounds, ground)
	if definition.has_elevation():
		_draw_terrain(bounds)
	# Grid spacing is in world metres and stays inside the playable rectangle.
	var factor: float = bounds.size.x / (definition.half_size.x * 2.0)
	for x: int in range(int(ceil(-definition.half_size.x / 10.0)), int(ceil(definition.half_size.x / 10.0))):
		var at: float = bounds.position.x + (x * 10.0 + definition.half_size.x) * factor
		draw_line(Vector2(at, bounds.position.y), Vector2(at, bounds.end.y), Color(0.23, 0.34, 0.25, 0.10))
	for y: int in range(int(ceil(-definition.half_size.y / 10.0)), int(ceil(definition.half_size.y / 10.0))):
		var at: float = bounds.position.y + (y * 10.0 + definition.half_size.y) * factor
		draw_line(Vector2(bounds.position.x, at), Vector2(bounds.end.x, at), Color(0.23, 0.34, 0.25, 0.10))
	var water: Array[Rect2] = []
	for region: Rect2 in definition.water_regions:
		var rectangle := _region_rect(region, bounds)
		if rectangle.has_area():
			water.append(rectangle)
			_draw_water(rectangle)
	_draw_shores(water)
	for region: Rect2 in definition.mountain_regions:
		_draw_mountain(_region_rect(region, bounds))
	for region: Rect2 in definition.bridges:
		_draw_bridge(_region_rect(region, bounds))
	draw_rect(bounds, Color("879879"), false, 1.0)
	_draw_coordinates(bounds, factor)
	for i: int in definition.building_positions.size():
		_draw_building(i)

func _draw_terrain(bounds: Rect2) -> void:
	var surface: WarTerrainSurface = definition.terrain
	var playable := Rect2(-definition.half_size, definition.half_size * 2.0)
	# The preview uses the same vertex grid as the world. Pixel centers are the
	# authored sample positions; camera-only terrain is cropped out of the map.
	var source := Rect2((playable.position - surface.origin) / surface.cell_size + Vector2(0.5, 0.5), playable.size / surface.cell_size)
	draw_texture_rect_region(surface.preview_texture, bounds, source)
	var factor: Vector2 = bounds.size / playable.size
	for guide: Vector4 in surface.ramp_guides:
		var uphill_start := Vector2(guide.x, guide.y)
		var uphill_end := Vector2(guide.z, guide.w)
		if not playable.has_point(uphill_start) or not playable.has_point(uphill_end):
			continue
		var start := bounds.position + (uphill_start - playable.position) * factor
		var tip := bounds.position + (uphill_end - playable.position) * factor
		var direction := (tip - start).normalized()
		var head := minf(5.0, start.distance_to(tip) * 0.28)
		var side := direction.orthogonal()
		draw_line(start, tip, INK, 1.6, true)
		draw_line(tip, tip - direction * head + side * head * 0.65, INK, 1.6, true)
		draw_line(tip, tip - direction * head - side * head * 0.65, INK, 1.6, true)
	for label: Vector3 in surface.label_positions:
		var world := Vector2(label.x, label.z)
		if not playable.has_point(world):
			continue
		var at := bounds.position + (world - playable.position) * factor + Vector2(8, -13)
		var height_label := ("%.1f" % label.y).trim_suffix(".0") + "m"
		draw_string(get_theme_default_font(), at, height_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)

func _draw_water(rectangle: Rect2) -> void:
	if not rectangle.has_area():
		return
	draw_rect(rectangle, Color("73aaa9"))
	# Short ripples express water without obscuring crossings or claiming extra land.
	for row: int in range(int(rectangle.size.y / 17.0)):
		for column: int in range(int(rectangle.size.x / 26.0)):
			var at := rectangle.position + Vector2(9.0 + column * 26.0, 9.0 + row * 17.0)
			draw_line(at, at + Vector2(8, 0), Color(0.87, 0.96, 0.88, 0.30), 1.0, true)

func _draw_shores(regions: Array[Rect2]) -> void:
	for edge: PackedVector2Array in _shore_edges(regions):
		draw_polyline(edge, Color("d3dfbb"), 2.0, true)

static func _shore_edges(regions: Array[Rect2]) -> Array[PackedVector2Array]:
	# Clip each shoreline by the other water polygons. Interior overlap disappears,
	# while island boundaries remain without triangulating or filling over the land.
	var result: Array[PackedVector2Array] = []
	for i: int in regions.size():
		var rectangle := regions[i]
		var outline := _rectangle_polygon(rectangle)
		outline.append(outline[0])
		var edges: Array[PackedVector2Array] = [outline]
		for j: int in regions.size():
			if i == j or not rectangle.intersects(regions[j], true):
				continue
			var visible_edges: Array[PackedVector2Array] = []
			for edge: PackedVector2Array in edges:
				# A subpixel margin also removes edges shared by exactly adjacent rectangles.
				visible_edges.append_array(Geometry2D.clip_polyline_with_polygon(edge, _rectangle_polygon(regions[j].grow(0.05))))
			edges = visible_edges
		result.append_array(edges)
	return result

static func _rectangle_polygon(rectangle: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rectangle.position, Vector2(rectangle.end.x, rectangle.position.y), rectangle.end, Vector2(rectangle.position.x, rectangle.end.y)])

func _draw_mountain(rectangle: Rect2) -> void:
	if not rectangle.has_area():
		return
	draw_rect(rectangle, Color("788877"))
	draw_rect(rectangle.grow(-2), Color("929e85"))
	var columns := maxi(1, int(rectangle.size.x / 29.0))
	var rows := maxi(1, int(rectangle.size.y / 30.0))
	var cell := rectangle.size / Vector2(columns, rows)
	var peak_size := minf(11, minf(cell.x, cell.y) * 0.38)
	for y: int in rows:
		for x: int in columns:
			var at := rectangle.position + cell * (Vector2(x, y) + Vector2(0.5, 0.5))
			var left := at + Vector2(-peak_size, peak_size * 0.62)
			var peak := at + Vector2(0, -peak_size)
			var right := at + Vector2(peak_size, peak_size * 0.62)
			draw_colored_polygon(PackedVector2Array([left, peak, right]), Color("dce0bd"))
			draw_colored_polygon(PackedVector2Array([peak, at + Vector2(0, peak_size * 0.62), right]), Color("657768"))
	draw_rect(rectangle, Color("5b7263"), false, 1)

func _draw_bridge(rectangle: Rect2) -> void:
	if not rectangle.has_area():
		return
	draw_rect(rectangle, Color("655e46"))
	draw_rect(rectangle.grow(-2), Color("eddb9a"))
	# Square paving works for both narrow bridges and the highland's central platform;
	# the rectangle's longest side does not imply its actual crossing direction.
	for y: int in range(1, int(rectangle.size.y / 8.0)):
		for x: int in range(1, int(rectangle.size.x / 8.0)):
			var stone := Rect2(rectangle.position + Vector2(x, y) * 8.0 - Vector2(2, 2), Vector2(4, 4))
			draw_rect(stone, Color("c8b77f"), false, 1.0)

func _draw_coordinates(bounds: Rect2, factor: float) -> void:
	var font := get_theme_default_font()
	var scale_length := 10.0 * factor
	var at := Vector2(bounds.position.x, bounds.end.y + 22)
	draw_line(at, at + Vector2(scale_length, 0), Color("b9cbb2"), 2, true)
	draw_line(at - Vector2(0, 3), at + Vector2(0, 3), Color("b9cbb2"), 1, true)
	draw_line(at + Vector2(scale_length, -3), at + Vector2(scale_length, 3), Color("b9cbb2"), 1, true)
	draw_string(font, at + Vector2(scale_length + 8, 5), "10 米", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("c6d0ba"))
	draw_string(font, Vector2(bounds.end.x - 56, bounds.position.y - 18), "北 ↑", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("c6d0ba"))

func _draw_building(index: int) -> void:
	var at := building_screen_position(index)
	var faction: int = definition.building_factions[index]
	var radius := 9.0 if faction < 0 else 13.0
	var color: Color = Color("f5edcd") if faction < 0 else FACTIONS.COLORS[faction]
	if hovered_building == index:
		draw_circle(at, radius + 8, Color(1, 0.94, 0.62, 0.28), true, -1, true)
		draw_arc(at, radius + 7, 0, TAU, 40, Color("fff1ad"), 1.5, true)
	draw_circle(at + Vector2(0, 3), radius + 2, Color(0.13, 0.21, 0.17, 0.24), true, -1, true)
	if faction >= 0:
		draw_circle(at, radius + 3, INK, true, -1, true)
		draw_circle(at, radius + 1, PAPER, true, -1, true)
		draw_circle(at, radius - 1, color, true, -1, true)
		var font := get_theme_default_font()
		var number := str(faction + 1)
		var text_width := font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, at + Vector2(-text_width / 2.0, 5), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, INK)
		if faction == local_faction:
			draw_arc(at, radius + 6, 0, TAU, 40, Color("fff0ac"), 2, true)
		return
	var kind: int = definition.building_kinds[index]
	if kind == 0:
		var roof := PackedVector2Array([at + Vector2(-10, -1), at + Vector2(0, -9), at + Vector2(10, -1)])
		draw_colored_polygon(roof, INK)
		draw_rect(Rect2(at + Vector2(-7, -1), Vector2(14, 10)), INK)
		draw_rect(Rect2(at + Vector2(-5, 0), Vector2(10, 7)), color)
		draw_rect(Rect2(at + Vector2(-2, 3), Vector2(4, 5)), Color("8f9b76"))
	elif kind == 1:
		draw_rect(Rect2(at + Vector2(-7, -7), Vector2(14, 16)), INK)
		draw_rect(Rect2(at + Vector2(-5, -5), Vector2(10, 12)), Color("b7c7b8"))
		for x: int in [-7, -1, 5]:
			draw_rect(Rect2(at + Vector2(x, -10), Vector2(3, 5)), INK)
		draw_rect(Rect2(at + Vector2(-2, 0), Vector2(4, 7)), INK)
	else:
		var diamond := PackedVector2Array([at + Vector2(0, -11), at + Vector2(11, 0), at + Vector2(0, 11), at + Vector2(-11, 0)])
		draw_colored_polygon(diamond, INK)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]), Color("dfb971"))
		draw_line(at + Vector2(-4, -2), at + Vector2(4, -2), INK, 3, true)
		draw_line(at + Vector2(0, -2), at + Vector2(0, 5), INK, 2, true)
