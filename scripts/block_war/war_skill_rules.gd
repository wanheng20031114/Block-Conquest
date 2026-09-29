extends RefCounted
## Commander skill profiles shared by simulation, AI and feedback.

const COMMANDER_ID := &"squirrel"
const COMMANDER_NAME := "松鼠"
const NAMES: Array[String] = ["征召军令", "疾行战鼓", "防护罩", "天降冲击"]
const COSTS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const COOLDOWNS: Array[float] = [35.0, 28.0, 45.0, 70.0]
const DURATIONS: Array[float] = [6.0, 8.0, 8.0, 0.0]
const ENERGY_MAX := 100.0
const ENERGY_INITIAL := 20.0
const ENERGY_REGEN := 1.0
const ENERGY_LATE_REGEN := 2.0
const ENERGY_ACCELERATION_TIME := 100.0
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
const BEAR_NAMES: Array[String] = ["工具箱", "重重跺脚", "链式防守", "震庭威慑"]
const BEAR_COSTS: Array[float] = [25.0, 25.0, 30.0, 70.0]
const BEAR_COOLDOWNS: Array[float] = [30.0, 30.0, 35.0, 70.0]
const BEAR_DURATIONS: Array[float] = [0.0, 4.0, 8.0, 5.0]
const BEAR_SLOW_RADIUS := 4.5
const BEAR_SLOW_MULTIPLIER := 0.4
const BEAR_LINK_RADIUS := 18.0
const BEAR_WARD_DEFENSE := 1.0
const BEAR_ORB_RANGE := 18.0
const BEAR_ORB_INTERVAL := 0.5
const BEAR_ORB_TARGETS := 3
const FROG := &"frog"
const FROG_NAMES: Array[String] = ["弱化雾气", "浮力薄隔", "隐身", "致命打击"]
const FROG_COSTS: Array[float] = [20.0, 30.0, 20.0, 90.0]
const FROG_COOLDOWNS: Array[float] = [20.0, 32.0, 26.0, 100.0]
const FROG_DURATIONS: Array[float] = [3.0, 3.0, 0.0, 0.0]
const FROG_RADII: Array[float] = [3.5, 3.5, 4.5, 0.0]
const FROG_WEAKNESS := 0.20
const FROG_STRIKE_FRACTION := 0.80
const FOX := &"fox"
const FOX_NAMES: Array[String] = ["从天而降", "顺手牵星", "临阵招降", "惊慌失措"]
const FOX_COSTS: Array[float] = [25.0, 40.0, 60.0, 80.0]
const FOX_COOLDOWNS: Array[float] = [35.0, 50.0, 65.0, 85.0]
const FOX_DURATIONS: Array[float] = [0.0, 0.0, 0.0, 0.0]
const FOX_BOMB_FRACTION := 0.5
const FOX_BOMB_CAP := 30
const FOX_STEAL_STARS := 1.0
const FOX_CONVERT_RADIUS := 3.0
const FOX_PANIC_FRACTION := 0.8
const FOX_PANIC_DESTINATIONS := 3
const PIG := &"pig"
const PIG_NAMES: Array[String] = ["猪冲锋", "猪会飞", "猪整队", "特大猪"]
const PIG_COSTS: Array[float] = [15.0, 25.0, 25.0, 80.0]
const PIG_COOLDOWNS: Array[float] = [18.0, 30.0, 35.0, 85.0]
const PIG_DURATIONS: Array[float] = [15.0, 15.0, 15.0, 0.0]
const PIG_READY_DURATION := 15.0
const PIG_CHARGE_SPEED_BONUS := 0.20
const PIG_CHARGE_ATTACK_BONUS := 0.10
const PIG_FLIGHT_LIMIT := 30
const PIG_FORMATION_LIMIT := 60
const PIG_DROP_RADIUS := 3.0
const PIG_DROP_FALL_TIME := 0.65
const PIG_DROP_LIFETIME := 1.4
const PIG_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_pig_charge.svg"), preload("res://assets/ui/block_war/skill_pig_fly.svg"), preload("res://assets/ui/block_war/skill_pig_formation.svg"), preload("res://assets/ui/block_war/skill_pig_drop.svg")]
const SQUIRREL_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_muster.svg"), preload("res://assets/ui/block_war/skill_haste.svg"), preload("res://assets/ui/block_war/skill_bulwark.svg"), preload("res://assets/ui/block_war/skill_impact.svg")]
const RABBIT_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_rabbit_dash.svg"), preload("res://assets/ui/block_war/skill_rabbit_seal.svg"), preload("res://assets/ui/block_war/skill_rabbit_recall.svg"), preload("res://assets/ui/block_war/skill_rabbit_burrow.svg")]
const BEAR_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_bear_toolbox.svg"), preload("res://assets/ui/block_war/skill_bear_stomp.svg"), preload("res://assets/ui/block_war/skill_bear_link.svg"), preload("res://assets/ui/block_war/skill_bear_fortress.svg")]
const FROG_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_frog_mist.svg"), preload("res://assets/ui/block_war/skill_frog_float.svg"), preload("res://assets/ui/block_war/skill_frog_cloak.svg"), preload("res://assets/ui/block_war/skill_frog_strike.svg")]
const FOX_ICONS: Array[Texture2D] = [preload("res://assets/ui/block_war/skill_fox_bomb.svg"), preload("res://assets/ui/block_war/skill_fox_steal.svg"), preload("res://assets/ui/block_war/skill_fox_convert.svg"), preload("res://assets/ui/block_war/skill_fox_panic.svg")]
const PORTRAITS := {&"squirrel": preload("res://assets/ui/block_war/commanders/squirrel.png"), RABBIT: preload("res://assets/ui/block_war/commanders/rabbit.png"), BEAR: preload("res://assets/ui/block_war/commanders/bear.png"), FROG: preload("res://assets/ui/block_war/commanders/frog.png"), FOX: preload("res://assets/ui/block_war/commanders/fox.png"), PIG: preload("res://assets/ui/block_war/commanders/pig.png")}

