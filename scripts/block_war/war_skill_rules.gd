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
const RABBIT_COSTS: Array[float] = [25.0, 25.0, 20.0, 65.0]
const RABBIT_COOLDOWNS: Array[float] = [25.0, 30.0, 26.0, 70.0]
const RABBIT_DURATIONS: Array[float] = [8.0, 6.0, 0.0, 15.0]
const RABBIT_RUSH_RADIUS := 3.0
const RABBIT_RUSH_MULTIPLIER := 2.0
const RABBIT_RUSH_ATTACK_BONUS := 0.5
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
const BEAR_COOLDOWNS: Array[float] = [30.0, 25.0, 35.0, 70.0]
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
const FROG_COSTS: Array[float] = [20.0, 30.0, 20.0, 85.0]
const FROG_COOLDOWNS: Array[float] = [20.0, 32.0, 26.0, 95.0]
const FROG_DURATIONS: Array[float] = [3.0, 3.0, 0.0, 0.0]
const FROG_RADII: Array[float] = [3.5, 3.5, 4.5, 0.0]
const FROG_WEAKNESS := 0.20
const FROG_STRIKE_FRACTION := 0.80
const FOX := &"fox"
const FOX_NAMES: Array[String] = ["从天而降", "顺手牵星", "临阵招降", "惊慌失措"]
const FOX_COSTS: Array[float] = [25.0, 40.0, 60.0, 70.0]
const FOX_COOLDOWNS: Array[float] = [30.0, 50.0, 65.0, 70.0]
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
const PIG_COOLDOWNS: Array[float] = [18.0, 30.0, 30.0, 70.0]
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

