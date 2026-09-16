extends CanvasLayer
var controller: SandboxHeroController
var _draft: Dictionary
var _refreshing := false
var _rotating := false
var _notice_time := 0.0
var _selected_item: StringName = &"healing_potion"
var _selected_slot: int = 0
var _showing_weapon := false

func bind(value: SandboxHeroController) -> void:
	controller = value
	%Fields.set_tab_title(0,"形象与配色")
	%Fields.set_tab_title(1,"表情与装饰")
	UIMotion.bind_buttons($Root)
	for index: int in FactionPalette.SANDBOX_NAMES.size():
		%Faction.add_item("%02d · %s" % [index+1,FactionPalette.SANDBOX_NAMES[index]])
	for title: String in HeroProfile.EXPRESSION_NAMES: %Expression.add_item(title)
	for title: String in HeroProfile.HAT_NAMES: %Headwear.add_item(title)
	%Expression.item_selected.connect(func(index: int): _draft.expression=index; _preview())
	%Headwear.item_selected.connect(func(index: int): _draft.hat=index>0; _draft.headwear=maxi(0,index-1); _preview())
	%PlayerName.text_changed.connect(func(text: String): _draft.name = text)
	%Faction.item_selected.connect(func(index: int): _draft.faction=index; _preview())
	for key: String in ["TeamClothes","Backpack","Nose","Glasses","Scarf","Moustache","Feather"]:
		get_node("%"+key).toggled.connect(_toggle.bind(key.to_snake_case()))
	for key: String in ["Garment","Face","Boots"]:
		get_node("%"+key).color_changed.connect(_color.bind(key.to_snake_case()))
	%Preview.gui_input.connect(_preview_input)
	%ResetAppearance.pressed.connect(func():
		var original_name: String = _draft.name
		var original_faction: int = _draft.faction
		_draft = HeroProfile.defaults()
		_draft.name = original_name
		_draft.faction = original_faction
		_fill_creator()
		_preview())
	%CancelCreator.pressed.connect(close_panels)
	%ApplyCreator.pressed.connect(func():
		if controller.create_or_update(_draft): close_panels())
	%Control.pressed.connect(controller.toggle_view)
	%Reload.pressed.connect(func():
		if controller.has_hero() and controller.game.running: controller.hero.weapon.begin_reload())
	%Edit.pressed.connect(open_creator)
	%Run.pressed.connect(controller.game.handle_pause_action)
	%Resume.pressed.connect(func(): controller._menu_was_running=true; close_panels())
	%ReturnRTS.pressed.connect(func(): close_panels(); controller.set_first_person(false))
	%Settings.pressed.connect(func(): controller.game.settings.open_menu())
	%BackMenu.pressed.connect(controller.game.return_to_menu)
	%InventoryButton.pressed.connect(open_inventory)
	%CloseInventory.pressed.connect(close_panels)
	%UseItem.pressed.connect(func(): use_item(_selected_item))
	%WeaponCard.pressed.connect(func():
		if controller.has_hero() and controller.game.running: controller.hero.weapon.begin_reload())
	%EquippedWeapon.pressed.connect(func(): _showing_weapon=true; refresh())
	%SortInventory.pressed.connect(func():
		controller.hero.inventory.sort_stacks()
		_selected_slot = -1
		refresh())
	get_viewport().size_changed.connect(_layout)
	for slot: HeroInventorySlot in %BagGrid.get_children():
		slot.pressed.connect(func():
			_showing_weapon = false
			_selected_slot = slot.slot_index
			_selected_item = slot.item_id()
			refresh())
	for bar: HBoxContainer in [%Hotbar,%BagHotbar]:
		for slot: Node in bar.get_children():
			if slot is HeroInventorySlot:
				slot.pressed.connect(use_shortcut.bind(slot.slot_index))
				slot.gui_input.connect(func(event: InputEvent):
					if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and controller.has_hero():
						controller.hero.inventory.assign(slot.slot_index,&"")
						refresh())
	set_process(true)
	set_first_person(false)

