extends CanvasLayer
## Scene-authored native controls with interruptible reveal / hover motion.
## Motion reference: GodotGameUI TweenManager's staggered fade and scale.

signal percentage_changed(value: int)
signal skill_requested(index: int, from_keyboard: bool)
signal pause_requested()
signal resume_requested()
signal restart_requested()
signal exit_requested()
signal upgrade_requested()
signal convert_requested(kind: int)

const PERCENTAGES: Array[int] = [100, 75, 50, 25]
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")

var _paused: bool = false
var _finished: bool = false
var _help_from_pause: bool = false
var _toast_tween: Tween
var _balance_tween: Tween
var _balance_target: float = -1.0
var _last_ready: Array[bool] = [false, false, false, false]
var _skills_initialized: bool = false
var _skill_buttons: Array[Button] = []
var _percentage_buttons: Array[Button] = []
var _selection_target: Node3D
var _selection_camera: Camera3D
var _selection_buildings: Array[Node3D] = []
var _selection_slot := -1
var _actions_visible: bool = false
var _pointer_blockers: Array[Control] = []
var _commander: StringName = &""
var _enemy_commander: StringName = &""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index: int in 4:
		var skill: Button = get_node("UI/Skills/Row/Skill%d" % index)
		_skill_buttons.append(skill)
		skill.gui_input.connect(_skill_gui_input.bind(index))
		var percent: Button = get_node("UI/Percentages/Stack/P%d" % PERCENTAGES[index])
		_percentage_buttons.append(percent)
		percent.pressed.connect(_select_percentage.bind(PERCENTAGES[index]))
	%Pause.pressed.connect(func(): pause_requested.emit())
	%Help.pressed.connect(_open_help)
	%Exit.pressed.connect(_open_exit)
	%Resume.pressed.connect(func(): resume_requested.emit())
	%PauseHelp.pressed.connect(_open_help)
	%PauseRestart.pressed.connect(func(): restart_requested.emit())
	%PauseExit.pressed.connect(func(): exit_requested.emit())
	%HelpClose.pressed.connect(_close_help)
	%ResultRestart.pressed.connect(func(): restart_requested.emit())
	%ResultExit.pressed.connect(func(): exit_requested.emit())
	%HintClose.pressed.connect(func(): UIMotion.dismiss(%QuickHint))
	%Upgrade.pressed.connect(func(): upgrade_requested.emit())
	%ConvertHouse.pressed.connect(func(): convert_requested.emit(0))
	%ConvertTower.pressed.connect(func(): convert_requested.emit(1))
	%ConvertForge.pressed.connect(func(): convert_requested.emit(2))
	for button: BaseButton in $UI.find_children("*", "BaseButton", true, false):
		_pointer_blockers.append(button)
	for panel: Control in [%PauseOverlay, %HelpOverlay, %ResultOverlay]:
		_pointer_blockers.append(panel)
	_pointer_blockers.append(%Selection)
	UIMotion.bind_buttons($UI)
	var panels: Array[Control] = [%Top, %Player, %Enemy, %Percentages, %Skills]
	for index: int in panels.size():
		var panel: Control = panels[index]
		panel.modulate.a = 0.0
		var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(float(index) * 0.06)
		tween.tween_callback(func():
			panel.modulate.a = 1.0
			UIMotion.reveal(panel, Vector2(0, 12))
		)

