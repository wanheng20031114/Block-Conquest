extends CanvasLayer
## Scene-authored native controls with interruptible reveal / hover motion.
## Motion reference: GodotGameUI TweenManager's staggered fade and scale.

signal percentage_changed(value: int)
signal skill_requested(index: int, from_keyboard: bool)
signal pause_requested()
signal resume_requested()
signal match_pause_requested(paused: bool)
signal surrender_requested()
signal restart_requested()
signal exit_requested()
signal upgrade_requested()
signal convert_requested(kind: int)
signal ui_sound_requested(kind: StringName)
signal debug_refresh_requested()
signal debug_visibility_changed(visible: bool)

const PERCENTAGES: Array[int] = [100, 75, 50, 25]
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const BUILDING_NAMES := WarBuilding.KIND_NAMES

var _paused: bool = false
var _finished: bool = false
var _help_from_pause: bool = false
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
var _online_menu := false
var _online_action := ""
var _global_paused := false
var _local_surrendered := false
var _can_match_pause := false
var _can_surrender := false
var _pause_actor_name := ""
var _hosting := false
var _public_skill_layout_count := 0

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
	%MatchPause.pressed.connect(_request_match_pause)
	%Surrender.pressed.connect(_request_surrender)
	%PauseHelp.pressed.connect(_open_help)
	%PauseSettings.pressed.connect(_open_settings)
	get_node("/root/Session/Settings").closed.connect(_settings_closed)
	%PauseRestart.pressed.connect(_request_restart)
	%PauseExit.pressed.connect(_request_exit)
	%HelpClose.pressed.connect(_close_help)
	%ResultRestart.pressed.connect(_request_restart)
	%ResultExit.pressed.connect(_request_exit)
	%OnlineConfirm.get_node("Center/Card/Column/Actions/Cancel").pressed.connect(_cancel_online_action)
	%OnlineConfirm.get_node("Center/Card/Column/Actions/Confirm").pressed.connect(_confirm_online_action)
	var online: Node = get_node("/root/Session/Online")
	_online_menu = not online.match_config.is_empty()
	if _online_menu:
		_configure_online_menu(online)
	%DebugPanel.close_requested.connect(set_debug_visible.bind(false))
	%DebugRefresh.timeout.connect(func(): debug_refresh_requested.emit())
	%Upgrade.pressed.connect(func(): upgrade_requested.emit())
	%ConvertHouse.pressed.connect(func(): convert_requested.emit(0))
	%ConvertTower.pressed.connect(func(): convert_requested.emit(1))
	%ConvertForge.pressed.connect(func(): convert_requested.emit(2))
	%ConvertEnergy.pressed.connect(func(): convert_requested.emit(3))
	for button: BaseButton in $UI.find_children("*", "BaseButton", true, false):
		_pointer_blockers.append(button)
	for panel: Control in [%PauseOverlay, %HelpOverlay, %ResultOverlay, %OnlineConfirm]:
		_pointer_blockers.append(panel)
	_pointer_blockers.append(%Selection)
	_pointer_blockers.append(%EnergyBar)
	_pointer_blockers.append(%DebugPanel)
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
	_update_match_controls(state)
	var commander: StringName = state.commander
	var local_faction := int(state.get("local_faction", 0))
	var skill_names := SKILL_RULES.names_for(commander)
	var skill_cooldowns := SKILL_RULES.cooldowns_for(commander)
	if _commander != commander:
		_commander = commander
		$UI/Player/Icon.texture = SKILL_RULES.PORTRAITS[commander]
		%PausePortrait.texture = SKILL_RULES.PORTRAITS[commander]
		%ResultPortrait.texture = SKILL_RULES.PORTRAITS[commander]
		for index: int in 4:
			_skill_buttons[index].get_node("Icon").texture = SKILL_RULES.icons_for(commander)[index]
	if _enemy_commander != state.enemy_commander:
		_enemy_commander = state.enemy_commander
		$UI/Enemy/Icon.texture = SKILL_RULES.PORTRAITS[_enemy_commander]
	var player_total: int = int(state.player_total)
	%PlayerTotal.text = str(player_total)
	%EnemyTotal.text = str(int(state.enemy_total))
	# Ink sits directly on the faction colors; an empty rail has a dark surface.
	var has_troops: bool = state.faction_totals.any(func(count: int) -> bool: return count > 0)
	var count_ink := Color(0.055, 0.12, 0.095) if has_troops else Color(0.99, 1, 0.97)
	%PlayerTotal.add_theme_color_override("font_color", count_ink)
	%EnemyTotal.add_theme_color_override("font_color", count_ink)
	$UI/Player/Name.text = SKILL_RULES.name_for(commander)
	$UI/Enemy/Name.text = "敌方联盟" if state.team_size > 1 else SKILL_RULES.name_for(_enemy_commander)
	$UI/Enemy/Role.text = state.get("enemy_role", "%d 名电脑对手" % state.team_size)
	var duel: bool = int(state.faction_count) == 2
	$UI/Enemy/Role.visible = not duel
	$UI/Enemy/Skills.visible = duel
	if duel:
		var enemy_faction: int = 1 - local_faction
		$UI/Enemy/Skills.update_skills(state.faction_commanders[enemy_faction], state.faction_skill_statuses[enemy_faction], state.faction_names[enemy_faction], state.faction_skill_active[enemy_faction])
		if bool(state.get("online", false)):
			$UI/Enemy/Name.text = state.faction_names[enemy_faction]
	var seconds: int = int(state.time)
	%Time.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	%Balance.update_factions(state.faction_totals, state.morale_stars, int(state.faction_count), local_faction, state.get("faction_names", []))
	%Balance.update_skills(state.faction_commanders, state.faction_skill_statuses, state.faction_names, state.faction_skill_active)
	if _public_skill_layout_count != int(state.faction_count):
		_public_skill_layout_count = int(state.faction_count)
		# Team matches show individual totals above morale and skills below it.
		var player_row_space: float = 0.0 if duel else 48.0
		%Time.position.y = 54.0 + player_row_space
		%MatchStatus.position.y = 128.0 + player_row_space
	for index: int in 4:
		_percentage_buttons[index].set_pressed_no_signal(PERCENTAGES[index] == int(state.percentage))
		_percentage_buttons[index].disabled = _global_paused or _local_surrendered or _finished
	_update_building_actions(state)
	var armed: int = int(state.armed_skill)
	%TargetHint.visible = armed >= 0
	if armed >= 0:
		var target_text := "拖至地面 · 松手即点燃 · 敌我均伤" if armed == 3 else ("拖至地面 · 圈内己军移速 +%d%%，持续 %d 秒" % [roundi((SKILL_RULES.HASTE_MULTIPLIER - 1.0) * 100.0), SKILL_RULES.DURATIONS[1]] if armed == 1 else "拖至自己或盟友建筑 · 松手施放")
		if commander == SKILL_RULES.RABBIT:
			target_text = ["圈选自己的行军 · 攻击力 +%d%%、移速 +%d%%，持续 %d 秒" % [roundi(SKILL_RULES.RABBIT_RUSH_ATTACK_BONUS * 100.0), roundi((SKILL_RULES.RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), SKILL_RULES.RABBIT_DURATIONS[0]], "拖至敌方建筑 · 停工 6 秒", "拖至地面 · 双方部队各自返回出发建筑", "拖至自己的建筑 · 15 秒内下次出兵走兔洞"][armed]
		elif commander == SKILL_RULES.BEAR:
			target_text = ["拖至自己或盟友的施工建筑 · 立即完工并返还 50% 人口", "拖至地面 · 圈内敌军移速 -60%，持续 4 秒", "拖至自己或盟友建筑 · 预览同队连线后松手", "拖至自己或盟友建筑 · 防御力 +100%，持续 5 秒并召唤法球"][armed]
		elif commander == SKILL_RULES.FROG:
			target_text = ["拖至地面 · 敌军攻击力 -20%，持续至进入建筑；雾内避开炮塔", "圈选双方士兵 · 滞空 3 秒", "圈选己方士兵 · 隐身至进入建筑，避开炮塔", "拖至敌方或中立建筑 · 削减 80% 驻军并降至 1 级"][armed]
		%TargetHint.text = "%s  ·  %s  /  右键取消" % [skill_names[armed], target_text]
	%SkillDrag.visible = armed >= 0
	if armed >= 0:
		%SkillDrag.get_node("Icon").texture = _skill_buttons[armed].get_node("Icon").texture
	var energy: float = float(state.energy)
	%EnergyBar.value = energy
	var combat_regen: float = SKILL_RULES.combat_energy_per_loss(float(state.morale_stars[local_faction]))
	%EnergyBar.tooltip_text = "%.2f / %d 技力\n当前恢复 +%.2f 点/秒 · %d 座有效能量塔\n自然恢复：前 %d 秒 +%d 点/秒，之后 +%d 点/秒\n建筑交战每损失 1 人：当前技力 +%.2f\n士气不足 3 星：+0.20；3 星至不足 5 星：+0.15；5 星：+0.10\n技能直接杀伤、路上伤亡不计；收益按玩家独立计算。" % [energy, int(state.energy_max), float(state.energy_regen), int(state.energy_tower_count), SKILL_RULES.ENERGY_ACCELERATION_TIME, SKILL_RULES.ENERGY_REGEN, SKILL_RULES.ENERGY_LATE_REGEN, combat_regen]
	for index: int in 4:
		var button: Button = _skill_buttons[index]
		var cooldown: float = float(state.cooldowns[index])
		var duration: float = float(state.skill_durations[index])
		var cost: int = int(state.energy_costs[index])
		var cooling: bool = cooldown > 0.0
		var affordable: bool = energy >= cost
		var ready: bool = not cooling and affordable and not _paused and not _finished and not _global_paused and not _local_surrendered
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
	%MatchStatus.hide()
	%OnlineConfirm.hide()
	_online_action = ""
	%PauseOverlay.hide()
	%HelpOverlay.hide()
	%ResultTitle.text = "胜利" if won else "战线失守"
	%ResultEyebrow.text = "积木战争  /  军团凯旋" if won else "积木战争  /  重整旗鼓"
	%ResultDetail.text = "敌方已失去全部据点与援军。山谷由你掌控。" if won else "所有据点与援军已失守。调整进军路线，再战一次。"
	%ResultOverlay.show()
	UIMotion.reveal(%ResultCard, Vector2(0, 28))

func show_draw() -> void:
	_finished = true
	%MatchStatus.hide()
	%OnlineConfirm.hide()
	_online_action = ""
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
	_actions_visible = bool(state.selected_owned) and int(state.armed_skill) < 0 and not _global_paused and not _local_surrendered
	var level := int(state.selected_level)
	var population := int(state.selected_available_population)
	var cost := int(state.upgrade_cost)
	var max_level := int(state.selected_max_level)
	var capped := level >= max_level
	var remaining := ceili(float(state.construction_remaining))
	var busy := remaining > 0
	var converting := int(state.conversion_target)
	var upgrading := busy and converting < 0
	%Upgrade.visible = int(state.selected_kind) in [0, 1]
	%Upgrade.get_node("NextLevel").text = str(mini(level + 1, max_level))
	%Upgrade.get_node("Cost/Population").visible = not capped and not upgrading
	var detail := "开工后剩余 %d 名可用驻军" % (population - cost)
	if population < cost:
		detail = "还差 %d 名驻军" % (cost - population)
	var duration := WarBuilding.upgrade_duration(int(state.selected_kind), level)
	var upgrade_hint := "升级至 %d 级 · 耗时 %d 秒\n消耗 %d 名驻军 · %s\n%s" % [level + 1, duration, cost, detail, state.selected_detail]
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
		upgrade_hint = "正在改建%s · 还需 %d 秒\n完工前保留原建筑的功能和形态" % [BUILDING_NAMES[converting], remaining]
	_update_action(%Upgrade, bool(state.can_upgrade), amount, upgrade_hint, not capped and not busy and population < cost)
	if upgrading:
		%Upgrade.get_node("Icon").modulate.a = 0.8
	var conversions: Array[Button] = [%ConvertHouse, %ConvertTower, %ConvertForge, %ConvertEnergy]
	for kind: int in conversions.size():
		var button := conversions[kind]
		var allowed := kind != int(state.selected_kind) and (kind != 3 or int(state.selected_kind) == 2)
		button.visible = allowed
		var convert_cost := int(state.convert_cost)
		var hint := "改建%s · 消耗 %d 名驻军\n施工 10 秒，完工后重置至 1 级\n施工期间保留当前功能和形态" % [BUILDING_NAMES[kind], convert_cost]
		if kind == 3:
			hint = "改建能量塔 · 消耗 %d 名驻军 · 施工 10 秒\n第 1 / 2 / 3 座额外恢复 +0.5 / +0.25 / +0.15 技力/秒；\n第 4 座起，每座额外 +0.1 技力/秒。\n本塔出征部队每次夺取敌方建筑 +10 技力，\n中立建筑除外，奖励不随塔数叠加。\n不产兵、不可升级；技力上限 100。" % convert_cost
		if population < convert_cost:
			hint += "\n还差 %d 名驻军" % (convert_cost - population)
		var active_conversion := busy and kind == converting
		if busy:
			hint = "施工中 · 还需 %d 秒\n完工前保留当前功能和形态" % remaining
		button.get_node("Cost/Population").visible = not active_conversion
		_update_action(button, allowed and bool(state.selected_owned) and not busy and population >= convert_cost, "%ds" % remaining if active_conversion else str(convert_cost), hint, not busy and population < convert_cost)
		if active_conversion:
			button.get_node("Icon").modulate.a = 0.8
	%BuildingActions.size = %BuildingActions.get_combined_minimum_size()
	%Selection.size = %BuildingActions.size + Vector2(6.0, 0.0)
	_position_selection()

func _update_action(button: Button, available: bool, cost: String, hint: String, shortfall: bool) -> void:
	button.disabled = not available or _paused or _finished or _global_paused or _local_surrendered
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
	var bounds := Rect2(Vector2(16, 96), Vector2($UI.size.x - 32.0, %Skills.position.y - 120.0))
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
	_refresh_match_status()

func set_network_status(message: String, detail: String = "") -> void:
	# Waiting/recovery lasts until authority confirms it.
	if message.is_empty():
		%OnlineStatus.hide()
		_refresh_match_status()
		return
	var changed: bool = %OnlineStatusTitle.text != message
	%OnlineStatusTitle.text = message
	%OnlineStatusDetail.text = detail
	%OnlineStatusDetail.visible = not detail.is_empty()
	%OnlineStatus.show()
	_refresh_match_status()
	if changed:
		UIMotion.reveal(%OnlineStatus, Vector2(0, -8))

func is_pointer_blocked(screen: Vector2) -> bool:
	# _input runs before GUI hover updates. Test this event's position, not the
	# previous hovered control, and ignore transparent layout containers.
	for control: Control in _pointer_blockers:
		if control.is_visible_in_tree():
			var local := control.get_global_transform_with_canvas().affine_inverse() * screen
			if Rect2(Vector2.ZERO, control.size).has_point(local):
				return true
	return false

func is_pointer_over_hud(screen: Vector2) -> bool:
	# Presence is hidden over informational HUD too. These non-interactive panels
	# still permit ordinary battlefield input according to is_pointer_blocked.
	if is_pointer_blocked(screen):
		return true
	for control: Control in [%Top, %Player, %Enemy, %Percentages, %Skills, %OnlineStatus, %MatchStatus]:
		if control.is_visible_in_tree():
			var local := control.get_global_transform_with_canvas().affine_inverse() * screen
			if Rect2(Vector2.ZERO, control.size).has_point(local):
				return true
	return false

func debug_visible() -> bool:
	return %DebugPanel.visible

func _debug_shortcut() -> String:
	for event: InputEvent in InputMap.action_get_events("debug"):
		if event is InputEventKey:
			return OS.get_keycode_string(event.get_physical_keycode_with_modifiers() if event.physical_keycode != 0 else event.get_keycode_with_modifiers())
	return "未绑定"

func toggle_debug_panel() -> void:
	set_debug_visible(not debug_visible())

func set_debug_visible(value: bool) -> void:
	if debug_visible() == value:
		return
	%DebugPanel.visible = value
	if value:
		%DebugPanel.set_shortcut(_debug_shortcut())
		%DebugRefresh.start()
	else:
		%DebugRefresh.stop()
	debug_visibility_changed.emit(value)
	if value:
		debug_refresh_requested.emit()

func help_visible() -> bool:
	return %HelpOverlay.visible

func _select_percentage(value: int) -> void:
	if not _paused and not _finished and not _global_paused and not _local_surrendered:
		percentage_changed.emit(value)

func _skill_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _skill_buttons[index].disabled:
		_request_skill(index, false)
		_skill_buttons[index].accept_event()

func _request_skill(index: int, from_keyboard: bool) -> void:
	# Keyboard requests reach the controller even while a card is unavailable,
	# so its actual cooldown or energy shortfall produces the same clear feedback.
	if not _paused and not _finished and not _global_paused and not _local_surrendered:
		skill_requested.emit(index, from_keyboard)

func _open_help() -> void:
	_update_help_controls()
	_help_from_pause = _paused
	if not _paused:
		pause_requested.emit()
	else:
		ui_sound_requested.emit(&"war_select")
	%PauseOverlay.hide()
	%HelpOverlay.show()
	%HelpClose.grab_focus(true)
	UIMotion.reveal(%HelpCard, Vector2(0, 20))

func _update_help_controls() -> void:
	if _online_menu:
		%HelpCard.get_node("Detail4").text = "屏幕边缘或中键拖动来移动镜头；滚轮缩放。\nEsc 只打开本地菜单；%s 暂停或继续整场对局。\n参战真人均可暂停，投降后可观战；%s 开关数据面板。" % [_pause_shortcut(), _debug_shortcut()]
	else:
		%HelpCard.get_node("Detail4").text = "铁匠铺提高全军攻击力与防御力；士气提高攻击力、防御力与移速。\n炮塔防御力：1 级 +25%%、2 级 +40%%、3 级 +60%%、4 级 +70%%。\n同类常驻加成相加，攻击力除以防御力结算；技能独立结算。按 %s 开关数据面板。" % _debug_shortcut()

func _close_help() -> void:
	%HelpOverlay.hide()
	if _help_from_pause:
		ui_sound_requested.emit(&"war_cancel")
		%PauseOverlay.show()
		%PauseHelp.grab_focus(true)
		UIMotion.reveal(%PauseCard)
	else:
		resume_requested.emit()

func _open_exit() -> void:
	pause_requested.emit()
	%PauseExit.grab_focus()

func _configure_online_menu(online: Node) -> void:
	_hosting = online.is_host
	%Pause.text = "菜单"
	%Pause.tooltip_text = "打开菜单 · 对局继续进行 · Esc"
	%PauseMenuActions.add_theme_constant_override("separation", 8)
	for button: Button in %PauseMenuActions.get_children():
		button.custom_minimum_size.y = 52 if button == %Resume else 44
	%MatchPause.show()
	%Surrender.show()
	%PauseRestart.text = "全员返回房间" if online.is_host else "等待房主返回房间"
	%ResultRestart.text = "返回房间" if online.is_host else "等待房主返回房间"
	%PauseRestart.disabled = not online.is_host
	%ResultRestart.disabled = not online.is_host
	%PauseExit.text = "离开对局"
	%ResultExit.text = "离开房间"
	%Exit.tooltip_text = "联机对局菜单"
	_update_help_controls()
	_refresh_match_menu()

func _pause_shortcut() -> String:
	for event: InputEvent in InputMap.action_get_events("pause"):
		if event is InputEventKey:
			return OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	return "暂停快捷键"

func _update_match_controls(state: Dictionary) -> void:
	_global_paused = bool(state.get("global_paused", false))
	_local_surrendered = bool(state.get("local_surrendered", false))
	_can_match_pause = _online_menu and bool(state.get("can_match_pause", false)) and not _finished
	_can_surrender = _online_menu and bool(state.get("can_surrender", false)) and not _finished
	_pause_actor_name = str(state.get("pause_actor_name", ""))
	if _online_action == "surrender" and not _can_surrender:
		_cancel_online_action()
	_refresh_match_menu()
	_refresh_match_status()

func _refresh_match_menu() -> void:
	if not _online_menu:
		return
	%Resume.text = "返回观战   Esc" if _local_surrendered else "返回战场   Esc"
	%MatchPause.text = ("继续对局   " if _global_paused else "暂停对局   ") + _pause_shortcut()
	%MatchPause.disabled = not _can_match_pause
	%MatchPause.tooltip_text = "仍参战的真人可暂停或继续整场对局。" if not _local_surrendered else "你已投降，观战时不能暂停或继续对局。"
	%Surrender.text = "已投降 · 观战中" if _local_surrendered else "投降并观战"
	%Surrender.disabled = not _can_surrender
	%PauseCard.get_node("Title").text = "对局已暂停" if _global_paused else ("正在观战" if _local_surrendered else "战斗仍在继续")
	%PauseCard.get_node("Sub").text = "仍参战的真人均可恢复对局。" if _global_paused else ("你已交出军团，可继续观看战局。" if _local_surrendered else "Esc 只打开菜单，暂停请按 %s。" % _pause_shortcut())

func _refresh_match_status() -> void:
	%MatchStatus.visible = _online_menu and (_global_paused or _local_surrendered) and not _paused and not _finished and not %OnlineStatus.visible
	if not %MatchStatus.visible:
		return
	if _global_paused:
		%MatchStatusTitle.text = "对局已暂停"
		var actor := "%s 暂停了对局。" % _pause_actor_name if not _pause_actor_name.is_empty() else "所有玩家的战场均已暂停。"
		%MatchStatusDetail.text = actor + ("按 %s 继续。" % _pause_shortcut() if _can_match_pause else "等待参战指挥官继续。")
	else:
		%MatchStatusTitle.text = "已投降 · 观战中"
		%MatchStatusDetail.text = "房主仍在托管 · 留在房间即可继续观战" if _hosting else "军团已交接 · 你可以继续观看队友的战斗"

func _request_match_pause() -> void:
	if _finished:
		return
	if not _online_menu:
		if _paused: resume_requested.emit()
		else: pause_requested.emit()
	elif _can_match_pause:
		match_pause_requested.emit(not _global_paused)

func _request_surrender() -> void:
	if not _can_surrender or _finished:
		return
	var detail := "投降后，你将转为观战。建筑和行军部队随机交给尚存的真人队友，建筑驻军减少 40%。\n\n若本方所有真人均已投降，本方立即判负。"
	if _hosting:
		detail += "\n\n你仍是房主，需要留在房间继续托管对局。"
	_show_online_confirm("surrender", "确认投降？", detail, "确认投降并观战")

func _request_restart() -> void:
	if not _online_menu:
		restart_requested.emit()
	elif _finished:
		restart_requested.emit()
	else:
		_show_online_confirm("room", "全员返回房间？", "当前对局将结束，所有玩家一起返回房间。", "确认返回")

func _request_exit() -> void:
	if not _online_menu:
		exit_requested.emit()
		return
	var host: bool = get_node("/root/Session/Online").is_host
	var detail := "离开即视为投降。建筑和行军部队随机交给尚存的真人队友，建筑驻军减少 40%。\n\n本方所有真人均已投降时，本方立即判负。也可以返回菜单，选择投降并留在房间观战。"
	if host:
		detail = "你是房主，离开将关闭房间，结束所有玩家的对局。\n\n投降后留在房间观战，仍可继续托管，让其他玩家完成战斗。"
	elif _local_surrendered:
		detail = "你已投降，军团已完成交接。离开观战并返回主菜单，其他玩家继续战斗。"
	if _finished:
		detail = "你是房主，离开会关闭这个房间。" if host else "返回主菜单，离开这个房间。"
	_show_online_confirm("leave", "离开房间？", detail, "确认离开")

func _show_online_confirm(action: String, title: String, detail: String, confirm: String) -> void:
	_online_action = action
	var column: Node = %OnlineConfirm.get_node("Center/Card/Column")
	column.get_node("Title").text = title
	column.get_node("Detail").text = detail
	column.get_node("Actions/Confirm").text = confirm
	column.get_node("Actions/Cancel").text = "取消投降" if action == "surrender" else ("留下来" if _finished else "返回菜单")
	%OnlineConfirm.show()
	column.get_node("Actions/Cancel").grab_focus(true)
	UIMotion.reveal(%OnlineConfirm.get_node("Center/Card"), Vector2(0, 12))

func _cancel_online_action() -> void:
	_online_action = ""
	%OnlineConfirm.hide()
	if _finished:
		%ResultExit.grab_focus(true)
	else:
		%Resume.grab_focus(true)

func _confirm_online_action() -> void:
	var action := _online_action
	_online_action = ""
	%OnlineConfirm.hide()
	if action == "room":
		restart_requested.emit()
	elif action == "leave":
		exit_requested.emit()
	elif action == "surrender" and _can_surrender and not _finished:
		surrender_requested.emit()

func _open_settings() -> void:
	ui_sound_requested.emit(&"war_select")
	get_node("/root/Session/Settings").open_menu()

func _settings_closed() -> void:
	if %PauseOverlay.visible:
		%PauseSettings.grab_focus(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if %OnlineConfirm.visible:
		if event.is_action_pressed("ui_cancel"):
			_cancel_online_action()
			get_viewport().set_input_as_handled()
		return
	if get_node("/root/Session/Settings").is_open():
		return
	if event.is_action_pressed("debug"):
		if not %HelpOverlay.visible:
			toggle_debug_panel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		_request_match_pause()
		get_viewport().set_input_as_handled()
		return
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
	if code == KEY_ESCAPE and debug_visible() and not %HelpOverlay.visible:
		set_debug_visible(false)
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
	if _paused or _finished or _global_paused or _local_surrendered:
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