func open_creator() -> void:
	controller.begin_panel()
	_draft = controller.profile.duplicate()
	_fill_creator()
	%ApplyCreator.text = "保存形象" if controller.has_hero() else "创建英雄"
	%Creator.show()
	%Viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview()

func _fill_creator() -> void:
	_refreshing = true
	%PlayerName.text = _draft.name
	%Faction.select(_draft.faction)
	%TeamClothes.set_pressed_no_signal(_draft.team_clothes)
	%Expression.select(_draft.expression)
	%Headwear.select(_draft.headwear+1 if _draft.hat else 0)
	for key: String in ["Backpack","Nose","Glasses","Scarf","Moustache","Feather"]: get_node("%"+key).set_pressed_no_signal(_draft[key.to_snake_case()])
	for key: String in ["Garment","Face","Boots"]: get_node("%"+key).color = _draft[key.to_snake_case()]
	_refreshing = false

func _preview() -> void:
	if _refreshing: return
	%Model.set_team(FactionPalette.SANDBOX_OFFSET+_draft.faction)
	%Model.apply_appearance(_draft)
	%Garment.disabled = _draft.team_clothes

func _toggle(value: bool,key: String) -> void:
	if _refreshing: return
	_draft[key] = value
	_preview()

func _color(value: Color,key: String) -> void:
	if _refreshing: return
	_draft[key] = value
	_preview()

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT: _rotating = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var camera: Camera3D = %Viewport.get_node("Camera")
			camera.size = clampf(camera.size+(-.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .2),2.4,4.5)
	if event is InputEventMouseMotion and _rotating: %PreviewPivot.rotation.y += event.relative.x*.01

func close_panels() -> void:
	%Creator.hide()
	%Pause.hide()
	%Inventory.hide()
	%Viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	controller.end_panel()

func open_pause() -> void:
	controller.begin_panel()
	%Pause.show()

func hide_pause() -> void:
	%Pause.hide()

func set_first_person(value: bool) -> void:
	%WeaponView.visible = value
	%Crosshair.visible = value
	%FPSHint.visible = value
	%WeaponViewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	%Dock.get_node("Rows/Actions").visible = not value
	_layout()
	refresh()

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var factor: float = minf(1.0,minf(viewport_size.x/1600.0,viewport_size.y/900.0))
	for layout: Control in [%HudLayout,%InventoryLayout]:
		layout.scale = Vector2.ONE*factor
		layout.size = viewport_size/factor
	# The RTS minimap occupies the lower left; reserve that same native HUD area.
	var rts := controller != null and not controller.first_person
	%Vitals.position.x = (controller.game.hud.get_node("Sidebar").get_global_rect().end.x+24.0)/factor if rts else 48.0
	%Boost.position.x = %Vitals.position.x+276.0 if rts else 342.0
	%Loadout.offset_left = -74.0 if rts else -238.0
	%Loadout.offset_right = 654.0 if rts else 490.0

