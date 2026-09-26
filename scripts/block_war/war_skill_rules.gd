extends RefCounted
## Commander skill profiles shared by simulation, AI and feedback.

const COMMANDER_ID := &"squirrel"
const COMMANDER_NAME := "榛果"
const NAMES: Array[String] = ["征召军令", "疾行战鼓", "防护罩", "天降冲击"]
const COSTS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 70.0]
const DURATIONS: Array[float] = [6.0, 8.0, 8.0, 0.0]
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 2.0
const RECRUIT_RATE := 4.0
const HASTE_MULTIPLIER := 1.6
const HASTE_RADIUS := 4.5
const SHIELD_DEFENSE := 0.25
const FIRE_RADIUS := 4.5
const FIRE_DAMAGE := 25.0

const RABBIT := &"rabbit"
const RABBIT_NAMES: Array[String] = ["蹦蹦小径", "封条急件", "归巢口哨", "兔洞快递"]
const RABBIT_COSTS: Array[float] = [25.0, 25.0, 20.0, 65.0]
const RABBIT_COOLDOWNS: Array[float] = [24.0, 30.0, 26.0, 70.0]
const RABBIT_DURATIONS: Array[float] = [6.0, 6.0, 0.0, 0.0]
const RABBIT_HASTE_RADIUS := 3.5
const RABBIT_HASTE_MULTIPLIER := 1.7
const DISABLE_DURATION := 6.0
const RECALL_RADIUS := 6.0
const RECALL_LIMIT := 24
const BURROW_LIMIT := 30
const BURROW_RESERVE := 10
const BURROW_MINIMUM := 12
const BURROW_RANGE := 18.0
const BURROW_BATCH_INTERVAL := 0.16
const BURROW_EXIT_DISTANCE := 3.0
const SQUIRREL_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_muster.svg"), preload("res://assets/ui/block_war/skill_haste.svg"), preload("res://assets/ui/block_war/skill_bulwark.svg"), preload("res://assets/ui/block_war/skill_impact.svg")]
const RABBIT_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_rabbit_dash.svg"), preload("res://assets/ui/block_war/skill_rabbit_seal.svg"), preload("res://assets/ui/block_war/skill_rabbit_recall.svg"), preload("res://assets/ui/block_war/skill_rabbit_burrow.svg")]
const PORTRAITS := {&"squirrel": preload("res://assets/ui/block_war/commanders/squirrel.png"), RABBIT: preload("res://assets/ui/block_war/commanders/rabbit.png")}

static func names_for(commander: StringName) -> Array[String]:
	return RABBIT_NAMES if commander == RABBIT else NAMES

static func costs_for(commander: StringName) -> Array[float]:
	return RABBIT_COSTS if commander == RABBIT else COSTS

static func cooldowns_for(commander: StringName) -> Array[float]:
	return RABBIT_COOLDOWNS if commander == RABBIT else COOLDOWNS

static func durations_for(commander: StringName) -> Array[float]:
	return RABBIT_DURATIONS if commander == RABBIT else DURATIONS

static func is_ground(index: int, commander: StringName) -> bool:
	return index == 0 if commander == RABBIT else index in [1, 3]

static func name_for(commander: StringName) -> String:
	return "跳豆 · 兔子" if commander == RABBIT else "榛果 · 松鼠"

static func icons_for(commander: StringName) -> Array[Texture2D]:
	return RABBIT_ICONS if commander == RABBIT else SQUIRREL_ICONS

static func effect_text(index: int) -> String:
	match index:
		0: return "每秒征召 %d 人，持续 %d 秒，不叠加。" % [RECRUIT_RATE, DURATIONS[0]]
		1: return "半径 %.1f 米的疾行区域，持续 %d 秒。\n圈内自己的部队提速 %d%%，离开恢复原速。" % [HASTE_RADIUS, DURATIONS[1], roundi((HASTE_MULTIPLIER - 1.0) * 100.0)]
		2: return "守备 +%d%%，持续 %d 秒，不叠加。" % [SHIELD_DEFENSE * 100.0, DURATIONS[2]]
		3: return "松手立即点燃，火焰从圆心迅速扩散至 %.1f 米。\n接触的双方士兵均死亡，敌方驻军基础伤害 %d。" % [FIRE_RADIUS, FIRE_DAMAGE]
	return ""

static func description(index: int, commander: StringName = COMMANDER_ID) -> String:
	if commander == RABBIT:
		return [
			"拖至地面，松手施放。\n半径 3.5 米，持续 6 秒。\n圈内自己的部队提速 70%，离开恢复。",
			"拖至敌方建筑，令其停工 6 秒。\n住宅停止产兵，炮塔停止射击，\n铁匠铺暂停提供攻击增益。不叠加。",
			"拖至自己的建筑，松手集合。\n附近 6 米内最多 24 名自己的行军折返，\n按原速返回，途中仍会受到攻击。",
			"拖至建筑，松手立即出兵。\n从附近自己的建筑转运最多 30 人，保留 10 人。\n每 0.16 秒出洞一排，途中仍会受到攻击。"
		][index]
	var targets: Array[String] = ["自己或盟友住宅", "地面", "自己或盟友建筑", "地面"]
	return "拖至%s，松手施放。\n%s" % [targets[index], effect_text(index)]