static func natural_energy_regen(elapsed: float) -> float:
	return ENERGY_REGEN if elapsed < ENERGY_ACCELERATION_TIME else ENERGY_LATE_REGEN

static func natural_energy_between(start_time: float, duration: float) -> float:
	var early_seconds := clampf(ENERGY_ACCELERATION_TIME - start_time, 0.0, duration)
	return early_seconds * ENERGY_REGEN + (duration - early_seconds) * ENERGY_LATE_REGEN

static func combat_energy_per_loss(morale_stars: float) -> float:
	if morale_stars >= 5.0:
		return 0.1
	return 0.15 if morale_stars >= 3.0 else 0.2

static func energy_tower_bonus(count: int) -> float:
	var bonus := 0.0
	for index: int in mini(count, ENERGY_TOWER_BONUSES.size()):
		bonus += ENERGY_TOWER_BONUSES[index]
	return bonus + maxf(0, count - ENERGY_TOWER_BONUSES.size()) * ENERGY_TOWER_LATER_BONUS

static func names_for(commander: StringName) -> Array[String]:
	if commander == PIG: return PIG_NAMES
	if commander == FOX: return FOX_NAMES
	if commander == FROG: return FROG_NAMES
	if commander == BEAR: return BEAR_NAMES
	return RABBIT_NAMES if commander == RABBIT else NAMES

static func costs_for(commander: StringName) -> Array[float]:
	if commander == PIG: return PIG_COSTS
	if commander == FOX: return FOX_COSTS
	if commander == FROG: return FROG_COSTS
	if commander == BEAR: return BEAR_COSTS
	return RABBIT_COSTS if commander == RABBIT else COSTS

static func cooldowns_for(commander: StringName) -> Array[float]:
	if commander == PIG: return PIG_COOLDOWNS
	if commander == FOX: return FOX_COOLDOWNS
	if commander == FROG: return FROG_COOLDOWNS
	if commander == BEAR: return BEAR_COOLDOWNS
	return RABBIT_COOLDOWNS if commander == RABBIT else COOLDOWNS

static func durations_for(commander: StringName) -> Array[float]:
	if commander == PIG: return PIG_DURATIONS
	if commander == FOX: return FOX_DURATIONS
	if commander == FROG: return FROG_DURATIONS
	if commander == BEAR: return BEAR_DURATIONS
	return RABBIT_DURATIONS if commander == RABBIT else DURATIONS

static func is_ground(index: int, commander: StringName) -> bool:
	if commander == PIG: return index == 3
	if commander == FOX: return index == 2
	if commander == FROG: return index in [0, 1, 2]
	if commander == BEAR: return index == 1
	return index in [0, 2] if commander == RABBIT else index in [1, 3]

static func name_for(commander: StringName) -> String:
	if commander == PIG: return "猪猪"
	if commander == FOX: return "狐狸"
	if commander == FROG: return "青蛙"
	if commander == BEAR: return "熊"
	return "兔子" if commander == RABBIT else "松鼠"