func refresh() -> void:
	if controller == null: return
	var show_weapon: bool = controller.first_person and not controller._menu_active
	%WeaponView.visible = controller.first_person and (not controller._menu_active or %Inventory.visible)
	%Crosshair.visible = show_weapon
	%FPSHint.visible = show_weapon
	%WeaponViewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_weapon else SubViewport.UPDATE_DISABLED
	%Dock.visible = controller.has_hero() and not controller._menu_active
	if not controller.has_hero(): return
	var hero := controller.hero
	%HeroName.text = hero.display_name
	%Health.text = "%d / %d" % [hero.hp,hero.max_hp]
	%HealthMeter.max_value = hero.max_hp
	%HealthMeter.value = hero.hp
	%Ammo.text = "%.1fs" % hero.weapon.reload_remaining if hero.weapon.reload_remaining>0.0 else "%02d / %02d" % [hero.weapon.rounds,hero.weapon.definition.magazine_size]
	%WeaponTitle.text = "装填中" if hero.weapon.reload_remaining>0.0 else hero.weapon.definition.display_name
	%ReloadMeter.visible = hero.weapon.reload_remaining>0.0
	%ReloadMeter.value = 1.0-hero.weapon.reload_remaining/hero.weapon.definition.reload_seconds
	%Armor.text = "护甲  %d / %d" % [hero._stats.melee_armor,hero._stats.ranged_armor]
	%Boost.visible = hero.speed_boost_remaining>0.0
	%BoostTime.text = "+%d%% · %ds" % [roundi((hero.speed_boost_multiplier-1.0)*100),ceili(hero.speed_boost_remaining)]
	%Control.text = "返回 RTS  F5" if controller.first_person else "操控英雄  F5"
	%Run.text = "暂停交战" if controller.game.running else "开始交战"
	%FPSHint.text = "F5  返回 RTS     I  背包     Esc  菜单" if controller.game.running else "模拟已暂停 · Esc 打开菜单继续交战"
	%Reload.disabled = not controller.game.running or hero.weapon.reload_remaining>0 or hero.weapon.rounds==10
	for bar: HBoxContainer in [%Hotbar,%BagHotbar]:
		if not bar.is_visible_in_tree(): continue
		for slot: Node in bar.get_children():
			if slot is HeroInventorySlot:
				slot.inventory = hero.inventory
				slot.key_prefix = "" if controller.first_person else "Alt+"
				slot.refresh()
	if %Inventory.visible:
		_refresh_inventory(hero)

func _refresh_inventory(hero: HeroUnit) -> void:
	%BagHeroName.text = hero.display_name
	%BagArmor.text = "护甲 %d / %d" % [hero._stats.melee_armor,hero._stats.ranged_armor]
	%BagSpeed.text = "移速 %.1f" % hero.speed
	%BagHealth.text = "%d / %d" % [hero.hp,hero.max_hp]
	%ShortcutHelp.text = "1–5 使用 · 右键解除绑定" if controller.first_person else "Alt + 1–5 使用 · 右键解除绑定"
	if _selected_slot>=0 and hero.inventory.slots[_selected_slot].id!=_selected_item: _selected_slot = -1
	for slot: HeroInventorySlot in %BagGrid.get_children():
		slot.inventory = hero.inventory
		if _selected_slot < 0 and slot.item_id()==_selected_item: _selected_slot = slot.slot_index
		slot.selected = not _showing_weapon and slot.slot_index==_selected_slot and not slot.item_id().is_empty()
		slot.refresh()
	var occupied: int = hero.inventory.slots.filter(func(slot: Dictionary):return slot.count>0).size()
	%BagCapacity.text = "背包  %d / %d" % [occupied,HeroInventory.CAPACITY]
	if _showing_weapon:
		var weapon := hero.weapon.definition
		%ItemArt.texture = %WeaponIconViewport.get_texture()
		%ItemArt.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		%ItemArt.custom_minimum_size.y = 160.0
		%ItemName.text = weapon.display_name
		%ItemKind.text = "已装备 · 远程武器"
		%ItemStock.text = "%d / %d 发" % [hero.weapon.rounds,weapon.magazine_size]
		%ItemDescription.text = "木质枪托与黄铜枪机。\n无限备弹，按 R 手动装填。"
		%ItemEffect.text = "攻击 %d + %d = %d" % [hero.attack_damage,weapon.attack_bonus,hero.attack_damage+weapon.attack_bonus]
		%ItemCooldown.text = "射程 %.0f · 间隔 %.2f 秒\n装填 %.1f 秒 · 弹匣 %d 发" % [weapon.range,weapon.interval,weapon.reload_seconds,weapon.magazine_size]
		%UseItem.hide()
		%ItemFootnote.text = "RTS 与第一人称共用弹匣。"
		return
	var item: HeroItemDefinition = HeroInventory.ITEMS.get(_selected_item)
	%ItemArt.texture = item.icon if item != null else null
	%ItemArt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	%ItemArt.custom_minimum_size.y = 128.0
	%ItemName.text = item.display_name if item != null else "选择一件物品"
	%ItemDescription.text = item.description if item != null else "选择背包中的物品查看效果。"
	%ItemKind.text = ("恢复用品" if item.effect==HeroItemDefinition.Effect.HEAL else "增益用品") if item != null else "物品详情"
	%ItemStock.text = "持有 %d" % hero.inventory.count(_selected_item) if item != null else ""
	var remaining: float = hero.inventory.cooldowns.get(_selected_item,0.0)
	%ItemEffect.text = ("恢复 %d 生命" % item.amount if item.effect==HeroItemDefinition.Effect.HEAL else "移速 +%d%% · 持续 %.0f 秒" % [roundi((item.amount-1.0)*100),item.duration]) if item != null else ""
	%ItemCooldown.text = ("冷却中 %.1f 秒" % remaining if remaining>0 else "共享冷却 %.0f 秒 · 每格 %d 瓶" % [item.cooldown,item.stack_limit]) if item != null else ""
	var no_effect := item != null and ((item.effect==HeroItemDefinition.Effect.HEAL and hero.hp>=hero.max_hp) or (item.effect==HeroItemDefinition.Effect.SPEED and hero.speed_boost_remaining>0))
	%UseItem.show()
	%UseItem.disabled = item==null or remaining>0 or hero.inventory.count(_selected_item)==0 or no_effect or not hero.alive
	%UseItem.text = "冷却中  %.1fs" % remaining if remaining>0 else ("生命值已满" if no_effect and item.effect==HeroItemDefinition.Effect.HEAL else ("加速效果持续中" if no_effect else "使用药剂"))
	%ItemFootnote.text = "拖入快捷位，可在战斗中使用。"

