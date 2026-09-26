extends RefCounted
## The default squirrel's four skills. Simulation, AI and feedback share these values.

const COMMANDER_ID := &"squirrel"
const COMMANDER_NAME := "榛果"
const NAMES: Array[String] = ["征召军令", "疾行战鼓", "磐石壁垒", "天降冲击"]
const COSTS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 70.0]
const DURATIONS: Array[float] = [6.0, 8.0, 8.0, 0.0]
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 2.0
const RECRUIT_RATE := 4.0
const HASTE_MULTIPLIER := 1.6
const HASTE_RADIUS := 4.5
const SHIELD_DEFENSE := 0.5
const FIRE_RADIUS := 4.5
const FIRE_DAMAGE := 25.0
const FIRE_WINDUP := 0.8

static func effect_text(index: int) -> String:
	match index:
		0: return "每秒征召 %d 人，持续 %d 秒，不叠加。" % [RECRUIT_RATE, DURATIONS[0]]
		1: return "半径 %.1f 米的疾行区域，持续 %d 秒。\n圈内自己的部队提速 %d%%，离开恢复原速。" % [HASTE_RADIUS, DURATIONS[1], roundi((HASTE_MULTIPLIER - 1.0) * 100.0)]
		2: return "守备 +%d%%，持续 %d 秒，不叠加。" % [SHIELD_DEFENSE * 100.0, DURATIONS[2]]
		3: return "蓄热 %.1f 秒后，火焰从圆心扩散至 %.1f 米。\n接触的双方士兵均死亡，敌方驻军基础伤害 %d。" % [FIRE_WINDUP, FIRE_RADIUS, FIRE_DAMAGE]
	return ""

static func description(index: int) -> String:
	var targets: Array[String] = ["自己或盟友住宅", "地面", "自己或盟友建筑", "地面"]
	return "拖至%s，松手施放。\n%s" % [targets[index], effect_text(index)]