func update_state(state: Dictionary) -> void:
	var commander: StringName = state.commander
	var skill_names := SKILL_RULES.names_for(commander)
	var skill_cooldowns := SKILL_RULES.cooldowns_for(commander)
	if _commander != commander:
		_commander = commander
		$UI/Player/Icon.texture = SKILL_RULES.PORTRAITS[commander]
		for index: int in 4:
			_skill_buttons[index].get_node("Icon").texture = SKILL_RULES.icons_for(commander)[index]
	if _enemy_commander != state.enemy_commander:
		_enemy_commander = state.enemy_commander
		$UI/Enemy/Icon.texture = SKILL_RULES.PORTRAITS[_enemy_commander]
	var player_total: int = int(state.player_total)
	var enemy_total: int = int(state.enemy_total)
	%PlayerTotal.text = str(player_total)
	%EnemyTotal.text = str(enemy_total)
	%MapTitle.text = "%s · %s" % [state.map_title, state.map_mode]
	$UI/Player/Name.text = SKILL_RULES.name_for(commander)
	$UI/Enemy/Name.text = "敌方联盟" if state.team_size > 1 else SKILL_RULES.name_for(_enemy_commander)
	$UI/Enemy/Role.text = "%d 名电脑对手" % state.team_size
	var seconds: int = int(state.time)
	%Time.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	var target: float = float(player_total) / maxf(float(player_total + enemy_total), 1.0) * 100.0
	if not is_equal_approx(target, _balance_target):
		_balance_target = target
		if _balance_tween != null and _balance_tween.is_valid():
			_balance_tween.kill()
		_balance_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_balance_tween.tween_property(%Balance, "value", target, 0.28)
	for index: int in 4:
		_percentage_buttons[index].set_pressed_no_signal(PERCENTAGES[index] == int(state.percentage))
	%ForgeBonus.text = ("你的攻击  +%d%%" if state.team_size > 1 else "攻击加成  +%d%%") % (int(state.forges) * 10)
	_update_building_actions(state)
	var armed: int = int(state.armed_skill)
	%TargetHint.visible = armed >= 0
	if armed >= 0:
		var target_text := "拖至地面 · 松手即点燃 · 敌我均伤" if armed == 3 else ("拖至地面 · 圈内自己的部队加速" if armed == 1 else "拖至自己或盟友建筑 · 松手施放")
		if commander == SKILL_RULES.RABBIT:
			target_text = ["拖至地面 · 圈内自己的部队加速", "拖至敌方建筑 · 停工 6 秒", "拖至自己的建筑 · 召回附近部队", "拖至建筑 · 预览来源与出口"][armed]
		%TargetHint.text = "%s  ·  %s  /  右键取消" % [skill_names[armed], target_text]
	%SkillDrag.visible = armed >= 0
	if armed >= 0:
		%SkillDrag.get_node("Icon").texture = _skill_buttons[armed].get_node("Icon").texture
	var energy: float = float(state.energy)
	%EnergyBar.value = energy
	for index: int in 4:
		var button: Button = _skill_buttons[index]
		var cooldown: float = float(state.cooldowns[index])
		var duration: float = float(state.skill_durations[index])
		var cost: int = int(state.energy_costs[index])
		var cooling: bool = cooldown > 0.0
		var affordable: bool = energy >= cost
		var ready: bool = not cooling and affordable and not _paused and not _finished
		button.disabled = not ready
		button.set_pressed_no_signal(armed == index)
		button.get_node("Cooldown").value = cooldown / skill_cooldowns[index] * 100.0
		button.get_node("Cooldown").visible = cooling
		button.get_node("Seconds").text = str(ceili(cooldown)) if cooling else ""
		button.get_node("Cost").text = str(cost)
		var status := ""
		if duration > 0.0:
			status = "%s %ds" % [skill_names[index], ceili(duration)]
		elif armed == index:
			status = "选择地面" if SKILL_RULES.is_ground(index, commander) else "选择目标"
		elif cooling:
			status = "冷却 %ds" % ceili(cooldown)
		elif not affordable:
			status = "缺技力 %d" % ceili(cost - energy)
		button.get_node("Icon").visible = not cooling
		button.get_node("Icon").modulate.a = 1.0 if ready else 0.6
		button.get_node("ReadyLight").visible = ready
		if not ready:
			button.get_node("ReadyGlow").hide()
		button.set_hint(skill_names[index], SKILL_RULES.description(index, commander), cost, skill_cooldowns[index], energy, status, armed < 0)
		if ready and not _last_ready[index] and _skills_initialized:
			_pulse_ready(button)
		_last_ready[index] = ready
	_skills_initialized = true