func open_inventory() -> void:
	if not controller.has_hero(): return
	controller.begin_panel()
	%Inventory.show()
	refresh()
	UIMotion.reveal(%Left,Vector2(-10,0))
	UIMotion.reveal(%Right,Vector2(10,0))

func use_shortcut(index: int) -> void:
	if not controller.has_hero(): return
	use_item(controller.hero.inventory.hotbar[index])

func use_item(id: StringName) -> void:
	if not controller.has_hero(): return
	var error := controller.hero.inventory.use(id,controller.hero)
	if not error.is_empty(): notice(error)
	else:
		controller.game.get_node("Audio").play_ui(&"select")
		refresh()

func set_hit_feedback(hit: bool) -> void:
	%Crosshair.text = "×" if hit else "+"
	%Crosshair.modulate = Color("ffc970") if hit else Color.WHITE

func update_weapon_pose(weapon: HeroWeaponRuntime) -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var desired := Vector2i(viewport_size*.75)
	if %WeaponViewport.size != desired: %WeaponViewport.size = desired
	var recoil := .065*pow(clampf(weapon.cooldown/weapon.definition.interval,0,1),4.0) if weapon.shots_fired>0 else 0.0
	var reload_pose := sin(PI*(1.0-weapon.reload_remaining/weapon.definition.reload_seconds)) if weapon.reload_remaining>0 else 0.0
	%GunPivot.position = Vector3(.32,-.29-.13*reload_pose,-.54+recoil)
	%GunPivot.rotation = Vector3(-.40*reload_pose,0,.12*reload_pose)
	%MuzzleFlash.visible = weapon.shots_fired>0 and weapon.definition.interval-weapon.cooldown < .045

func notice(message: String) -> void:
	%Notice.text = message
	_notice_time = 4.0

func _process(delta: float) -> void:
	_notice_time = maxf(0.0,_notice_time-delta)
	if _notice_time == 0.0: %Notice.text = ""
