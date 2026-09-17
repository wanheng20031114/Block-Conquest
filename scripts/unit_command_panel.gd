extends PanelContainer
## RTS commands are selection-bound; the same panel presents troops and heroes.
var game: Node3D
var portraits: Dictionary = {}
@onready var composition: SelectionComposition = %Composition
@onready var ability_buttons: Array[Node] = %Abilities.get_children()

func bind(controller: Node3D, textures: Dictionary) -> void:
	game = controller
	portraits = textures
	composition.bind(game, portraits)
	composition.focus_changed.connect(refresh)
	%Attack.pressed.connect(game.set_attack_mode.bind(true))
	%Stop.pressed.connect(game.stop_selected)
	%Hold.pressed.connect(func(): game.hold_selected(Input.is_key_pressed(KEY_SHIFT)))
	%Focus.pressed.connect(game.focus_selection)
	%Inventory.pressed.connect(func(): if focused_hero() != null: game.hero_controller.interface.open_inventory())
	%Control.pressed.connect(func(): if focused_hero() != null: game.hero_controller.set_first_person(true))
	for index: int in ability_buttons.size():
		ability_buttons[index].pressed.connect(trigger_action_slot.bind(index))

func focused_hero() -> HeroUnit:
	var entity := composition.focused_entity()
	if entity is HeroUnit and entity.owner_id == game.local_owner_id: return entity
	return null

func refresh() -> void:
	if game == null: return
	composition.refresh()
	visible = composition.total_count > 0 and not game.placing
	if not visible: return
	var entity := composition.focused_entity()
	if entity == null: return
	var group := composition.focused_group()
	%Portrait.texture = portraits[group.kind]
	%UnitName.text = entity.display_name + (" ×%d" % group.members.size() if group.members.size()>1 else "")
	%Role.text = ("你的部队" if entity.owner_id==game.local_owner_id else "其他阵营") + " · 当前查看"
	%Health.max_value = maxf(1.0, group.max_hp)
	%Health.value = group.hp
	%HealthText.text = "生命 %d / %d" % [ceili(group.hp), ceili(group.max_hp)]
	%Health.visible = not entity is ResourceVein
	%HealthText.visible = not entity is ResourceVein
	%Stats.text = "右键指派农民采集" if entity is ResourceVein else _stats_text(entity)
	%Attack.text = "攻击前进 " + game.settings.hotkey_text("rts_attack_move")
	%Stop.text = "停止 " + game.settings.hotkey_text("rts_stop")
	%Hold.text = "坚守 " + game.settings.hotkey_text("rts_hold")
	%Attack.set_pressed_no_signal(game.attack_mode)
	var controllable: bool = not game.own_selected_units().is_empty()
	for button: Button in [%Attack,%Stop,%Hold]: button.disabled = not controllable
	%Focus.text = "定位 " + game.settings.hotkey_text("rts_focus")
	var hero := focused_hero()
	%Abilities.visible = hero != null
	%Inventory.visible = hero != null
	%Control.visible = hero != null
	%AbilityTitle.text = "英雄能力 / 道具" if hero != null else "单位指令"
	%UnitHint.visible = hero == null
	%UnitHint.text = "右键移动 / 攻击\n当前选择的所有己方单位接收行军指令。"
	if entity is BattleBuilding:
		%AbilityTitle.text = "建筑状态"
		%UnitHint.text = "自动攻击射程内敌人\nDelete 移除所选建筑" if entity._stats.damage > 0 else "固定建筑\nDelete 移除所选建筑"
	if hero == null: return
	for index: int in ability_buttons.size():
		var button: Button = ability_buttons[index]
		button.get_node("Hotkey").text = game.settings.hotkey_text("rts_slot_%d" % (index+1))
		var icon: TextureRect = button.get_node("Icon")
		var cooldown: ProgressBar = button.get_node("Cooldown")
		var title: Label = button.get_node("Title")
		var status: Label = button.get_node("Status")
		if index == 5:
			icon.texture = game.hero_controller.interface.get_node("%WeaponIconViewport").get_texture()
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			title.text = "装填"
			status.text = "%.1fs" % hero.weapon.reload_remaining if hero.weapon.reload_remaining>0 else "%d/%d" % [hero.weapon.rounds,hero.weapon.definition.magazine_size]
			cooldown.max_value = hero.weapon.definition.reload_seconds
			cooldown.value = hero.weapon.reload_remaining
			button.disabled = not game.running or hero.weapon.reload_remaining>0 or hero.weapon.rounds==hero.weapon.definition.magazine_size
			button.tooltip_text = "装填弹匣 · %.1f 秒 · 无限备弹" % hero.weapon.definition.reload_seconds
			continue
		var id: StringName = hero.inventory.hotbar[index]
		var item: HeroItemDefinition = HeroInventory.ITEMS.get(id)
		icon.texture = item.icon if item != null else null
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		title.text = item.display_name if item != null else "未绑定"
		var remaining: float = hero.inventory.cooldowns.get(id,0.0)
		status.text = "%.1fs" % remaining if remaining>0 else ("×%d" % hero.inventory.count(id) if item != null else "")
		cooldown.max_value = item.cooldown if item != null else 1.0
		cooldown.value = remaining
		var no_effect: bool = item != null and ((item.effect == HeroItemDefinition.Effect.HEAL and hero.hp>=hero.max_hp) or (item.effect == HeroItemDefinition.Effect.SPEED and hero.speed_boost_remaining>0))
		button.disabled = not game.running or item == null or remaining>0 or hero.inventory.count(id)==0 or no_effect
		button.tooltip_text = item.description if item != null else "在背包中将道具拖入对应快捷位。"