func show_result(won: bool) -> void:
	_finished = true
	%PauseOverlay.hide()
	%HelpOverlay.hide()
	%ResultTitle.text = "胜利" if won else "战线失守"
	%ResultEyebrow.text = "积木战争  /  军团凯旋" if won else "积木战争  /  重整旗鼓"
	%ResultDetail.text = "敌方已失去全部据点与援军。山谷由你掌控。" if won else "所有据点与援军已失守。调整进军路线，再战一次。"
	%ResultOverlay.show()
	UIMotion.reveal(%ResultCard, Vector2(0, 28))

func show_draw() -> void:
	_finished = true
	%PauseOverlay.hide()
	%HelpOverlay.hide()
	%ResultTitle.text = "战局僵持"
	%ResultEyebrow.text = "积木战争  /  重整旗鼓"
	%ResultDetail.text = "双方均已没有可出征的民兵与产兵住宅。重整旗鼓，再战一局。"
	%ResultOverlay.show()
	UIMotion.reveal(%ResultCard, Vector2(0, 28))

func track_building(building: Node3D, camera: Camera3D, buildings: Array[Node3D]) -> void:
	if building != _selection_target:
		_selection_slot = -1
	_selection_target = building
	_selection_camera = camera
	_selection_buildings = buildings

func _process(_delta: float) -> void:
	_position_selection()

func set_skill_drag_target(valid: bool, screen: Vector2) -> void:
	%SkillDrag.position = $UI.get_global_transform_with_canvas().affine_inverse() * screen + Vector2(24, -48)
	%SkillDrag.get_node("Icon").modulate = Color("536541") if valid else Color("965342")

func _update_building_actions(state: Dictionary) -> void:
	_actions_visible = bool(state.selected_owned) and int(state.armed_skill) < 0
	var level := int(state.selected_level)
	var population := int(state.selected_population)
	var cost := int(state.upgrade_cost)
	var max_level := int(state.selected_max_level)
	var capped := level >= max_level
	var remaining := ceili(float(state.construction_remaining))
	var busy := remaining > 0
	var converting := int(state.conversion_target)
	var upgrading := busy and converting < 0
	%Upgrade.visible = int(state.selected_kind) != 2
	%Upgrade.get_node("NextLevel").text = str(mini(level + 1, max_level))
	%Upgrade.get_node("Cost/Population").visible = not capped and not upgrading
	var detail := "开工后剩余 %d 名驻军" % (population - cost)
	if population < cost:
		detail = "还差 %d 名驻军" % (cost - population)
	var upgrade_hint := "升级至 %d 级 · 耗时 10 秒\n消耗 %d 名驻军 · %s\n%s" % [level + 1, cost, detail, state.selected_detail]
	if int(state.selected_kind) == 1 and not capped:
		upgrade_hint += "\n完工后射程增加 2 米"
	var amount := str(cost)
	if capped:
		upgrade_hint = "已达 %d 级\n%s" % [max_level, state.selected_detail]
		amount = "—"
	elif upgrading:
		upgrade_hint = "正在升至 %d 级 · 还需 %d 秒\n施工期间维持当前等级，失守会中断\n%s" % [level + 1, remaining, state.selected_detail]
		amount = "%ds" % remaining
	elif busy:
		upgrade_hint = "正在改建%s · 还需 %d 秒\n完工前保留原建筑的功能和形态" % [["住宅", "炮塔", "铁匠铺"][converting], remaining]
	_update_action(%Upgrade, bool(state.can_upgrade), amount, upgrade_hint, not capped and not busy and population < cost)
	if upgrading:
		%Upgrade.get_node("Icon").modulate.a = 0.8
	var conversions: Array[Button] = [%ConvertHouse, %ConvertTower, %ConvertForge]
	for kind: int in conversions.size():
		var button := conversions[kind]
		button.visible = kind != int(state.selected_kind)
		var convert_cost := int(state.convert_cost)
		var hint := "改建%s · 消耗 %d 名驻军\n施工 10 秒，完工后重置至 1 级\n施工期间保留当前功能和形态" % [["住宅", "炮塔", "铁匠铺"][kind], convert_cost]
		if population < convert_cost:
			hint += "\n还差 %d 名驻军" % (convert_cost - population)
		var active_conversion := busy and kind == converting
		if busy:
			hint = "施工中 · 还需 %d 秒\n完工前保留当前功能和形态" % remaining
		button.get_node("Cost/Population").visible = not active_conversion
		_update_action(button, bool(state.selected_owned) and not busy and population >= convert_cost, "%ds" % remaining if active_conversion else str(convert_cost), hint, not busy and population < convert_cost)
		if active_conversion:
			button.get_node("Icon").modulate.a = 0.8
	%BuildingActions.size = %BuildingActions.get_combined_minimum_size()
	%Selection.size = %BuildingActions.size + Vector2(6.0, 0.0)
	_position_selection()

