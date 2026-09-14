extends Control
## Combat-only native controls; no recruitment, resources or construction actions.
const CLASS_LABELS: Dictionary = {&"cavalry": "骑兵", &"siege": "攻城器", &"building": "建筑", &"worker": "建设单位"}
var game: Node3D
var _notice_seconds: float = 0.0
var _army_page: int = 0
var _army_units: Array[BattleUnit] = []
var _selected_preview: String = ""
var _portraits: Dictionary = {}
@onready var _army_slots: Array[Node] = %ArmySlots.get_children()

func _ready() -> void:
	UIMotion.bind_buttons(self)
	UIMotion.reveal.call_deferred(%Objectives, Vector2(0, -8))
	UIMotion.reveal.call_deferred(%IntroPanel)
	for kind: String in $ModelPreviews.KINDS:
		_portraits[kind] = $ModelPreviews.portrait(kind)
	for slot: Button in _army_slots:
		slot.pressed.connect(_on_army_slot_pressed.bind(slot))
	%ArmyPrevious.pressed.connect(_turn_army_page.bind(-1))
	%ArmyNext.pressed.connect(_turn_army_page.bind(1))

func bind_game(controller: Node3D) -> void:
	game = controller
	%Minimap.game = game
	%Minimap.map_clicked.connect(game._on_minimap_clicked)
	%Army.pressed.connect(game.select_army)
	%Attack.pressed.connect(game.set_attack_mode.bind(true))
	%Stop.pressed.connect(game.stop_selected)
	%Hold.pressed.connect(game.hold_selected)
	%Focus.pressed.connect(game.focus_selection)
	%Base.pressed.connect(game.select_headquarters)
	for index: int in range(1, 10):
		get_node("%Group" + str(index)).pressed.connect(_on_group_pressed.bind(index))
	%Pause.pressed.connect(game.handle_pause_action)
	%Skip.pressed.connect(game.skip_intro)
	%Continue.pressed.connect(game.accept_result)
	%Resume.pressed.connect(game.handle_pause_action)
	%Settings.pressed.connect(game.open_settings)
	%Leave.pressed.connect(game.return_to_menu)
	game.settings.changed.connect(refresh_hotkey_labels)
	refresh_hotkey_labels()

func refresh_hotkey_labels() -> void:
	%Attack.text = "攻击前进 " + game.settings.hotkey_text("rts_attack_move")
	%Stop.text = "停止 " + game.settings.hotkey_text("rts_stop")
	%Hold.text = "坚守 " + game.settings.hotkey_text("rts_hold")
	%Focus.text = "定位 " + game.settings.hotkey_text("rts_focus")
	%Army.text = "选择全部军队 " + game.settings.hotkey_text("rts_select_army")
	%GroupHint.tooltip_text = "Ctrl + 点击编队：建立编队\nShift + 点击编队：追加所选部队\n点击召回编队；快速双击编队定位镜头"

func refresh() -> void:
	if game == null or game.encounter == null:
		return
	%Title.text = "围剿" if game.battle_kind == "siege" else ("前哨站 · 紧急作战" if game.emergency else "前哨站")
	%Eyebrow.text = ("作战目标 · 坚守待援 · 难度 %d" if game.battle_kind == "siege" else "作战目标 · 肃清据点 · 难度 %d") % game.encounter.difficulty
	if game.battle_kind == "siege":
		var seconds: int = maxi(0, ceili(game.encounter.duration - game.elapsed))
		%Objective.text = "守住中央大本营，等待援军抵达"
		%Progress.text = "坚守 %02d:%02d    ·    第 %d / 7 波    ·    敌军 %d" % [seconds / 60, seconds % 60, game.wave_index, game.living_enemies()]
		if is_instance_valid(game.headquarters):
			%Detail.text = "大本营  %d / %d    ·    部队全灭后仍可继续坚守" % [ceili(game.headquarters.hp), ceili(game.headquarters.max_hp)]
	else:
		%Objective.text = "摧毁所有敌方建筑物与部队"
		%Progress.text = "剩余建筑 %d / 8    ·    敌军存活 %d / 累计 %d" % [game.remaining_buildings(), game.living_enemies(), game.enemy_total]
		%Detail.text = "存活兵营会补充援军 · 优先摧毁兵营"
	%ArmyCount.text = "远征军  %d 人" % game.player_count()
	%IntroPanel.visible = game.intro_active and not game.finished
	%Commands.visible = not game.intro_active
	%MapPanel.visible = not game.intro_active
	%Groups.visible = not game.intro_active
	%MapTitle.text = "中央营地 · 围剿" if game.battle_kind == "siege" else "林地前哨站"
	%Skip.disabled = not game._match_ready
	%PortraitName.text = "侦察队长 · 罗文"
	%Dialogue.text = ("包围已经形成。敌军会从四周不断涌来！守住中央大本营，援军将在两分半后抵达。" if game.battle_kind == "siege" else "指挥官，五座箭塔守着林道，三个兵营仍在召集援军。摧毁兵营切断增援，再清除全部守军与建筑。留意侧翼的搜索队！")
	var own: Array = game.own_selected_units()
	_refresh_selection()
	_refresh_army()
	_refresh_groups()
	%Attack.disabled = own.is_empty() or game.intro_active or game.finished
	%Stop.disabled = %Attack.disabled
	%Hold.disabled = %Attack.disabled
	%Focus.disabled = game.selection.is_empty() or game.intro_active or game.finished
	%Army.disabled = _army_units.is_empty() or game.intro_active or game.finished
	%Base.visible = game.battle_kind == "siege"
	%Base.disabled = not is_instance_valid(game.headquarters) or not game.headquarters.alive or game.intro_active or game.finished
	%Pause.disabled = game.intro_active or game.finished
	%Attack.set_pressed_no_signal(game.attack_mode)

