extends Control
## An isolated, authored diagram. It never creates armies or changes a match.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const HOUSE := preload("res://assets/ui/block_war/action_house.svg")
const TOWER := preload("res://assets/ui/block_war/action_tower.svg")
const FRIEND := Color("7baf8c")
const FOE := Color("db8e72")

var commander: StringName = &"squirrel"
var skill_index: int = 0
var playing: bool = true
@export var progress: float = 0.0:
	set(value):
		progress = value
		if is_node_ready():
			_render_demo()

@onready var animator: AnimationPlayer = %AnimationPlayer
@onready var home: TextureRect = %Home
@onready var away: TextureRect = %Away
@onready var allies: Array[TextureRect] = [%AllyA, %AllyB, %AllyC]
@onready var enemies: Array[TextureRect] = [%EnemyA, %EnemyB, %EnemyC]
@onready var range_ring: Panel = %Range
@onready var shield: Panel = %Shield
@onready var portals: Array[Panel] = [%PortalA, %PortalB]
@onready var route: Line2D = %Route
@onready var tunnel: Line2D = %Tunnel
@onready var projectile: Line2D = %Projectile
@onready var skill_icon: TextureRect = %SkillIcon
@onready var direction: Label = %Direction
@onready var home_count: Label = %HomeCount
@onready var away_count: Label = %AwayCount
@onready var effect_label: Label = %EffectLabel
@onready var construction: ProgressBar = %Construction
@onready var caption: Label = %Caption

var _left := Vector2.ZERO
var _right := Vector2.ZERO
var _middle := Vector2.ZERO
var _travel_left: float
var _travel_right: float


func _ready() -> void:
	resized.connect(_render_demo)
	visibility_changed.connect(_sync_playback)
	configure(commander, skill_index)


func configure(next_commander: StringName, next_skill_index: int) -> void:
	assert(next_commander in [&"squirrel", &"rabbit", &"bear", &"frog"])
	assert(next_skill_index >= 0 and next_skill_index < 4)
	commander = next_commander
	skill_index = next_skill_index
	if not is_node_ready():
		return
	skill_icon.texture = RULES.icons_for(commander)[skill_index]
	replay()


func set_playing(enabled: bool) -> void:
	playing = enabled
	if is_node_ready():
		_sync_playback()


func replay() -> void:
	if not is_node_ready():
		return
	animator.play(&"cycle")
	animator.seek(0.0, true)
	progress = 0.0
	_sync_playback()


func _sync_playback() -> void:
	if playing and is_visible_in_tree():
		animator.play(&"cycle")
	else:
		animator.pause()


func _exit_tree() -> void:
	animator.stop()


func _place(control: Control, center: Vector2, extent: Vector2) -> void:
	control.size = extent
	control.position = center - extent * 0.5


func _render_demo() -> void:
	# All positions derive from the available content box, keeping diagrams clear
	# when the detail column changes size. Nodes themselves are scene-authored.
	var floor_y := minf(size.y - 99.0, 119.0)
	_left = Vector2(53.0, floor_y)
	_right = Vector2(size.x - 53.0, floor_y)
	_middle = (_left + _right) * 0.5
	_travel_left = _left.x + 39.0
	_travel_right = _right.x - 39.0
	_place(home, _left - Vector2(0, 10), Vector2(56, 56))
	_place(away, _right - Vector2(0, 10), Vector2(56, 56))
	home.texture = HOUSE
	away.texture = HOUSE
	home.modulate = FRIEND
	away.modulate = FOE
	home.scale = Vector2.ONE
	away.scale = Vector2.ONE
	_place(home_count, _left + Vector2(0, 33), Vector2(96, 22))
	_place(away_count, _right + Vector2(0, 33), Vector2(96, 22))
	home_count.text = "己方 · 20"
	away_count.hide()
	away_count.text = ""
	$Legend.text = "绿 · 己方   橙 · 敌方"
	route.points = PackedVector2Array([_left + Vector2(0, 16), _right + Vector2(0, 16)])
	_place(range_ring, _middle, Vector2((_travel_right - _travel_left) / 3.0 + 28.0, 91.0))
	_place(shield, _left - Vector2(0, 10), Vector2(85, 91))
	_place(skill_icon, _middle - Vector2(0, 54), Vector2(35, 35))
	_place(effect_label, _middle + Vector2(0, 43), Vector2(size.x - 190.0, 26))
	_place(direction, _middle - Vector2(0, 16), Vector2(80, 31))
	_place(construction, _left + Vector2(0, 21), Vector2(62, 7))
	for visual: CanvasItem in [range_ring, shield, tunnel, portals[0], portals[1], projectile, direction, construction]:
		visual.visible = false
		visual.modulate = Color.WHITE
	effect_label.text = ""
	skill_icon.visible = true
	skill_icon.modulate = Color(1, 1, 1, 0.8 + 0.2 * sin(progress * TAU))
	for index: int in range(3):
		allies[index].visible = false
		enemies[index].visible = false
		allies[index].modulate = FRIEND
		enemies[index].modulate = FOE
		_place(allies[index], Vector2(_travel_left, floor_y), Vector2(18, 24))
		_place(enemies[index], Vector2(_travel_right, floor_y), Vector2(18, 24))
	match commander:
		&"squirrel": _squirrel()
		&"rabbit": _rabbit()
		&"bear": _bear()
		&"frog": _frog()