static func icons_for(commander: StringName) -> Array[Texture2D]:
	if commander == PIG: return PIG_ICONS
	if commander == FOX: return FOX_ICONS
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
	if commander == PIG:
		return [
			"选择自己的建筑，获得 15 秒冲锋待命。\n下一次派出的部队移速 +20%、攻击 +10%，持续至入城。\n可与飞行、整队叠加；过期未出兵则失效。",
			"选择自己的建筑，获得 15 秒飞行待命。\n下一次派兵飞越地形，沿直线前往目的地。\n最多派出 30 人后停止；余兵留守，可叠加。",
			"选择自己的建筑，获得 15 秒整队待命。\n下一次派兵缩短排距和列距，集中抵达。\n最多派出 60 人后停止；叠加飞行时上限 30 人。",
			"选择战场落点，0.65 秒后特大猪砸下。\n半径 3 米内敌我所有行军部队死亡，建筑驻军减半。\n无视防护与分伤，不直接占领；空地也可施放。"
		][index]
	if commander == FOX:
		return [
			"向敌方或中立建筑投下炸弹。\n损失当前驻军的 50%，最多 30 人，向下取整。\n无视防御，不直接占领；链式防守可分担。",
			"拖至敌方建筑，偷取其所属英雄最多 1 星士气。\n不足 1 星时按实际数量转移，自己最多 5 星。\n对方无士气或自己已满时不消耗技力。",
			"招降半径 3 米内当前的敌方行军部队。\n永久归自己指挥，保留位置、阵型及行军路线。\n进入己方建筑增援，进入敌方建筑则进攻。",
			"使敌方建筑内 80% 的驻军逃走，向下取整。\n逃兵保持原阵营，分赴较近的最多 3 座同阵营建筑。\n距离不限；无去处时无法施放。"
		][index]
	if commander == FROG:
		return [
			"展开半径 3.5 米的薄雾，持续 3 秒。\n接触的敌军攻击 -20%，持续至入城。\n炮塔无法攻击雾内士兵；增援人数不变。",
			"使半径 3.5 米内当前的双方士兵滞空 3 秒。\n无法移动，也不会被炮塔命中。\n落地后继续原路线，其他技能仍可影响。",
			"半径 4.5 米内当前的己方士兵隐身。\n仅留下极淡轮廓，持续至进入建筑。\n炮塔无法攻击；仍会被火攻和法术击中。",
			"敌方或中立建筑损失当前驻军的 80%，降至 1 级。\n损失按整个人口计算，打断施工，不直接占领。\n无视防御，链式防守不分担。"
		][index]
	if commander == BEAR:
		return [
			"拖至正在升级或转换的己方建筑。\n立即完工，返还本次消耗人口的 50%。",
			"拖至地面，展开半径 4.5 米的震地区域。\n圈内敌军减速 60%，持续 4 秒。\n友军不受影响，离开后恢复速度。",
			"连接 18 米内最近的另一座己方建筑，持续 8 秒。\n支援方分担一半驻军伤害，奇数多承担 1 人。\n支援兵力不足或一端失守时断开。",
			"己方建筑防御 +%d%%，持续 %d 秒。\n头顶法球立即开火，优先攻击范围内最远的敌兵。\n射程 %d 米，每 %.1f 秒攻击最多 %d 人。" % [roundi(BEAR_WARD_DEFENSE * 100.0), BEAR_DURATIONS[3], BEAR_ORB_RANGE, BEAR_ORB_INTERVAL, BEAR_ORB_TARGETS]
		][index]
	if commander == RABBIT:
		return [
			"选中半径 %.1f 米内自己的行军，持续 %d 秒。\n移速 +%d%%，攻击 +%d%%，离开落点仍生效。\n仅强化施放瞬间选中的部队，不叠加。" % [RABBIT_RUSH_RADIUS, RABBIT_DURATIONS[0], roundi((RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), roundi(RABBIT_RUSH_ATTACK_BONUS * 100.0)],
			"拖至敌方建筑，令其停工 6 秒。\n暂停产兵、射击、铁匠铺攻防、\n能量塔恢复加成。不叠加。",
			"拖至地面，松手吹响口哨。\n半径 6 米内所有阵营的行军部队，\n各自返回出发建筑，途中仍会受到攻击。",
			"拖至自己的建筑，获得 15 秒兔洞待命。\n下一次派兵开始快速掘地，无距离限制。\n按所选比例最多派出 50 人，每 0.16 秒出洞一排。"
		][index]
	var targets: Array[String] = ["自己或盟友住宅", "地面", "自己或盟友建筑", "地面"]
	return "拖至%s，松手施放。\n%s" % [targets[index], effect_text(index)]