static func description(index: int, commander: StringName = COMMANDER_ID) -> String:
	if commander == PIG:
		return [
			"攻击力 +%d%%，移速 +%d%%，持续至进入建筑。\n己方建筑获得 %d 秒冲锋待命，强化下一次派出的部队。\n可与飞行、整队叠加；过期未出兵则失效。" % [roundi(PIG_CHARGE_ATTACK_BONUS * 100.0), roundi(PIG_CHARGE_SPEED_BONUS * 100.0), PIG_READY_DURATION],
			"下一次派兵直线飞行，无视地形，最多 %d 人。\n己方建筑获得 %d 秒飞行待命，过期未出兵则失效。\n剩余驻军留守，可与冲锋、整队叠加。" % [PIG_FLIGHT_LIMIT, PIG_READY_DURATION],
			"下一次派兵缩短排距和列距，最多 %d 人。\n己方建筑获得 %d 秒整队待命，过期未出兵则失效。\n剩余驻军留守；与飞行叠加时最多 %d 人。" % [PIG_FORMATION_LIMIT, PIG_READY_DURATION, PIG_FLIGHT_LIMIT],
			"半径 %.1f 米内，敌我行军部队全部死亡，建筑驻军减少 50%%。\n选择落点后 %.2f 秒砸下，无视防御力和链式分伤。\n不直接占领建筑，空地也可施放。" % [PIG_DROP_RADIUS, PIG_DROP_FALL_TIME]
		][index]
	if commander == FOX:
		return [
			"敌方或中立建筑损失当前驻军的 %d%%，最多 %d 人，向下取整。\n无视防御力，链式防守可分担；不直接占领。" % [roundi(FOX_BOMB_FRACTION * 100.0), FOX_BOMB_CAP],
			"偷取敌方最多 %d 星士气，己方最多 %d 星。\n以敌方建筑为目标，士气从其所属玩家转移给自己。\n不足 %d 星时转移实际数量；敌方无士气或己方已满时无法施放。" % [FOX_STEAL_STARS, 5, FOX_STEAL_STARS],
			"招降半径 %.1f 米内施放时的敌方行军部队。\n永久归己方指挥，保留位置、阵型和路线。\n抵达己方建筑时增援，抵达敌方建筑时进攻。" % FOX_CONVERT_RADIUS,
			"敌方建筑内 %d%% 的驻军逃走，人数向下取整。\n逃兵保持原阵营，分赴最近的最多 %d 座同阵营建筑。\n距离不限；没有可抵达的建筑时无法施放。" % [roundi(FOX_PANIC_FRACTION * 100.0), FOX_PANIC_DESTINATIONS]
		][index]
	if commander == FROG:
		return [
			"攻击力 -%d%%，作用于接触薄雾的敌军，持续至进入建筑。\n薄雾半径 %.1f 米，持续 %d 秒；炮塔无法攻击雾内士兵。\n增援人数不变。" % [roundi(FROG_WEAKNESS * 100.0), FROG_RADII[0], FROG_DURATIONS[0]],
			"半径 %.1f 米内，施放时的敌我行军部队滞空 %d 秒。\n期间无法移动，也不会被炮塔命中。\n落地后继续原路线，其他技能仍可影响。" % [FROG_RADII[1], FROG_DURATIONS[1]],
			"半径 %.1f 米内，施放时的己方行军部队隐身，持续至进入建筑。\n仅留下极淡轮廓，炮塔无法攻击。\n仍会受到火焰和法术伤害。" % FROG_RADII[2],
			"敌方或中立建筑损失当前驻军的 %d%%，等级降至 1 级。\n损失按整个人口计算，中断施工，不直接占领。\n无视防御力，链式防守无法分担。" % roundi(FROG_STRIKE_FRACTION * 100.0)
		][index]
	if commander == BEAR:
		return [
			"立即完成自己或盟友建筑的升级或改建。\n返还本次消耗人口的 50%，补入该建筑驻军。",
			"移速 -%d%%，作用于区域内的敌军。\n震地区域半径 %.1f 米，持续 %d 秒。\n离开区域后恢复原速，己方与盟友不受影响。" % [roundi((1.0 - BEAR_SLOW_MULTIPLIER) * 100.0), BEAR_SLOW_RADIUS, BEAR_DURATIONS[1]],
			"自己或盟友的建筑，由最近的另一座同队建筑分担 50%% 驻军伤害，持续 %d 秒。\n连接距离最多 %d 米，奇数伤亡由支援方多承担 1 人。\n支援兵力不足或一端失守时断开。" % [BEAR_DURATIONS[2], BEAR_LINK_RADIUS],
			"防御力 +%d%%，作用于自己或盟友建筑，持续 %d 秒。\n法术球立即开火，每 %.1f 秒攻击 %d 米内最多 %d 名敌兵。\n优先选择最远目标。" % [roundi(BEAR_WARD_DEFENSE * 100.0), BEAR_DURATIONS[3], BEAR_ORB_INTERVAL, BEAR_ORB_RANGE, BEAR_ORB_TARGETS]
		][index]
	if commander == RABBIT:
		return [
			"攻击力 +%d%%，移速 +%d%%，持续 %d 秒。\n仅作用于施放时半径 %.1f 米内的己方行军部队。\n离开范围后仍生效，同类效果不叠加。" % [roundi(RABBIT_RUSH_ATTACK_BONUS * 100.0), roundi((RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), RABBIT_DURATIONS[0], RABBIT_RUSH_RADIUS],
			"敌方建筑停工 %d 秒。\n暂停产兵、射击、铁匠铺攻防增益和能量塔技力恢复加成。\n不暂停升级或改建，同类效果不叠加。" % DISABLE_DURATION,
			"半径 %d 米内，所有阵营的行军部队返回各自出发建筑。\n返程途中仍会受到攻击。" % RECALL_RADIUS,
			"己方建筑获得 %d 秒兔洞待命，强化下一次派兵。\n经兔洞抵达目标附近，两座建筑间需有可通行路线。\n无距离限制，按所选比例最多 %d 人，每 %.2f 秒出洞一排。" % [BURROW_READY_DURATION, BURROW_LIMIT, BURROW_BATCH_INTERVAL]
		][index]
	return [
		"每秒征召 %d 人，持续 %d 秒。\n作用于己方或盟友住宅，可超过自然产兵上限。\n同类效果不叠加。" % [RECRUIT_RATE, DURATIONS[0]],
		"移速 +%d%%，作用于区域内的己方行军部队。\n疾行区域半径 %.1f 米，持续 %d 秒。\n离开区域后恢复原速。" % [roundi((HASTE_MULTIPLIER - 1.0) * 100.0), HASTE_RADIUS, DURATIONS[1]],
		"防御力 +%d%%，持续 %d 秒。\n作用于己方或盟友建筑，同类效果不叠加。\n与士气、铁匠铺等常驻防御力独立结算。" % [roundi(SHIELD_DEFENSE * 100.0), DURATIONS[2]],
		"基础伤害 %d，范围半径 %.1f 米。\n火焰从圆心扩散，消灭接触的敌我行军部队。\n伤害敌方和中立建筑驻军，不直接占领。" % [FIRE_DAMAGE, FIRE_RADIUS]
	][index]