func _refresh_selection() -> void:
	%SelectedStats.tooltip_text = ""
	%SelectionHP.visible = not game.selection.is_empty()
	%SelectionHPText.visible = not game.selection.is_empty()
	if game.selection.is_empty():
		%SelectedRole.text = "远征军 · 选择与编队"
		%Selection.text = "等待指令"
		%SelectedStats.text = "点击下方头像选择部队\nShift + 点击追加或移出选择"
		%SelectedPortrait.texture = null
		_selected_preview = ""
		return
	var first: Node3D = game.selection[0]
	_selected_preview = first.unit_type if first is BattleUnit else first.building_type
	%SelectedPortrait.texture = _portraits[_selected_preview]
	var total_hp: float = 0.0
	var maximum: float = 0.0
	var counts: Dictionary = {}
	for entity: Node3D in game.selection:
		total_hp += entity.hp
		maximum += entity.max_hp
		counts[entity.display_name] = int(counts.get(entity.display_name, 0)) + 1
	%SelectionHP.max_value = maximum
	%SelectionHP.value = total_hp
	%SelectionHPText.text = "生命 %d / %d" % [ceili(total_hp), ceili(maximum)]
	if game.selection.size() > 1:
		%SelectedRole.text = "远征军 · 联合编队"
		%Selection.text = "已选择 %d 个目标" % game.selection.size()
		var composition: PackedStringArray = []
		for kind: String in counts:
			composition.append("%s ×%d" % [kind, counts[kind]])
		%SelectedStats.text = "%d 种兵力 · %d 个可指挥单位\nCtrl + 编队键保存当前选择" % [counts.size(), game.own_selected_units().size()]
		%SelectedStats.tooltip_text = "\n".join(composition)
		return
	var definition: CombatDefinition = first.get_combat_definition()
	var own: bool = first.owner_id == game.local_owner_id
	%SelectedRole.text = ("远征军" if own else "敌方") + " · " + _formation_label(definition)
	%Selection.text = first.display_name
	var attack_bonus: float = 0.0
	var defense_bonus: float = 0.0
	if first is BattleUnit and definition.military:
		attack_bonus = game.get_player(first.owner_id).get_attack_bonus()
		defense_bonus = game.get_player(first.owner_id).get_defense_bonus()
	var attack: String = "%s %s · 射程 %s" % ["远攻" if definition.damage_channel == CombatDefinition.DamageChannel.RANGED else "近攻", _number(definition.damage + attack_bonus), _number(definition.range)]
	if definition is UnitDefinition and not definition.support_kind.is_empty():
		attack = "%s %s / %s秒 · 范围 %s" % ["治疗" if definition.support_kind == &"heal" else "维修", _number(definition.support_amount), _number(definition.support_period), _number(definition.support_range)]
	var armor: String = "近甲 %s / 远甲 %s" % [_number(DamageResolver.armor_for_channel(definition, CombatDefinition.DamageChannel.MELEE, defense_bonus)), _number(DamageResolver.armor_for_channel(definition, CombatDefinition.DamageChannel.RANGED, defense_bonus))]
	%SelectedStats.text = attack + "\n" + armor + " · " + first.order_name
	%SelectedStats.tooltip_text = definition.description + "\n" + attack + "\n" + armor

func _formation_label(definition: CombatDefinition) -> String:
	if definition.combat_class in [&"infantry", &"archer"]:
		return "远程步兵" if definition.damage_channel == CombatDefinition.DamageChannel.RANGED else "近战步兵"
	return CLASS_LABELS[definition.combat_class]

