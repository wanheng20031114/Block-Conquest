extends Control
## Public territory shares pair each faction's buildings with its morale.

const FACTIONS = preload("res://scripts/block_war/war_factions.gd")
const ORDER: Array[int] = [0, 2, 4, 1, 3, 5]
const ROW_WIDTH: float = 92.0
const ROW_GAP: float = 8.0
const ROW_TOP: float = 24.0
var _faction_count: int = 0
var _has_buildings: bool = false
var _weights := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _targets := PackedFloat32Array([0, 0, 0, 0, 0, 0])
var _balance_tween: Tween
var _order: Array[int] = ORDER.duplicate()

func _ready() -> void:
	for faction: int in 6:
		get_node("Segments/Faction%d" % faction).color = FACTIONS.COLORS[faction]
		get_node("Leaders/Faction%d" % faction).default_color = Color(FACTIONS.COLORS[faction], 0.6)
	resized.connect(_layout)
	_layout()

func update_factions(building_counts: Array, morale: Array, count: int, local_faction: int = 0, names: Array = []) -> void:
	_order = [local_faction]
	for faction: int in ORDER:
		if faction != local_faction and FACTIONS.allied(faction, local_faction):
			_order.append(faction)
	for faction: int in ORDER:
		if FACTIONS.hostile(faction, local_faction):
			_order.append(faction)
	var total: float = 0.0
	for faction: int in count:
		total += float(building_counts[faction])
	_has_buildings = total > 0.0
	var targets := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	for faction: int in count:
		targets[faction] = float(building_counts[faction]) / total if _has_buildings else 1.0 / float(count)
		var row: HBoxContainer = get_node("Stars/Faction%d" % faction)
		var full_stars: int = floori(float(morale[faction]))
		row.tooltip_text = "%s · %d 星\n攻击 +%d%% · 防御 +%d%% · 移速 +%d%%" % [names[faction] if names.size() == count else FACTIONS.NAMES[faction], full_stars, full_stars * 5, full_stars * 25, full_stars * 10]
		row.tooltip_text += "\n%d 处据点 · 顶部色带表示据点占比\n己方数字为联盟总兵力，敌方总兵力未知" % int(building_counts[faction])
		if full_stars < 5:
			var next_star_percent: float = floorf((float(morale[faction]) - full_stars) * 1000.0) / 10.0
			row.tooltip_text += "\n下颗星充能 %.1f%%" % next_star_percent
		for index: int in 5:
			row.get_child(index).set_charge(float(morale[faction]) - float(index))
	if _faction_count != count:
		_faction_count = count
		_targets = targets
		_weights = targets.duplicate()
		if _balance_tween != null and _balance_tween.is_valid():
			_balance_tween.kill()
	elif _targets != targets:
		_targets = targets
		if _balance_tween != null and _balance_tween.is_valid():
			_balance_tween.kill()
		_balance_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_balance_tween.tween_method(_blend_weights.bind(_weights.duplicate(), targets), 0.0, 1.0, 0.28)
	_layout()

func _blend_weights(weight: float, start: PackedFloat32Array, target: PackedFloat32Array) -> void:
	for faction: int in 6:
		_weights[faction] = lerpf(start[faction], target[faction], weight)
	_layout()

func _layout() -> void:
	if not is_node_ready():
		return
	var seats: Array[int] = []
	var centers: Array[float] = []
	var cursor: float = 0.0
	for faction: int in _order:
		var segment: ColorRect = get_node("Segments/Faction%d" % faction)
		var row: Control = get_node("Stars/Faction%d" % faction)
		var leader: Line2D = get_node("Leaders/Faction%d" % faction)
		segment.visible = faction < _faction_count and _has_buildings
		row.visible = faction < _faction_count
		leader.hide()
		if faction >= _faction_count:
			continue
		var width: float = size.x * _weights[faction]
		segment.position = Vector2(cursor, 0.0)
		segment.size = Vector2(width, 16.0)
		seats.append(faction)
		centers.append(cursor + width * 0.5)
		cursor += width
	if seats.is_empty():
		return
	var scale_factor: float = minf(1.0, size.x / (ROW_WIDTH * seats.size() + ROW_GAP * (seats.size() - 1)))
	var half_width: float = ROW_WIDTH * scale_factor * 0.5
	var step: float = (ROW_WIDTH + ROW_GAP) * scale_factor
	var packed_centers: Array[float] = centers.duplicate()
	# Keep exact share centers whenever they fit; only crowded neighbors move.
	for index: int in packed_centers.size():
		packed_centers[index] = maxf(centers[index], half_width if index == 0 else packed_centers[index - 1] + step)
	packed_centers[-1] = minf(packed_centers[-1], size.x - half_width)
	for index: int in range(packed_centers.size() - 2, -1, -1):
		packed_centers[index] = minf(packed_centers[index], packed_centers[index + 1] - step)
	for index: int in seats.size():
		var row: Control = get_node("Stars/Faction%d" % seats[index])
		row.scale = Vector2.ONE * scale_factor
		row.position = Vector2(packed_centers[index] - half_width, ROW_TOP).round()
		if absf(packed_centers[index] - centers[index]) > 4.0:
			var leader: Line2D = get_node("Leaders/Faction%d" % seats[index])
			leader.points = PackedVector2Array([Vector2(centers[index], 17), Vector2(centers[index], 19), Vector2(packed_centers[index], ROW_TOP - 2)])
			leader.show()