func _march(units: Array[TextureRect], fraction: float, from_right: bool = false, lift: float = 0.0) -> void:
	var start := _travel_right if from_right else _travel_left
	var end := _travel_left if from_right else _travel_right
	for index: int in range(units.size()):
		var offset := (index - 1) * 15.0
		units[index].visible = true
		units[index].position = Vector2(lerpf(start, end, fraction) + offset - 9.0, _middle.y - 17.0 - lift)


func _phase(start: float, finish: float) -> float:
	return clampf((progress - start) / (finish - start), 0.0, 1.0)


func _label(text: String) -> void:
	effect_label.text = text


func _squirrel() -> void:
	match skill_index:
		0:
			var recruited := mini(24, int(_phase(0.15, 0.85) * 24.0))
			home_count.text = "己方 · %d" % (20 + recruited)
			_place(skill_icon, _left - Vector2(0, 54), Vector2(35, 35))
			_label("+%d 兵力" % recruited)
			caption.text = "住宅持续征召，每秒增加 4 人"
			direction.visible = true
			direction.text = "+"
			direction.modulate.a = 0.45 + 0.55 * sin(progress * PI * 12.0) ** 2
		1:
			range_ring.visible = true
			var travel := _phase(0.1, 0.9)
			# Three equal route segments: the middle takes 1 / 1.6 as long.
			var x: float
			if travel < 0.381:
				x = travel / 0.381 / 3.0
			elif travel < 0.619:
				x = 1.0 / 3.0 + (travel - 0.381) / 0.238 / 3.0
			else:
				x = 2.0 / 3.0 + (travel - 0.619) / 0.381 / 3.0
			_march(allies, x)
			var inside := x > 0.333 and x < 0.667
			_label("移速 +60%" if inside else "正常移速")
			caption.text = "己方部队进入区域后加速，离开恢复"
		2:
			shield.visible = progress > 0.18
			shield.modulate.a = 0.65 + 0.35 * sin(progress * PI * 3.0) ** 2
			_march(enemies, _phase(0.1, 0.9) * 0.93, true)
			_place(skill_icon, _left - Vector2(0, 61), Vector2(35, 35))
			_label("守备 +25%" if progress > 0.18 else "选择己方建筑")
			caption.text = "提升目标建筑守备，持续 8 秒"
		3:
			var fire := _phase(0.38, 0.65)
			_march(allies, minf(_phase(0.02, 0.55) * 0.6, 0.49))
			_march(enemies, minf(_phase(0.02, 0.55) * 0.6, 0.49), true)
			range_ring.visible = fire > 0.0
			_place(range_ring, _middle, Vector2(145.0, 101.0) * maxf(0.05, fire))
			range_ring.modulate = Color(1.0, 0.55, 0.3, 1.0 - _phase(0.78, 0.98))
			for unit: TextureRect in allies + enemies:
				unit.modulate.a = 1.0 - _phase(0.45, 0.55)
			_label("双方士兵均受火焰影响" if fire > 0.0 else "选择地面区域")
			caption.text = "火焰向外扩散，接触的双方士兵均死亡"