func _update_action(button: Button, available: bool, cost: String, hint: String, shortfall: bool) -> void:
	button.disabled = not available or _paused or _finished
	button.tooltip_text = hint
	button.get_node("Icon").modulate.a = 0.45 if button.disabled else 1.0
	var amount: Label = button.get_node("Cost/Amount")
	amount.text = cost
	amount.add_theme_color_override("font_color", Color("ffb19a") if shortfall else Color("fff7cf"))

func _position_selection() -> void:
	%Selection.visible = _selection_target != null and _actions_visible and not _paused and not _finished
	if not %Selection.visible:
		return
	var world := _selection_target.global_position + Vector3(0, 2.5, 0)
	if _selection_camera.is_position_behind(world):
		%Selection.hide()
		return
	# Native camera projection returns viewport coordinates; the HUD may be scaled.
	var to_ui: Transform2D = $UI.get_global_transform_with_canvas().affine_inverse()
	var anchor: Vector2 = to_ui * _selection_camera.unproject_position(world)
	if not Rect2(Vector2.ZERO, $UI.size).has_point(anchor):
		%Selection.hide()
		return
	var extent: Vector2 = to_ui * _selection_camera.unproject_position(world + _selection_camera.global_basis.x * 3.0)
	var gap: float = absf(extent.x - anchor.x) + 3.0
	var menu_size: Vector2 = %Selection.size
	var bounds := Rect2(Vector2(16, 64), Vector2($UI.size.x - 32.0, %Skills.position.y - 88.0))
	var percentage_rect: Rect2 = %Percentages.get_global_rect().grow_side(SIDE_RIGHT, 40.0)
	var obstacles: Array[Rect2] = []
	# A compact side menu must not cover a neighboring building or its population.
	for building: Node3D in _selection_buildings:
		var center: Vector2 = to_ui * _selection_camera.unproject_position(building.global_position + Vector3(0, 3.5, 0))
		obstacles.append(Rect2(center - Vector2(gap, gap * 0.85), Vector2(gap * 2.0, gap * 1.7)))
	var placements: Array[Vector2] = []
	var best_slot := 0
	var best_score := INF
	for side: float in [1.0, -1.0]:
		for rise: float in [0.0, -1.0, 1.0]:
			var candidate := anchor + Vector2(gap if side > 0.0 else -gap - menu_size.x, -menu_size.y * 0.5 + rise * (menu_size.y + 18.0))
			candidate = candidate.clamp(bounds.position, bounds.end - menu_size)
			var rect := Rect2(candidate, menu_size)
			var score := rect.get_center().distance_squared_to(anchor)
			# Keep the current slot through small camera/layout changes. Its 8 px
			# inset is a spatial dead band, not a delay that can expire mid-click.
			if placements.size() == _selection_slot:
				rect = rect.grow(-8.0)
				score -= 6000.0
			score += 1000.0 if side < 0.0 else 0.0
			score += rect.intersection(percentage_rect).get_area() * 10000.0
			for obstacle: Rect2 in obstacles:
				score += rect.intersection(obstacle).get_area() * 100.0
			if score < best_score:
				best_score = score
				best_slot = placements.size()
			placements.append(candidate)
	# Do not move the actions to a different slot while the player aims at them.
	var pointer: Vector2 = to_ui * get_viewport().get_mouse_position()
	if _selection_slot < 0 or not %Selection.get_rect().grow(4.0).has_point(pointer):
		_selection_slot = best_slot
	%Selection.position = placements[_selection_slot].round()
	# A fine leader keeps an offset menu visibly attached to its own building.
	var on_right: bool = %Selection.position.x > anchor.x
	%BuildingActions.position.x = 6.0 if on_right else 0.0
	var start: Vector2 = anchor - %Selection.position + Vector2(gap - 3.0 if on_right else 3.0 - gap, 0)
	var end := Vector2(4.0 if on_right else menu_size.x - 4.0, 33.0)
	$UI/Selection/Connector.points = PackedVector2Array([start, Vector2(end.x, start.y), end])

