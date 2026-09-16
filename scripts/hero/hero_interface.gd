extends CanvasLayer
var controller: SandboxHeroController
var _draft: Dictionary
var _refreshing := false
var _rotating := false
var _notice_time := 0.0
var _selected_item: StringName = &"healing_potion"

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
	for slot: HeroInventorySlot in %BagGrid.get_children():
		slot.pressed.connect(func():
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
	%Dock.anchor_left = .5 if value else 0.0
	%Dock.anchor_right = .5 if value else 1.0
	%Dock.offset_left = -350 if value else 314
	%Dock.offset_right = 350 if value else -16
	%Dock.offset_top = -169 if value else -213
	%Dock.offset_bottom = -45
	%Dock.get_node("Rows/Actions").visible = not value
	refresh()

func refresh() -> void:
	if controller == null: return
	var show_weapon: bool = controller.first_person and not controller._menu_active
	%WeaponView.visible = show_weapon
	%Crosshair.visible = show_weapon
	%FPSHint.visible = show_weapon
	%WeaponViewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_weapon else SubViewport.UPDATE_DISABLED
	%Dock.visible = controller.has_hero() and not controller._menu_active
	if not controller.has_hero(): return
	var hero := controller.hero
	%HeroName.text = hero.display_name
	%Health.text = "生命 %d / %d" % [hero.hp,hero.max_hp]
	%HealthMeter.max_value = hero.max_hp
	%HealthMeter.value = hero.hp
	%Ammo.text = "装填中 %.1f 秒" % hero.weapon.reload_remaining if hero.weapon.reload_remaining>0.0 else "%02d / 10 · 无限备弹" % hero.weapon.rounds
	%Control.text = "返回 RTS  F5" if controller.first_person else "操控英雄  F5"
	%Run.text = "暂停交战" if controller.game.running else "开始交战"
	%FPSHint.text = "WASD 移动 · 左键开火 · R 换弹 · Space 跳跃 · F5 返回 · Esc 菜单" if controller.game.running else "模拟已暂停 · Esc 打开菜单继续交战"
	%Reload.disabled = not controller.game.running or hero.weapon.reload_remaining>0 or hero.weapon.rounds==10
	for bar: HBoxContainer in [%Hotbar,%BagHotbar]:
		for slot: Node in bar.get_children():
			if slot is HeroInventorySlot:
				slot.inventory = hero.inventory
				slot.refresh()
	if %Inventory.visible:
		for slot: HeroInventorySlot in %BagGrid.get_children():
			slot.inventory = hero.inventory
			slot.refresh()
		var occupied: int = hero.inventory.slots.filter(func(slot: Dictionary):return slot.count>0).size()
		%BagCapacity.text = "%d / 24 格" % occupied
		var item: HeroItemDefinition = HeroInventory.ITEMS.get(_selected_item)
		%ItemArt.texture = item.icon if item != null else null
		%ItemName.text = item.display_name if item != null else "选择一件物品"
		%ItemDescription.text = item.description if item != null else "选择背包中的物品查看效果。"
		var remaining: float = hero.inventory.cooldowns.get(_selected_item,0.0)
		%ItemCooldown.text = "冷却 %.1f 秒" % remaining if remaining>0 else ""
		%UseItem.disabled = item==null or remaining>0 or hero.inventory.count(_selected_item)==0

func open_inventory() -> void:
	if not controller.has_hero(): return
	controller.begin_panel()
	%Inventory.show()
	refresh()

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