func _stats_text(entity: Node3D) -> String:
	var definition: CombatDefinition = entity.get_combat_definition()
	var own: bool = entity.owner_id == game.local_owner_id
	var player: PlayerState = game.get_player(entity.owner_id)
	var military_unit: bool = definition is UnitDefinition and definition.military
	var attack_bonus: float = player.get_attack_bonus() if own and military_unit else 0.0
	var defense_bonus: float = player.get_defense_bonus() if own and military_unit else 0.0
	var damage: float = definition.damage + attack_bonus
	var attack_range: float = definition.range
	if entity is HeroUnit:
		damage += entity.weapon.definition.attack_bonus
		attack_range = entity.weapon.definition.range
	var damage_label: String = _number(damage)
	if definition is BuildingDefinition and definition.weapon_count > 1:
		damage_label += " × %d" % definition.weapon_count
	var result := "%s %s · 射程 %s\n近甲 %s · 远甲 %s\n%s" % ["远攻" if definition.damage_channel==CombatDefinition.DamageChannel.RANGED else "近攻", damage_label, _number(attack_range),
		_number(DamageResolver.armor_for_channel(definition,CombatDefinition.DamageChannel.MELEE,defense_bonus)),
		_number(DamageResolver.armor_for_channel(definition,CombatDefinition.DamageChannel.RANGED,defense_bonus)), entity.order_name]
	if entity is HeroUnit:
		result += "\n弹匣 %d/%d · %s" % [entity.weapon.rounds,entity.weapon.definition.magazine_size,"装填 %.1fs" % entity.weapon.reload_remaining if entity.weapon.reload_remaining>0 else "无限备弹"]
	return result

func _number(value: float) -> String:
	return String.num(snappedf(value, 0.1), 1).trim_suffix(".0")

func trigger_action_slot(index: int) -> bool:
	refresh()
	var hero := focused_hero()
	if hero == null: return false
	if index<0 or index>=ability_buttons.size() or ability_buttons[index].disabled: return true
	if index == 5: hero.weapon.begin_reload()
	else: game.hero_controller.interface.use_shortcut(index)
	refresh()
	return true

func cycle_selection_group(reverse: bool = false) -> bool:
	return composition.cycle(reverse)
