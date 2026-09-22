extends CanvasLayer
## Scene-authored native controls with interruptible reveal / hover motion.
## Motion reference: GodotGameUI TweenManager's staggered fade and scale.

signal percentage_changed(value: int)
signal skill_requested(index: int)
signal pause_requested()
signal resume_requested()
signal restart_requested()
signal exit_requested()
signal upgrade_requested()
signal convert_requested(kind: int)

const PERCENTAGES: Array[int] = [100, 75, 50, 25]
const SKILL_NAMES: Array[String] = ["征召军令", "疾行战鼓", "磐石壁垒", "天降冲击"]
const COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 60.0]

var _paused: bool = false
var _finished: bool = false
var _help_from_pause: bool = false
var _toast_tween: Tween
var _balance_tween: Tween
var _balance_target: float = -1.0
var _last_selected: String = ""
var _last_cooldowns: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _skill_buttons: Array[Button] = []
var _percentage_buttons: Array[Button] = []
var _managing: bool = false
var _selected_owned: bool = false
var _pointer_blockers: Array[Control] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index: int in 4:
		var skill: Button = get_node("UI/Skills/Row/Skill%d" % index)
		_skill_buttons.append(skill)
		skill.pressed.connect(_request_skill.bind(index))
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
	%Manage.pressed.connect(_toggle_management)
	%Upgrade.pressed.connect(func(): upgrade_requested.emit())
	%ConvertHouse.pressed.connect(func(): convert_requested.emit(0))
	%ConvertTower.pressed.connect(func(): convert_requested.emit(1))
	%ConvertForge.pressed.connect(func(): convert_requested.emit(2))
	for button: BaseButton in $UI.find_children("*", "BaseButton", true, false):
		_pointer_blockers.append(button)
	for panel: Control in [%ManagementBackdrop, %PauseOverlay, %HelpOverlay, %ResultOverlay]:
		_pointer_blockers.append(panel)
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
	var player_total: int = int(state.player_total)
	var enemy_total: int = int(state.enemy_total)
	%PlayerTotal.text = str(player_total)
	%EnemyTotal.text = str(enemy_total)
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
	%SendAmount.visible = bool(state.selected_owned)
	%SendAmount.text = "派出 %d 人 · %d%%   [1–4] 切换" % [int(state.send_count), int(state.percentage)]
	%ForgeBonus.text = "锻造加成  +%d%%" % (int(state.forges) * 10)
	var selected_name: String = str(state.selected_name)
	%Selection.visible = not selected_name.is_empty()
	if not selected_name.is_empty():
		%SelectedName.text = "%s · %d 级" % [selected_name, int(state.selected_level)]
		%SelectedPopulation.text = "%d" % int(state.selected_population)
		%SelectedDetail.text = str(state.selected_detail)
		%Manage.tooltip_text = str(state.selected_detail)
		if selected_name != _last_selected:
			_managing = false
			%Manage.set_pressed_no_signal(false)
			UIMotion.reveal(%Selection, Vector2(0, 5))
		var owned: bool = bool(state.get("selected_owned", false))
		_selected_owned = owned
		%Manage.visible = owned
		_refresh_management()
		if owned:
			var kind: int = int(state.selected_kind)
			%Upgrade.text = "升级 · %d 人口" % int(state.upgrade_cost)
			%Upgrade.disabled = not bool(state.can_upgrade)
			if int(state.selected_level) >= 3:
				%Upgrade.text = "已达最高等级"
			%ConvertHouse.disabled = kind == 0 or int(state.selected_population) < int(state.convert_cost)
			%ConvertTower.disabled = kind == 1 or int(state.selected_population) < int(state.convert_cost)
			%ConvertForge.disabled = kind == 2 or int(state.selected_population) < int(state.convert_cost)
	_last_selected = selected_name
	var armed: int = int(state.armed_skill)
	%TargetHint.visible = armed >= 0
	if armed >= 0:
		%TargetHint.text = "%s  ·  点击目标建筑  /  右键取消" % SKILL_NAMES[armed]
	for index: int in 4:
		var button: Button = _skill_buttons[index]
		var cooldown: float = float(state.cooldowns[index])
		var duration: float = float(state.skill_durations[index])
		var cooling: bool = cooldown > 0.0
		button.disabled = cooling or _paused or _finished
		button.set_pressed_no_signal(armed == index)
		button.get_node("Cooldown").value = cooldown / COOLDOWNS[index] * 100.0
		button.get_node("Cooldown").visible = cooling
		button.get_node("Seconds").text = str(ceili(cooldown)) if cooling else ""
		button.get_node("Name").text = "%s %ds" % [["", "疾行", "壁垒", ""][index], ceili(duration)] if duration > 0.0 else "选择目标" if armed == index else SKILL_NAMES[index]
		button.get_node("Status").hide()
		button.get_node("Name").add_theme_color_override("font_color", Color("c2c1ab") if cooling else Color("f4efd8"))
		button.get_node("Key").add_theme_color_override("font_color", Color("e4e1cb") if cooling else Color("384032"))
		button.get_node("Icon").modulate.a = 0.42 if cooling else 1.0
		if _last_cooldowns[index] > 0.0 and not cooling:
			_pulse_ready(button)
		_last_cooldowns[index] = cooldown

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

func _toggle_management() -> void:
	_managing = %Manage.button_pressed
	_refresh_management()
	if _managing:
		UIMotion.reveal(%ManagementBackdrop, Vector2(0, 6))
		UIMotion.reveal(%BuildingActions)

func _refresh_management() -> void:
	var opened: bool = _managing and _selected_owned
	%BuildingActions.visible = opened
	%ManagementBackdrop.visible = opened
	%SelectedDetail.visible = opened

func _pulse_ready(button: Button) -> void:
	var glow: Control = button.get_node("ReadyGlow")
	glow.pivot_offset = glow.size * 0.5
	glow.scale = Vector2.ONE
	glow.modulate.a = 1.0
	glow.show()
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_parallel(true)
	tween.tween_property(glow, "scale", Vector2(1.32, 1.32), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(glow.hide)

func set_paused(value: bool) -> void:
	_paused = value
	if _finished:
		return
	if value:
		%PauseOverlay.show()
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

func _request_skill(index: int) -> void:
	if not _paused and not _finished and not _skill_buttons[index].disabled:
		skill_requested.emit(index)

func _open_help() -> void:
	_help_from_pause = _paused
	if not _paused:
		pause_requested.emit()
	%PauseOverlay.hide()
	%HelpOverlay.show()
	UIMotion.reveal(%HelpCard, Vector2(0, 20))

func _close_help() -> void:
	%HelpOverlay.hide()
	if _help_from_pause:
		%PauseOverlay.show()
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
		_request_skill(index)
		get_viewport().set_input_as_handled()
	var percentage_keys: Array[int] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4]
	index = percentage_keys.find(code)
	if index >= 0:
		_select_percentage([25, 50, 75, 100][index % 4])
		get_viewport().set_input_as_handled()