func _rabbit() -> void:
	match skill_index:
		0:
			range_ring.visible = progress < 0.4
			_place(range_ring, Vector2(lerpf(_travel_left, _travel_right, 0.23), _middle.y), Vector2(88, 84))
			var travel := _phase(0.1, 0.9)
			var x := travel * 0.55 if travel < 0.3 else 0.165 + (travel - 0.3) * 1.19
			_march(allies, x)
			_label("移速、攻击 +100%" if progress > 0.34 else "选定当前部队")
			caption.text = "选中部队获得冲刺，离开施放点仍然生效"
		1:
			away.texture = TOWER
			_place(skill_icon, _right - Vector2(0, 45), Vector2(42, 42))
			away.modulate = FOE.lerp(Color("ada18c"), _phase(0.15, 0.3))
			away_count.show()
			away_count.text = "敌方 · 停工" if progress > 0.24 else "敌方 · 炮塔"
			projectile.visible = progress < 0.2
			projectile.points = PackedVector2Array([_right - Vector2(0, 18), _middle])
			_march(allies, _phase(0.05, 0.95))
			_label("暂停运作" if progress > 0.24 else "选择敌方建筑")
			caption.text = "封停目标 6 秒：停产、停火或暂停攻击增益"
		2:
			var fraction := 0.46 * _phase(0.05, 0.38) * (1.0 - _phase(0.43, 0.92))
			_march(allies, fraction)
			_march(enemies, fraction, true)
			range_ring.visible = progress > 0.32 and progress < 0.62
			_place(range_ring, _middle, Vector2(size.x - 132.0, 94.0))
			direction.visible = progress > 0.43
			direction.text = "←   →"
			_label("各自返回出发建筑" if progress > 0.43 else "双方行军进入范围")
			caption.text = "范围内所有阵营的行军各自返程"
		3:
			var digging := _phase(0.18, 0.48)
			tunnel.visible = progress > 0.18
			var entrance := _left + Vector2(35, 15)
			var exit := _right + Vector2(-35, 15)
			tunnel.points = PackedVector2Array([entrance, entrance.lerp(exit, digging)])
			for index: int in range(2):
				portals[index].visible = progress > (0.15 if index == 0 else 0.48)
				_place(portals[index], Vector2(_travel_left if index == 0 else _travel_right - 20.0, _middle.y + 13), Vector2(37, 17))
			for index: int in range(3):
				var emergence := _phase(0.48 + index * 0.08, 0.73 + index * 0.08)
				allies[index].visible = emergence > 0.0
				allies[index].position = Vector2(_travel_right - 29.0 + emergence * 25.0, _middle.y - 5.0 - emergence * 13.0 - index * 4.0)
			_label("快速掘地" if progress < 0.48 else "部队分批出洞")
			caption.text = "下一次派兵使用兔洞，最多运送 50 人"


