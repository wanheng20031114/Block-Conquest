extends RefCounted
## Commander skill profiles shared by simulation, AI and feedback.

const COMMANDER_ID := &"squirrel"
const COMMANDER_NAME := "松鼠"
const NAMES: Array[String] = ["征召军令", "疾行战鼓", "防护罩", "天降冲击"]
const COSTS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 70.0]
const DURATIONS: Array[float] = [6.0, 8.0, 8.0, 0.0]
const ENERGY_MAX := 100.0
const ENERGY_REGEN := 2.0
const ENERGY_TOWER_BONUSES: Array[float] = [0.5, 0.25, 0.15]
const ENERGY_TOWER_LATER_BONUS := 0.1
const ENERGY_CAPTURE_REWARD := 10.0
const RECRUIT_RATE := 4.0
const HASTE_MULTIPLIER := 1.6
const HASTE_RADIUS := 4.5
const SHIELD_DEFENSE := 0.25
const FIRE_RADIUS := 4.5
const FIRE_DAMAGE := 25.0

const RABBIT := &"rabbit"
const RABBIT_NAMES: Array[String] = ["迅猛冲刺", "封条急件", "归巢口哨", "兔洞快递"]
const RABBIT_COSTS: Array[float] = [20.0, 25.0, 20.0, 65.0]
const RABBIT_COOLDOWNS: Array[float] = [20.0, 30.0, 26.0, 70.0]
const RABBIT_DURATIONS: Array[float] = [8.0, 6.0, 0.0, 15.0]
const RABBIT_RUSH_RADIUS := 3.6
const RABBIT_RUSH_MULTIPLIER := 2.0
const RABBIT_RUSH_ATTACK_BONUS := 1.0
const DISABLE_DURATION := 6.0
const RECALL_RADIUS := 6.0
const BURROW_LIMIT := 50
const BURROW_READY_DURATION := 15.0
const BURROW_DIG_SPEED := 45.0
const BURROW_BATCH_INTERVAL := 0.16
const BURROW_EXIT_DISTANCE := 3.0
const BEAR := &"bear"
const BEAR_NAMES: Array[String] = ["工具箱", "重重跺脚", "链式防守", "不落堡垒"]
const BEAR_COSTS: Array[float] = [25.0, 25.0, 30.0, 70.0]
const BEAR_COOLDOWNS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const BEAR_DURATIONS: Array[float] = [0.0, 4.0, 8.0, 5.0]
const BEAR_SLOW_RADIUS := 4.5
const BEAR_SLOW_MULTIPLIER := 0.4
const BEAR_LINK_RADIUS := 18.0
const BEAR_ORB_RANGE := 12.0
const BEAR_ORB_INTERVAL := 0.5
const FROG := &"frog"
const FROG_NAMES: Array[String] = ["弱化雾气", "浮力薄隔", "隐身", "致命打击"]
const FROG_COSTS: Array[float] = [20.0, 30.0, 20.0, 90.0]
const FROG_COOLDOWNS: Array[float] = [20.0, 32.0, 26.0, 100.0]
const FROG_DURATIONS: Array[float] = [3.0, 3.0, 0.0, 0.0]
const FROG_RADII: Array[float] = [3.5, 3.5, 4.5, 0.0]
const FROG_WEAKNESS := 0.20
const FROG_STRIKE_FRACTION := 0.80
const SQUIRREL_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_muster.svg"), preload("res://assets/ui/block_war/skill_haste.svg"), preload("res://assets/ui/block_war/skill_bulwark.svg"), preload("res://assets/ui/block_war/skill_impact.svg")]
const RABBIT_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_rabbit_dash.svg"), preload("res://assets/ui/block_war/skill_rabbit_seal.svg"), preload("res://assets/ui/block_war/skill_rabbit_recall.svg"), preload("res://assets/ui/block_war/skill_rabbit_burrow.svg")]
const BEAR_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_bear_toolbox.svg"), preload("res://assets/ui/block_war/skill_bear_stomp.svg"), preload("res://assets/ui/block_war/skill_bear_link.svg"), preload("res://assets/ui/block_war/skill_bear_fortress.svg")]
const FROG_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_frog_mist.svg"), preload("res://assets/ui/block_war/skill_frog_float.svg"), preload("res://assets/ui/block_war/skill_frog_cloak.svg"), preload("res://assets/ui/block_war/skill_frog_strike.svg")]
const PORTRAITS := {&"squirrel": preload("res://assets/ui/block_war/commanders/squirrel.png"), RABBIT: preload("res://assets/ui/block_war/commanders/rabbit.png"), BEAR: preload("res://assets/ui/block_war/commanders/bear.png"), FROG: preload("res://assets/ui/block_war/commanders/frog.png")}

static func energy_tower_bonus(count: int) -> float:
	var bonus := 0.0
	for index: int in mini(count, ENERGY_TOWER_BONUSES.size()):
		bonus += ENERGY_TOWER_BONUSES[index]
	return bonus + maxf(0, count - ENERGY_TOWER_BONUSES.size()) * ENERGY_TOWER_LATER_BONUS