func _refresh_army() -> void:
	_army_units.clear()
	var supply: int = 0
	for unit: BattleUnit in game.unit_container.get_children():
		if unit.alive and unit.owner_id == game.local_owner_id:
			_army_units.append(unit)
			supply += unit.get_combat_definition().supply
	var pages: int = maxi(1, ceili(float(_army_units.size()) / _army_slots.size()))
	_army_page = clampi(_army_page, 0, pages - 1)
	%ArmyListTitle.text = "远征部队 %d · 人口 %d/%d · 已选 %d" % [_army_units.size(), supply, game.command_unit_limit(game.local_owner_id), game.own_selected_units().size()]
	%ArmyPage.text = "%d / %d" % [_army_page + 1, pages]
	%ArmyPrevious.disabled = _army_page == 0 or game.finished
	%ArmyNext.disabled = _army_page >= pages - 1 or game.finished
	%ArmyEmpty.visible = _army_units.is_empty()
	for index: int in _army_slots.size():
		var slot: Button = _army_slots[index]
		var unit_index: int = _army_page * _army_slots.size() + index
		slot.visible = unit_index < _army_units.size()
		if not slot.visible:
			slot.remove_meta(&"unit")
			continue
		var unit: BattleUnit = _army_units[unit_index]
		slot.set_meta(&"unit", unit)
		slot.disabled = game.finished
		var selected: bool = unit in game.selection
		if slot.button_pressed != selected:
			slot.set_pressed_no_signal(selected)
		slot.get_node("Portrait").texture = _portraits[unit.unit_type]
		slot.get_node("Name").text = unit.display_name
		slot.get_node("Health").max_value = unit.max_hp
		slot.get_node("Health").value = unit.hp
		slot.tooltip_text = "%s · 生命 %d / %d\n%s\n点击选择 · Shift 追加/移出 · Ctrl 选择全部同类" % [unit.display_name, ceili(unit.hp), ceili(unit.max_hp), unit.order_name]

func _refresh_groups() -> void:
	var selected: Array = game.own_selected_assets()
	for index: int in range(1, 10):
		var members: Array = game.control_groups.get(index, []).filter(func(entity): return is_instance_valid(entity) and entity.alive)
		var button: Button = get_node("%Group" + str(index))
		var key: String = game.settings.hotkey_text("rts_group%d" % index)
		button.text = "%s · %d" % [key, members.size()] if not members.is_empty() else key
		button.disabled = game.finished
		var selected_group: bool = not members.is_empty() and members.size() == selected.size() and members.all(func(entity): return entity in selected)
		if button.button_pressed != selected_group:
			button.set_pressed_no_signal(selected_group)
		button.tooltip_text = "编队 %d · %d 个单位/建筑\n点击或按 %s 召回 · 快速双击定位\nCtrl + 点击建立 · Shift + 点击追加" % [index, members.size(), key]

func _on_army_slot_pressed(slot: Button) -> void:
	var unit: BattleUnit = slot.get_meta(&"unit")
	if not is_instance_valid(unit) or not unit.alive:
		return
	var additive: bool = Input.is_key_pressed(KEY_SHIFT)
	if Input.is_key_pressed(KEY_CTRL):
		var same_kind: Array = _army_units.filter(func(candidate: BattleUnit): return candidate.unit_type == unit.unit_type)
		game.select_entities(same_kind, additive)
	else:
		game.select_entities([unit], additive, additive)

func _on_group_pressed(index: int) -> void:
	game.use_control_group(index, Input.is_key_pressed(KEY_CTRL), Input.is_key_pressed(KEY_SHIFT))

func _turn_army_page(direction: int) -> void:
	_army_page += direction
	_refresh_army()

func _number(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).trim_suffix(".0")

func toast(message: String, seconds: float = 2.0) -> void:
	%Notice.text = message
	_notice_seconds = seconds

func _process(delta: float) -> void:
	$ModelPreviews.set_animated(_selected_preview if visible and not get_tree().paused else "")
	if _notice_seconds > 0.0:
		_notice_seconds -= delta
		if _notice_seconds <= 0.0:
			%Notice.text = ""

func show_result(victory: bool, duration: float, defeated: int) -> void:
	%IntroPanel.hide()
	%ModalShade.show()
	%ResultPanel.show()
	UIMotion.reveal(%ResultPanel, Vector2(0, 18))
	%ResultTitle.text = "坚守成功" if victory and game.battle_kind == "siege" else ("作战胜利" if victory else "远征结束")
	%ResultBody.text = ("援军抵达，围剿已经瓦解。前往整顿营地。" if game.battle_kind == "siege" else "前哨站已肃清，军队准备继续探索。") if victory else ("大本营被摧毁，本次远征到此结束。" if game.battle_kind == "siege" else "部署部队已全部阵亡，本次远征到此结束。")
	%ResultDetail.text = "作战用时 %02d:%02d    ·    击败敌军 %d\n军队名册与初始编队保留，本场伤亡不带出战场。" % [int(duration) / 60, int(duration) % 60, defeated]
	%Continue.text = "前往整顿营地" if victory and game.battle_kind == "siege" else ("领取结算" if victory else "查看远征记录")

func show_pause(value: bool) -> void:
	%PausePanel.visible = value
	%ModalShade.visible = value
	if value:
		UIMotion.reveal(%PausePanel)

func help_visible() -> bool:
	return false