func _bear() -> void:
	match skill_index:
		0:
			construction.visible = true
			construction.value = lerpf(28.0, 100.0, _phase(0.3, 0.4))
			_place(skill_icon, _left - Vector2(0, 53), Vector2(35, 35))
			home.modulate = Color("b1af91").lerp(FRIEND, _phase(0.3, 0.4))
			_label("立即完工 · 返还人口" if progress > 0.4 else "建筑正在施工")
			home_count.text = "己方 · 30" if progress > 0.4 else "己方 · 20"
			caption.text = "完成升级或转换，返还本次消耗人口的 50%"
		1:
			range_ring.visible = true
			range_ring.modulate.a = 0.6 + sin(progress * PI * 8.0) ** 2 * 0.4
			var travel := _phase(0.06, 0.95)
			var x: float
			if travel < 0.222:
				x = travel / 0.222 / 3.0
			elif travel < 0.778:
				x = 1.0 / 3.0 + (travel - 0.222) / 0.556 / 3.0
			else:
				x = 2.0 / 3.0 + (travel - 0.778) / 0.222 / 3.0
			_march(enemies, x, true)
			_march(allies, _phase(0.06, 0.95))
			for ally: TextureRect in allies:
				ally.position.y -= 23.0
			_label("敌军移速 -60%" if x > 0.333 and x < 0.667 else "离开恢复原速")
			caption.text = "震地区域仅使敌军减速，友军不受影响"
		2:
			away.modulate = FRIEND
			home_count.text = "受护 · %d" % (35 if progress > 0.54 else 40)
			away_count.show()
			away_count.text = "支援 · %d" % (25 if progress > 0.54 else 30)
			tunnel.visible = progress > 0.18
			tunnel.points = PackedVector2Array([_left + Vector2(28, 9), _right - Vector2(28, -9)])
			tunnel.modulate = FRIEND
			direction.visible = progress > 0.18
			direction.text = "→"
			_label("承受 5    分担 5" if progress > 0.54 else "建立单向分担")
			shield.visible = progress > 0.18
			_march(enemies, _phase(0.1, 0.55), true)
			for enemy: TextureRect in enemies:
				enemy.position.y -= 26.0
				enemy.modulate.a = 1.0 - _phase(0.5, 0.58)
			caption.text = "目标受伤时，支援建筑分担一半驻军伤害"
		3:
			shield.visible = progress > 0.14
			_place(skill_icon, _left - Vector2(0, 62), Vector2(35, 35))
			_march(enemies, minf(0.67, _phase(0.04, 0.6)), true)
			var shot := _phase(0.5, 0.66)
			projectile.visible = shot > 0.0 and shot < 1.0
			var origin := _left - Vector2(0, 45)
			var target := enemies[2].position + Vector2(9, 12)
			projectile.points = PackedVector2Array([origin.lerp(target, maxf(0.0, shot - 0.12)), origin.lerp(target, shot)])
			enemies[2].modulate.a = 1.0 - _phase(0.66, 0.72)
			_label("无敌 · 法术球反击")
			caption.text = "建筑无敌，敌军在外围等待；法术球打击远敌"


func _frog() -> void:
	match skill_index:
		0:
			range_ring.visible = true
			range_ring.modulate = Color(0.72, 0.87, 0.81, 0.65 + sin(progress * PI * 2) ** 2 * 0.3)
			_march(enemies, _phase(0.08, 0.92), true)
			var weakened := progress > 0.34
			for enemy: TextureRect in enemies:
				enemy.modulate = FOE.lerp(Color("b5c9b1"), 0.6 if weakened else 0.0)
			_label("攻击 -20%" if weakened else "敌军接触薄雾")
			caption.text = "雾内士兵免受炮塔攻击，敌军弱化持续至入城"
		1:
			var travel: float
			if progress < 0.3:
				travel = _phase(0.04, 0.3) * 0.4
			elif progress < 0.72:
				travel = 0.4
			else:
				travel = 0.4 + _phase(0.72, 0.98) * 0.6
			var suspended := progress >= 0.3 and progress < 0.72
			var lift := 15.0 * _phase(0.3, 0.35) * (1.0 - _phase(0.68, 0.73))
			_march(allies, travel, false, lift)
			_march(enemies, travel, true, lift)
			range_ring.visible = suspended
			range_ring.modulate = Color(0.73, 0.85, 1.0, 0.9)
			_label("滞空 · 暂停移动" if suspended else "继续原路线")
			caption.text = "当前范围内的双方士兵滞空 3 秒，落地后前进"
		2:
			_march(allies, _phase(0.04, 0.96))
			range_ring.visible = progress > 0.2 and progress < 0.43
			_place(range_ring, Vector2(lerpf(_travel_left, _travel_right, 0.3), _middle.y), Vector2(105, 90))
			var opacity := lerpf(1.0, 0.2, _phase(0.27, 0.35))
			for ally: TextureRect in allies:
				ally.modulate.a = opacity
			_label("隐身行军" if progress > 0.35 else "选定己方部队")
			caption.text = "隐身部队继续移动，免受炮塔攻击，直至入城"
		3:
			var struck := progress > 0.43
			$Legend.text = "绿 · 己方   灰 · 中立"
			_place(skill_icon, _right - Vector2(0, 58.0 - sin(_phase(0.25, 0.45) * PI) * 10.0), Vector2(40, 40))
			away_count.show()
			away_count.text = "中立 · %d" % (10 if struck else 50)
			away.modulate = Color("b5aa87").lerp(Color.WHITE, sin(_phase(0.4, 0.53) * PI) * 0.65)
			_label("3 级 → 1 级" if struck else "选择中立建筑")
			caption.text = "削减 80% 当前驻军并降至 1 级，不直接占领"
