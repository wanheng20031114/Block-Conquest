extends Control
var game: Node3D
var toast_remaining: float = 0
@onready var cards: Array[Node] = %Hand.get_children()
@onready var weapon_view: Control = $WeaponView
@onready var weapon_viewport: SubViewport = $WeaponView/WeaponViewport

func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()
	%FPSHint.hide()
	%DropZone.interface = self
	%DropHint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Pause.pressed.connect(toggle_pause)
	%Resume.pressed.connect(toggle_pause)
	%Restart.pressed.connect(func(): game.restart())
	%Back.pressed.connect(func(): game.return_to_menu())
	%Settings.pressed.connect(func(): game.open_settings())
	%Recovery.pressed.connect(func(): game.cast_skill(0))
	%Morale.pressed.connect(func(): game.cast_skill(1))
	%FocusHero.pressed.connect(func(): game.focus_hero())
	%ViewMode.pressed.connect(func(): game.hero_controller.toggle_view())
	%Recovery.tooltip_text = "肉体强化  [E]\n每秒恢复 25 生命，持续 5 秒。\n冷却 20 秒，从释放时开始计算。"
	%Morale.tooltip_text = "士气昂扬  [R]\n自身与半径 3 内的友军移动速度 +25%，持续 3 秒。\n冷却 25 秒，从释放时开始计算。"
	%HeroStats.tooltip_text = "基础攻击 20 + 武器攻击 20；射程 20；每 0.65 秒一发。\n本模式弹药无限，无需换弹。"
	%Gold.tooltip_text = "每名敌军阵亡，获得其造价 20% 的金币，最低 5。\n无需补刀；英雄与建筑不发放金币。"
	var enemy_fill: StyleBoxFlat = %EnemyHealth.get_theme_stylebox("fill").duplicate()
	enemy_fill.bg_color = Color("e47a84")
	%EnemyHealth.add_theme_stylebox_override("fill", enemy_fill)

func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	var factor := minf(viewport_size.x / 1600.0, viewport_size.y / 900.0)
	$Layout.scale = Vector2.ONE * factor
	$Layout.size = viewport_size / factor
	weapon_viewport.size = Vector2i(viewport_size * .75)

func bind_game(value: Node3D) -> void:
	game = value
	%Minimap.game = game
	$ModelPreviews.set_team(FactionPalette.SELF)
	for index: int in cards.size(): cards[index].bind(self, index)
	refresh()

func sync_hero(profile: Dictionary) -> void:
	$HeroPortrait.sync_appearance(profile)
	%Portrait.texture = $HeroPortrait.get_texture()
	%HeroName.text = profile.name