static func names_for(commander: StringName) -> Array[String]:
	if commander == FROG: return FROG_NAMES
	if commander == BEAR: return BEAR_NAMES
	return RABBIT_NAMES if commander == RABBIT else NAMES

static func costs_for(commander: StringName) -> Array[float]:
	if commander == FROG: return FROG_COSTS
	if commander == BEAR: return BEAR_COSTS
	return RABBIT_COSTS if commander == RABBIT else COSTS

static func cooldowns_for(commander: StringName) -> Array[float]:
	if commander == FROG: return FROG_COOLDOWNS
	if commander == BEAR: return BEAR_COOLDOWNS
	return RABBIT_COOLDOWNS if commander == RABBIT else COOLDOWNS

static func durations_for(commander: StringName) -> Array[float]:
	if commander == FROG: return FROG_DURATIONS
	if commander == BEAR: return BEAR_DURATIONS
	return RABBIT_DURATIONS if commander == RABBIT else DURATIONS

static func is_ground(index: int, commander: StringName) -> bool:
	if commander == FROG: return index in [0, 1, 2]
	if commander == BEAR: return index == 1
	return index in [0, 2] if commander == RABBIT else index in [1, 3]

static func name_for(commander: StringName) -> String:
	if commander == FROG: return "青蛙"
	if commander == BEAR: return "熊"
	return "兔子" if commander == RABBIT else "松鼠"

static func icons_for(commander: StringName) -> Array[Texture2D]:
	if commander == FROG: return FROG_ICONS
	if commander == BEAR: return BEAR_ICONS
	return RABBIT_ICONS if commander == RABBIT else SQUIRREL_ICONS

static func effect_text(index: int) -> String:
	match index:
		0: return "每秒征召 %d 人，持续 %d 秒，不叠加。" % [RECRUIT_RATE, DURATIONS[0]]
		1: return "半径 %.1f 米的疾行区域，持续 %d 秒。\n圈内自己的部队提速 %d%%，离开恢复原速。" % [HASTE_RADIUS, DURATIONS[1], roundi((HASTE_MULTIPLIER - 1.0) * 100.0)]
		2: return "守备 +%d%%，持续 %d 秒，不叠加。" % [SHIELD_DEFENSE * 100.0, DURATIONS[2]]
		3: return "松手立即点燃，火焰从圆心迅速扩散至 %.1f 米。\n接触的双方士兵均死亡，敌方驻军基础伤害 %d。" % [FIRE_RADIUS, FIRE_DAMAGE]
	return ""

static func description(index: int, commander: StringName = COMMANDER_ID) -> String:
	if commander == FROG:
		return [
			"展开半径 3.5 米的薄雾，持续 3 秒。\n接触的敌军攻击 -20%，持续至入城。\n炮塔无法攻击雾内士兵；增援人数不变。",
			"使半径 3.5 米内当前的双方士兵滞空 3 秒。\n无法移动，也不会被炮塔命中。\n落地后继续原路线，其他技能仍可影响。",
			"半径 4.5 米内当前的己方士兵隐身。\n仅留下极淡轮廓，持续至进入建筑。\n炮塔无法攻击；仍会被火攻和法术击中。",
			"敌方或中立建筑损失当前驻军的 80%，降至 1 级。\n损失按整个人口计算，打断施工，不直接占领。\n无敌可阻挡，链式防守不分担。"
		][index]
	if commander == BEAR:
		return [
			"拖至正在升级或转换的己方建筑。\n立即完工，返还本次消耗人口的 50%。",
			"拖至地面，展开半径 4.5 米的震地区域。\n圈内敌军减速 60%，持续 4 秒。\n友军不受影响，离开后恢复速度。",
			"连接 18 米内最近的另一座己方建筑，持续 8 秒。\n支援方分担一半驻军伤害，奇数多承担 1 人。\n支援兵力不足或一端失守时断开。",
			"己方建筑无敌 5 秒，敌军在外围等待交战。\n上方法术球立即开火，优先打击远处敌兵。\n射程 12 米，每 0.5 秒击杀 1 人。"
		][index]
	if commander == RABBIT:
		return [
			"选中半径 %.1f 米内自己的行军，持续 %d 秒。\n移速 +%d%%，攻击 +%d%%，离开落点仍生效。\n仅强化施放瞬间选中的部队，不叠加。" % [RABBIT_RUSH_RADIUS, RABBIT_DURATIONS[0], roundi((RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), roundi(RABBIT_RUSH_ATTACK_BONUS * 100.0)],
			"拖至敌方建筑，令其停工 6 秒。\n暂停产兵、射击、攻击增益或\n能量塔的恢复加成。不叠加。",
			"拖至地面，松手吹响口哨。\n半径 6 米内所有阵营的行军部队，\n各自返回出发建筑，途中仍会受到攻击。",
			"拖至自己的建筑，获得 15 秒兔洞待命。\n下一次派兵开始快速掘地，无距离限制。\n按所选比例最多派出 50 人，每 0.16 秒出洞一排。"
		][index]
	var targets: Array[String] = ["自己或盟友住宅", "地面", "自己或盟友建筑", "地面"]
	return "拖至%s，松手施放。\n%s" % [targets[index], effect_text(index)]
