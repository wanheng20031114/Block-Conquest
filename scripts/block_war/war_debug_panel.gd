extends PanelContainer
## Local, read-only battle diagnostics. The HUD owns visibility and refresh timing.

signal close_requested()


func _ready() -> void:
	%Close.pressed.connect(func(): close_requested.emit())


func set_shortcut(shortcut_text: String) -> void:
	%Close.text = "%s  关闭" % shortcut_text


func update_data(data: Dictionary) -> void:
	%AttackValue.text = _percent(float(data.attack_multiplier))
	%DefenseValue.text = _percent(float(data.defense_multiplier))
	%SpeedValue.text = _percent(float(data.speed_multiplier))
	%ActualSpeed.text = "%.2f m/s" % float(data.move_speed)
	%Context.text = "%s · %s\n%s · %s" % [data.commander_name, data.faction_name, data.mode, data.match_state]
	var morale_level: int = int(data.morale_level)
	%MoraleValue.text = "%d 星 · %d 士气" % [morale_level, floori(float(data.morale_points))]
	var next_points: float = float(data.morale_next)
	%MoraleProgress.text = "已达最高等级" if next_points < 0.0 else "下一级：%d / %.0f" % [floori(float(data.morale_points)), next_points]
	%BonusSources.text = "士气：攻击力 +%s · 防御力 +%s · 移速 +%s\n铁匠铺：攻击力 +%s · 防御力 +%s" % [
		_percent(float(data.morale_attack)), _percent(float(data.morale_defense)),
		_percent(float(data.morale_speed)), _percent(float(data.forge_attack)),
		_percent(float(data.forge_defense))]
	var buildings: Array = data.buildings
	%BuildingsValue.text = "住宅 %d    炮塔 %d\n铁匠铺 %d（有效 %d）\n能量塔 %d（有效 %d）" % [
		int(buildings[0]), int(buildings[1]), int(buildings[2]), int(data.forges_active),
		int(buildings[3]), int(data.energy_towers_active)]
	%ArmyValue.text = "总兵力 %.1f\n建筑驻军 %.1f    行军 %d\n空降 %d · 门内待出 %d（含在驻军内）" % [
		float(data.army_total), float(data.garrison), int(data.marching), int(data.airlifting), int(data.queued)]
	%EnergyValue.text = "%.1f / %.0f  ·  +%.2f / 秒" % [float(data.energy), float(data.energy_max), float(data.energy_regen)]
	_update_selection(data.selected)
	%PerformanceValue.text = "%.0f FPS  ·  %.2f ms / 帧\n对局时间 %02d:%02d" % [
		float(data.fps), float(data.frame_ms), int(data.sim_time) / 60, int(data.sim_time) % 60]


func _update_selection(selected: Dictionary) -> void:
	if selected.is_empty():
		%SelectionValue.text = "未选中建筑"
		return
	var lines: PackedStringArray = ["%s · %d 级 · #%d" % [selected.kind_name, int(selected.level), int(selected.id)], str(selected.owner)]
	if float(selected.population) >= 0.0:
		lines.append("驻军 %.1f · 可派 %d · 待出 %d" % [float(selected.population), floori(float(selected.available)), int(selected.queued)])
	else:
		lines.append("驻军情报不可见")
	lines.append("常驻防御力 %s · 临时防御力 +%s" % [_percent(float(selected.defense_multiplier)), _percent(float(selected.skill_defense))])
	if float(selected.construction_remaining) > 0.0:
		lines.append("施工剩余 %.1f 秒" % float(selected.construction_remaining))
	if float(selected.disruption_remaining) > 0.0:
		lines.append("停工剩余 %.1f 秒" % float(selected.disruption_remaining))
	%SelectionValue.text = "\n".join(lines)


func _percent(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)
