extends PanelContainer
## Local, read-only battle diagnostics. The HUD owns visibility and refresh timing.

signal close_requested()

var _rate_at := -1
var _rate_sent := 0
var _rate_received := 0


func _ready() -> void:
	%Close.pressed.connect(func(): close_requested.emit())


func set_shortcut(shortcut_text: String) -> void:
	%Close.text = "%s  关闭" % shortcut_text
	_rate_at = -1


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
	_update_performance(data)


func _update_performance(data: Dictionary) -> void:
	var lines := PackedStringArray()
	var network: Dictionary = data.network
	if network.is_empty():
		lines.append("单人对局 · 无网络链路")
		_rate_at = -1
	else:
		var transport: Dictionary = network.transport
		var match_data: Dictionary = network.match
		var states := {"disconnected": "未连接", "connecting": "连接中", "reconnecting": "重连中", "host_lost": "等待房主", "loading": "加载中", "match": "对局中", "finished": "已结束", "connected": "已连接", "room": "房间中"}
		lines.append("网络：%s" % states.get(network.connection_state, network.connection_state))
		lines.append("中继 RTT %s · 波动 %s" % [_milliseconds(transport.relay_rtt_ms), _milliseconds(transport.relay_jitter_ms)])
		lines.append("本机为房主" if match_data.is_host else "经中继到房主 RTT：%s" % _milliseconds(match_data.host_rtt_ms))
		var loss := "待采样" if float(transport.loss_percent) < 0.0 else "%.2f%%" % float(transport.loss_percent)
		lines.append("ENet 估计丢包 %s · 收包距今 %s" % [loss, _milliseconds(transport.last_received_age_ms)])
		lines.append(_traffic(transport))
		var sync_state := "载入基线" if match_data.snapshot_loading else ("等待恢复确认" if match_data.recovery_waiting else "已同步")
		if not transport.connected:
			sync_state = "连接中断"
		elif network.connection_state == "host_lost":
			sync_state = "等待房主恢复"
		elif not match_data.ready:
			sync_state = "同步未就绪"
		elif not match_data.is_host and int(match_data.authority_age_ms) > 2000:
			sync_state = "等待房主数据"
		lines.append("%s · 待处理事件 %d · 重同步 %d" % [sync_state, int(match_data.pending_events), int(match_data.resync_count)])
		lines.append("发送队列 %.1f KiB · 同步队列 %.1f KiB" % [float(transport.bulk_queue_bytes) / 1024.0, float(match_data.outbox_bytes) / 1024.0])
	lines.append("%.0f FPS · 平均帧间隔 %.2f ms" % [float(data.fps), float(data.frame_ms)])
	var timings: Dictionary = data.timings
	if not timings.ready:
		lines.append("本地计算：正在采样…")
	else:
		lines.append("本地耗时：近 %.1f 秒均值 / 开窗峰值" % float(timings.window_seconds))
		for row: Array in [["frame", "战场帧脚本"], ["simulation", "模拟（含 AI）"], ["ai", "AI 决策"], ["replication", "同步处理"], ["presentation", "客机呈现"]]:
			var stage: Dictionary = timings.stages[row[0]]
			var mean := "—" if int(stage.count) == 0 else "%.2f" % float(stage.mean_ms)
			var peak := "—" if int(stage.count) == 0 and float(stage.peak_since_open_ms) <= 0.0 else "%.2f" % float(stage.peak_since_open_ms)
			lines.append("%s：%s / %s ms" % [row[1], mean, peak])
	lines.append("对局时间 %02d:%02d" % [int(data.sim_time) / 60, int(data.sim_time) % 60])
	%PerformanceValue.text = "\n".join(lines)


func _traffic(transport: Dictionary) -> String:
	if not transport.connected:
		_rate_at = -1
		return "应用流量：—"
	var now := Time.get_ticks_msec()
	var text := "应用流量：待采样"
	var sent := int(transport.sent_bytes)
	var received := int(transport.received_bytes)
	if _rate_at >= 0 and now > _rate_at and sent >= _rate_sent and received >= _rate_received:
		var seconds := float(now - _rate_at) / 1000.0
		text = "应用流量 ↓ %.1f / ↑ %.1f KiB/s" % [float(received - _rate_received) / seconds / 1024.0, float(sent - _rate_sent) / seconds / 1024.0]
	_rate_at = now
	_rate_sent = sent
	_rate_received = received
	return text


func _milliseconds(value: float) -> String:
	return "待采样" if value < 0.0 else "%.0f ms" % value


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