func refresh() -> void:
	if game == null: return
	%Gold.text = "金币  %d" % game.players[0].gold
	%Clock.text = "%02d:%02d" % [int(game.elapsed) / 60, int(game.elapsed) % 60]
	%Wave.text = "第 %d 波  ·  %.1f 秒" % [game.wave_counts[0] + 1, maxf(0, game.wave_due[0] - game.elapsed)]
	%ArmyCount.text = "我方 %d / %d  ·  敌方 %d" % [game.army_counts[0], game.ARMY_CAP, game.army_counts[1]]
	for owner: int in 2:
		var base: BattleBuilding = game.bases[owner]
		var hp: float = base.hp if is_instance_valid(base) else 0
		var hp_max: float = base.max_hp if is_instance_valid(base) else 2200
		var label: Label = %OurBase if owner == 0 else %EnemyBase
		var bar: ProgressBar = %OurHealth if owner == 0 else %EnemyHealth
		label.text = "%s大本营  %d" % ["我方" if owner == 0 else "敌方", ceili(hp)]
		bar.max_value = hp_max
		bar.value = hp
	for index: int in cards.size():
		var entry: Dictionary = game.hands[0].slots[index]
		var card: MobaCardDefinition = entry.card
		var portrait: Texture2D = $ModelPreviews.portrait(card.units[0]) if card != null else null
		cards[index].present(entry, portrait, card != null and game.players[0].gold >= card.cost)
	var hero: MobaHero = game.local_hero()
	%Recovery.disabled = hero == null or not game.running or hero.recovery_cooldown > .000001
	%Morale.disabled = hero == null or not game.running or hero.morale_cooldown > .000001
	%FocusHero.disabled = hero == null
	%ViewMode.disabled = hero == null or not game.running
	if hero != null:
		%HeroHealth.max_value = hero.max_hp
		%HeroHealth.value = hero.hp
		%HeroHP.text = "%d / %d%s" % [ceili(hero.hp), int(hero.max_hp), "   强化中" if hero.recovery_ticks > 0 else ""]
		%Recovery.text = "E  肉体强化" if hero.recovery_cooldown <= .000001 else "E  %.1f 秒" % hero.recovery_cooldown
		%Morale.text = "R  士气昂扬" if hero.morale_cooldown <= .000001 else "R  %.1f 秒" % hero.morale_cooldown
		%HeroStats.text = "近甲 %d · 远甲 %d · %s" % [hero._stats.melee_armor, hero._stats.ranged_armor, "移速 +25%" if hero.movement_multiplier > 1 else "无限弹药"]
	else:
		%HeroHealth.value = 0
		%HeroHP.text = "%.1f 秒后在大本营复活" % maxf(0, game.respawn_at[0] - game.elapsed)
		%Recovery.text = "E  肉体强化"
		%Morale.text = "R  士气昂扬"
	%Minimap.queue_redraw()

func _process(delta: float) -> void:
	if toast_remaining > 0:
		toast_remaining -= delta
		if toast_remaining <= 0: %Toast.hide()

func toast(message: String, duration: float = 3) -> void:
	%Toast.text = message
	%Toast.show()
	toast_remaining = duration

func help_visible() -> bool: return %Modal.visible

func toggle_pause() -> void:
	if game.finished: return
	var pause: bool = not %Modal.visible
	%Modal.visible = pause
	game.set_running(not pause)
	game.hero_controller.capture_mouse(not pause and game.hero_controller.first_person)

func show_result(victory: bool, elapsed: float, kills: int) -> void:
	%Modal.show()
	%Resume.hide()
	%DialogTitle.text = "防线突破 · 胜利" if victory else "大本营失守"
	%DialogDetail.text = "用时 %02d:%02d · 击败敌军 %d\n出牌 %d 次 · 获得 %d 金币" % [int(elapsed) / 60, int(elapsed) % 60, kills, game.card_plays[0], game.earned_gold[0]]

func set_first_person(value: bool) -> void:
	weapon_view.visible = value
	weapon_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	%Crosshair.visible = value
	%FPSHint.visible = value
	%ViewMode.text = "F5  返回俯视" if value else "F5  第一人称"
	%Toast.position.y = 136 if value else 94

func set_hit_feedback(hit: bool) -> void:
	%Crosshair.modulate = Color("f2c76a") if hit else Color.WHITE

func update_weapon(weapon: HeroWeaponRuntime) -> void:
	var recoil := .065 * pow(clampf(weapon.cooldown / weapon.definition.interval, 0, 1), 4.0) if weapon.shots_fired > 0 else 0.0
	$WeaponView/WeaponViewport/GunPivot.position.z = -.54 + recoil
	$WeaponView/WeaponViewport/GunPivot/MuzzleFlash.visible = weapon.shots_fired > 0 and weapon.cooldown > weapon.definition.interval - .05

func drag_started() -> void:
	%DropHint.show()
	%DropText.text = "松开：从大本营派出援军"

func drag_finished() -> void:
	%DropHint.hide()

func _input(event: InputEvent) -> void:
	if not get_viewport().gui_is_dragging(): return
	var cancel: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	cancel = cancel or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE)
	if cancel:
		get_viewport().gui_cancel_drag()
		get_viewport().set_input_as_handled()