func _pulse_ready(button: Button) -> void:
	var glow: Control = button.get_node("ReadyGlow")
	glow.pivot_offset = glow.size * 0.5
	glow.scale = Vector2.ONE
	glow.modulate.a = 0.45
	glow.show()
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_parallel(true)
	tween.tween_property(glow, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(glow.hide)

func set_paused(value: bool) -> void:
	_paused = value
	if _finished:
		return
	if value:
		%PauseOverlay.show()
		%Resume.grab_focus(true)
		UIMotion.reveal(%PauseCard, Vector2(0, 18))
	else:
		%PauseOverlay.hide()
		%HelpOverlay.hide()

func notify(message: String) -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	%ToastText.text = message
	UIMotion.reveal(%Toast, Vector2(0, -8))
	_toast_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_interval(2.8)
	_toast_tween.tween_callback(func(): UIMotion.dismiss(%Toast, Vector2(0, -6)))

func is_pointer_blocked(screen: Vector2) -> bool:
	# _input runs before GUI hover updates. Test this event's position, not the
	# previous hovered control, and ignore transparent layout containers.
	for control: Control in _pointer_blockers:
		if control.is_visible_in_tree():
			var local := control.get_global_transform_with_canvas().affine_inverse() * screen
			if Rect2(Vector2.ZERO, control.size).has_point(local):
				return true
	return false

func help_visible() -> bool:
	return %HelpOverlay.visible

func _select_percentage(value: int) -> void:
	if not _paused and not _finished:
		percentage_changed.emit(value)

func _skill_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _skill_buttons[index].disabled:
		_request_skill(index, false)
		_skill_buttons[index].accept_event()

func _request_skill(index: int, from_keyboard: bool) -> void:
	# Keyboard requests reach the controller even while a card is unavailable,
	# so its actual cooldown or energy shortfall produces the same clear feedback.
	if not _paused and not _finished:
		skill_requested.emit(index, from_keyboard)

func _open_help() -> void:
	_help_from_pause = _paused
	if not _paused:
		pause_requested.emit()
	%PauseOverlay.hide()
	%HelpOverlay.show()
	%HelpClose.grab_focus(true)
	UIMotion.reveal(%HelpCard, Vector2(0, 20))

func _close_help() -> void:
	%HelpOverlay.hide()
	if _help_from_pause:
		%PauseOverlay.show()
		%PauseHelp.grab_focus(true)
		UIMotion.reveal(%PauseCard)
	else:
		resume_requested.emit()

func _open_exit() -> void:
	pause_requested.emit()
	%PauseExit.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code == KEY_F1 and not _finished:
		if %HelpOverlay.visible:
			_close_help()
		else:
			_open_help()
		get_viewport().set_input_as_handled()
		return
	if code == KEY_ESCAPE:
		if _finished:
			return
		if %HelpOverlay.visible:
			_close_help()
		elif _paused:
			resume_requested.emit()
		else:
			pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if _paused or _finished:
		return
	var skill_keys: Array[int] = [KEY_Q, KEY_W, KEY_E, KEY_R]
	var index: int = skill_keys.find(code)
	if index >= 0:
		_request_skill(index, true)
		get_viewport().set_input_as_handled()
	var percentage_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4]
	index = percentage_keys.find(code)
	if index >= 0:
		_select_percentage([25, 50, 75, 100][index % 4])
		get_viewport().set_input_as_handled()
