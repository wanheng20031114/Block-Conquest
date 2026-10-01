extends RefCounted
## Read-only catalogue text; shared rules remain the source of skill values.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const BUILDING := preload("res://scripts/block_war/war_building.gd")
const COMBAT := preload("res://scripts/block_war/war_combat_rules.gd")
const MARCHES := preload("res://scripts/block_war/war_marches.gd")
const GUIDE_ICONS := preload("res://assets/ui/block_war/codex_icons.tres")
const HEROES: Array[StringName] = [&"squirrel", &"rabbit", &"bear", &"frog", &"fox", &"pig"]


static func hero_profile(id: StringName) -> Dictionary:
	assert(id in HEROES)
	var profiles: Dictionary = {
		&"pig": {
			"title": RULES.name_for(id), "subtitle": "出征准备与精准重击",
			"summary": "提前强化下一次出兵，让部队冲锋、起飞或紧密集结；以特大猪砸破密集阵地。",
			"note": "出征准备可叠加；同时飞行和整队时，最多派出 30 人。特大猪会伤及双方。",
		},
		&"fox": {
			"title": RULES.name_for(id), "subtitle": "诡计与阵线瓦解",
			"summary": "投弹削弱据点，偷取敌方士气，招降行军并驱散驻军。",
			"note": "招降永久改变阵营；恐慌保留逃兵原阵营，不会消灭这些士兵。",
		},
		&"squirrel": {
			"title": RULES.name_for(id),
			"subtitle": "增援与均衡作战",
			"summary": "兼顾兵力补充、机动支援与据点防御，适合稳定推进。",
			"note": "征召与防护罩可支援盟友；火焰会伤及双方行军部队。",
		},
		&"rabbit": {
			"title": RULES.name_for(id),
			"subtitle": "机动与战线干扰",
			"summary": "以高速调动、建筑干扰和兔洞突袭改变战线。",
			"note": "冲刺仅强化施放时选中的部队；归巢口哨影响所有阵营。",
		},
		&"bear": {
			"title": RULES.name_for(id),
			"subtitle": "建设与据点守护",
			"summary": "直接升级据点，封住敌方出兵，并用火球守护或压制建筑。",
			"note": "工具箱与链式防守可支援盟友；震庭威慑对敌我建筑效果不同。",
		},
		&"frog": {
			"title": RULES.name_for(id),
			"subtitle": "控制与法术削弱",
			"summary": "运用弱化、滞空与隐身干扰行军，再以法术削弱据点。",
			"note": "隐身与滞空可避开炮塔，但仍会受到火焰和法术伤害。",
		},
	}
	return profiles[id]


static func skill_summary(id: StringName, index: int) -> String:
	assert(id in HEROES and index >= 0 and index < 4)
	return RULES.description(index, id)


static func skill_target(id: StringName, index: int) -> String:
	assert(id in HEROES and index >= 0 and index < 4)
	var targets: Dictionary = {
		&"pig": ["自己的建筑", "自己的建筑", "自己的建筑", "任意地面 · 敌我全部受影响"],
		&"fox": ["敌方或中立建筑", "有士气的敌方英雄所属建筑", "敌方行军部队", "有同阵营避难建筑的敌方据点"],
		&"squirrel": ["自己或盟友住宅", "地面区域", "自己或盟友建筑", "地面区域"],
		&"rabbit": ["自己的行军部队", "敌方建筑", "所有阵营的行军部队", "自己的建筑"],
		&"bear": ["未满级、未改建的自己或盟友建筑", "敌方建筑", "自己或盟友建筑", "自己、盟友或敌方建筑"],
		&"frog": ["地面区域", "双方行军部队", "自己的行军部队", "敌方或中立建筑"],
	}
	return targets[id][index]


static func guides() -> Array[Dictionary]:
	return [
		{
			"id": &"dispatch", "title": "派兵与增援", "tag": "基础指挥",
			"summary": "按所选比例派遣驻军，进攻据点或支援队友。",
			"sections": [
				{"title": "下达军令", "body": "从自己的建筑拖向目标，松手派兵。空地拖出选框可选中多栋己方建筑，再从任意已选建筑拖向目标，一起派兵；松开选框只完成选择。进入敌方或中立建筑时交战，进入自己或盟友的建筑时补充驻军。"},
				{"title": "选择与比例", "body": "Shift 点选增减、框选追加；短点建筑切回单选，点击空地清空选择。数字键 1—4 选择 25%、50%、75%、100%，派兵拖动时滚轮也能调整。多选按每栋可用驻军分别向下取整，提示数字为总人数。"},
				{"title": "出发队列", "body": "部队从各自建筑依次出发。已编入队列的士兵无法重复派遣，离开前仍参与防守。目标若已被选中，其他建筑会向它增援；出兵后保留选择。空驻军、失守或无法到达的来源单独跳过。"},
			],
			"tip": "增援进入盟友建筑后，归接收方指挥。",
			"icon": GUIDE_ICONS.get_meta(&"dispatch"),
		},
		{
			"id": &"victory", "title": "占领与胜负", "tag": "对局目标",
			"summary": "夺取据点，消灭敌方队伍最后的行军部队。",
			"sections": [
				{"title": "据点占领", "body": "击败驻军后，存活的进攻部队占领建筑。建筑被占领时降低 1 级，最低为 1 级，并中断尚未完成的施工。"},
				{"title": "胜利条件", "body": "敌方队伍失去全部建筑与行军部队后，我方获胜。敌方仍有行军部队时，对局继续。"},
				{"title": "僵局", "body": "若双方均只剩无法产兵且不足 1 人的据点，也没有行军部队，对局以平局结束。"},
			],
			"tip": "敌方建筑不显示人口图标；己方、盟友和中立建筑仍显示驻军数量。",
			"icon": GUIDE_ICONS.get_meta(&"victory"),
		},
		{
			"id": &"residence", "title": "住宅", "tag": "建筑 · 兵力生产",
			"summary": "持续补充驻军，是维持战线的兵力来源。",
			"table": {
				"headers": ["等级", "产兵\n人/秒", "驻扎容量\n人", "防御力", "升级消耗\n人", "升级耗时\n秒"],
				"rows": [
					["1", str(BUILDING.HOUSE_PRODUCTION_RATES[0]), "%d" % BUILDING.HOUSE_PRODUCTION_LIMITS[0], "+%d%%" % roundi(COMBAT.house_defense_bonus(1) * 100.0), str(BUILDING.HOUSE_UPGRADE_COSTS[0]), "%d" % BUILDING.upgrade_duration(0, 1)],
					["2", str(BUILDING.HOUSE_PRODUCTION_RATES[1]), "%d" % BUILDING.HOUSE_PRODUCTION_LIMITS[1], "+%d%%" % roundi(COMBAT.house_defense_bonus(2) * 100.0), str(BUILDING.HOUSE_UPGRADE_COSTS[1]), "%d" % BUILDING.upgrade_duration(0, 2)],
					["3", str(BUILDING.HOUSE_PRODUCTION_RATES[2]), "%d" % BUILDING.HOUSE_PRODUCTION_LIMITS[2], "+%d%%" % roundi(COMBAT.house_defense_bonus(3) * 100.0), str(BUILDING.HOUSE_UPGRADE_COSTS[2]), "%d" % BUILDING.upgrade_duration(0, 3)],
					["4", str(BUILDING.HOUSE_PRODUCTION_RATES[3]), "%d" % BUILDING.HOUSE_PRODUCTION_LIMITS[3], "+%d%%" % roundi(COMBAT.house_defense_bonus(4) * 100.0), "—", "—"],
				],
			},
			"sections": [
				{"title": "规则说明", "body": "升级消耗与耗时均指升至下一级，4 级已满级。\n施工期间产兵、驻扎容量与防御力保持原等级。\n建筑防御力与士气、铁匠铺加成相加，技能独立结算。"},
			],
			"tip": "达到驻扎容量只暂停自然产兵；增援与征召人数不限。驻军低于容量后恢复产兵。",
			"icon": GUIDE_ICONS.get_meta(&"residence"),
		},
		{
			"id": &"tower", "title": "炮塔", "tag": "建筑 · 区域防守",
			"summary": "自动拦截附近敌军，并为驻军提供防御力加成。",
			"table": {
				"headers": ["等级", "射程\n米", "攻击间隔\n秒", "每轮目标\n人", "防御力", "升级消耗\n人", "升级耗时\n秒"],
				"rows": [
					["1", "%d" % (9.0 + 1 * 2.0), str(COMBAT.tower_attack_interval(1)), "1", "+%d%%" % roundi(COMBAT.tower_defense_bonus(1) * 100.0), str(1 * 30), "%d" % BUILDING.upgrade_duration(1, 1)],
					["2", "%d" % (9.0 + 2 * 2.0), str(COMBAT.tower_attack_interval(2)), "2", "+%d%%" % roundi(COMBAT.tower_defense_bonus(2) * 100.0), str(2 * 30), "%d" % BUILDING.upgrade_duration(1, 2)],
					["3", "%d" % (9.0 + 3 * 2.0), str(COMBAT.tower_attack_interval(3)), "3", "+%d%%" % roundi(COMBAT.tower_defense_bonus(3) * 100.0), str(3 * 30), "%d" % BUILDING.upgrade_duration(1, 3)],
					["4", "%d" % (9.0 + 4 * 2.0), str(COMBAT.tower_attack_interval(4)), "4", "+%d%%" % roundi(COMBAT.tower_defense_bonus(4) * 100.0), "—", "—"],
				],
			},
			"sections": [
				{"title": "规则说明", "body": "升级消耗与耗时均指升至下一级，4 级已满级。\n施工期间射程、射速与防御力保持原等级；每轮目标为最多攻击人数。\n建筑防御力与士气、铁匠铺加成相加，技能独立结算。"},
			],
			"tip": "炮塔不产兵；无法攻击隐身、滞空或雾内士兵。中立炮塔只提供防御力，不主动开火。",
			"icon": GUIDE_ICONS.get_meta(&"tower"),
		},
		{
			"id": &"smithy", "title": "铁匠铺", "tag": "建筑 · 全军支援",
			"summary": "为所属玩家全军提供攻击力与防御力加成。",
			"sections": [
				{"title": "攻防增益", "body": "按有效铁匠铺总数计算累计加成：\n1 座：攻击力 +%d%%，防御力 +%d%%。\n2 座：攻击力 +%d%%，防御力 +%d%%。\n3 座：攻击力 +%d%%，防御力 +%d%%。\n4 座及以上：攻击力 +%d%%，防御力 +%d%%。" % [roundi(COMBAT.forge_attack_bonus(1) * 100.0), roundi(COMBAT.forge_defense_bonus(1) * 100.0), roundi(COMBAT.forge_attack_bonus(2) * 100.0), roundi(COMBAT.forge_defense_bonus(2) * 100.0), roundi(COMBAT.forge_attack_bonus(3) * 100.0), roundi(COMBAT.forge_defense_bonus(3) * 100.0), roundi(COMBAT.forge_attack_bonus(4) * 100.0), roundi(COMBAT.forge_defense_bonus(4) * 100.0)]},
				{"title": "加成归属", "body": "铁匠铺不提供移速加成。攻防增益只属于建筑拥有者，不共享给队友。"},
				{"title": "建筑特性", "body": "铁匠铺仅有 1 级，不支持升级，也不会自然产兵。可改建为能量塔；受到封条急件干扰时，暂时停止提供全部增益。"},
			],
			"tip": "铁匠铺与士气的同类加成相加；住宅、炮塔的防御力加成计入常驻防御，技能加成独立结算。",
			"icon": GUIDE_ICONS.get_meta(&"smithy"),
		},
		{
			"id": &"energy", "title": "能量塔", "tag": "建筑 · 技力补充",
			"summary": "由铁匠铺改建，提高技力恢复速度，并奖励成功进攻。",
			"sections": [
				{"title": "技力恢复", "body": "每座有效能量塔提供额外恢复：\n第 1 座：+%s 点/秒；第 2 座：+%s 点/秒；\n第 3 座：+%s 点/秒；第 4 座起每座：+%s 点/秒。\n收益按玩家独立计算，技力上限 %d 点；封条急件期间暂停加成。" % [RULES.ENERGY_TOWER_BONUSES[0], RULES.ENERGY_TOWER_BONUSES[1], RULES.ENERGY_TOWER_BONUSES[2], RULES.ENERGY_TOWER_LATER_BONUS, RULES.ENERGY_MAX]},
				{"title": "夺取奖励", "body": "从能量塔派出的部队夺取敌方建筑时，立即获得 10 点技力。每次成功占领结算一次，奖励不随塔数增加；占领中立建筑不触发。"},
				{"title": "建设限制", "body": "仅铁匠铺可改建为能量塔，消耗 20 人，耗时 %d 秒。能量塔不产兵、不可升级，可改建回住宅、炮塔或铁匠铺。" % BUILDING.CONSTRUCTION_DURATION},
			],
			"tip": "部队来源以发令时的建筑类型为准；原塔改造或易主不影响已发军令。进入建筑后，下次出征重新判定。",
			"icon": GUIDE_ICONS.get_meta(&"energy"),
		},
		{
			"id": &"construction", "title": "升级与改建", "tag": "据点经营",
			"summary": "消耗驻军提升建筑等级，或更换据点功能。",
			"sections": [
				{"title": "升级", "body": "住宅：升至 2 级消耗 %d 人，3 级消耗 %d 人，4 级消耗 %d 人。\n炮塔：升至 2 级消耗 30 人，3 级消耗 60 人，4 级消耗 90 人。\n只能使用尚未编入出发队列的驻军。" % BUILDING.HOUSE_UPGRADE_COSTS},
				{"title": "改建", "body": "改建消耗 20 人。住宅、炮塔和铁匠铺可互相转换；仅铁匠铺可改建为能量塔，能量塔可改回前三种建筑。完成后，新建筑从 1 级开始。"},
				{"title": "施工", "body": "住宅：1 → 2 级 %d 秒，2 → 3 级 %d 秒，3 → 4 级 %d 秒。\n炮塔：1 → 2 级 %d 秒，后续升级各 %d 秒。改建均需 %d 秒。\n期间保留原有功能与防御力；失守中断施工，消耗不返还。" % [BUILDING.upgrade_duration(0, 1), BUILDING.upgrade_duration(0, 2), BUILDING.upgrade_duration(0, 3), BUILDING.upgrade_duration(1, 1), BUILDING.upgrade_duration(1, 2), BUILDING.CONSTRUCTION_DURATION]},
			],
			"tip": "封条急件暂停建筑运作，不暂停升级或改建计时。",
			"icon": GUIDE_ICONS.get_meta(&"construction"),
		},
		{
			"id": &"terrain", "title": "地形与行军", "tag": "战场路线",
			"summary": "利用桥梁和山道组织进攻，控制关键通路。",
			"sections": [
				{"title": "通行路线", "body": "基础移速 %s 米/秒，士气与技能可改变移速。部队沿可通行路线前进；水域和山地阻挡通行，桥梁连接两岸。路线预览显示实际行进方向。" % MARCHES.SPEED},
				{"title": "途中交互", "body": "双方行军部队可以互相穿行，不在途中进行近战。炮塔、火焰与其他技能仍可影响行军。"},
				{"title": "特殊机动", "body": "兔洞将部队送至目标附近，两楼仍须有可通行路线。猪会飞则可无视地形、直线前往目的地，最多派出 30 人；与猪整队叠加仍取 30 人上限，其余驻军留在建筑。"},
			],
			"tip": "派兵时同时观察路线长度与沿途敌方炮塔。",
			"icon": GUIDE_ICONS.get_meta(&"terrain"),
		},
		{
			"id": &"morale", "title": "士气", "tag": "军团状态",
			"summary": "通过战斗和建设积累士气，提高全军表现。",
			"sections": [
				{"title": "士气变化", "body": "占领据点、完成升级和击杀敌军可积累士气。进攻损失与据点失守会降低士气；建筑改建本身不提供升级奖励。"},
				{"title": "星级增益", "body": "每颗完整士气星：攻击力 +5%%，防御力 +%d%%，移速 +10%%。\n最多 5 星；下一颗星尚未充满时不提供额外增益。" % roundi(WarMorale.DEFENSE_PER_STAR * 100.0)},
				{"title": "自然衰减", "body": "没有士气事件时，士气会在一段时间后逐渐衰减。星级越高，开始衰减越早，衰减速度也越快。"},
			],
			"tip": "每位玩家独立计算士气，队友之间不共享星级。",
			"icon": GUIDE_ICONS.get_meta(&"morale"),
		},
		{
			"id": &"skills", "title": "技力与施法", "tag": "指挥官技能",
			"summary": "技力决定施法资源，冷却限制技能使用频率。",
			"sections": [
				{"title": "自然恢复", "body": "开局 %d 点技力，上限 %d 点。前 %d 秒自然恢复 %d 点/秒，之后 %d 点/秒；暂停不计时。能量塔额外加速恢复，悬停技力条可查看当前数值。" % [RULES.ENERGY_INITIAL, RULES.ENERGY_MAX, RULES.ENERGY_ACCELERATION_TIME, RULES.ENERGY_REGEN, RULES.ENERGY_LATE_REGEN]},
				{"title": "战损回能", "body": "建筑交战中，己方每实际损失 1 人：\n战前士气不足 3 星：技力 +0.2；\n3 星至不足 5 星：技力 +0.15；5 星：技力 +0.1。\n攻守均计，包含进攻中立和链式分担；技能直接杀伤、路上伤亡不计。"},
				{"title": "施法与取消", "body": "四项技能共用技力、独立冷却。拖动图标或按住 Q/W/E/R 瞄准，松手施放，右键取消。取消或无效施放不扣技力、不进冷却；电脑遵循相同规则。"},
			],
			"tip": "查看技能的目标与作用范围，避免对友军造成误伤。",
			"icon": GUIDE_ICONS.get_meta(&"skills"),
		},
		{
			"id": &"teams", "title": "队伍协作", "tag": "多人战术",
			"summary": "与队友共享胜负，通过增援和协同进攻扩大优势。",
			"sections": [
				{"title": "队伍规模", "body": "战场支持 1v1、2v2 和 3v3。团队对局以整支队伍的建筑和行军部队判定胜负。"},
				{"title": "独立资源", "body": "建筑、技力、士气、铁匠铺全军增益与能量塔收益均按玩家独立计算。玩家只能从自己的建筑派兵、升级或改建。"},
				{"title": "相互支援", "body": "派往盟友建筑的部队会补充其驻军，抵达后归接收方指挥。松鼠的征召军令、防护罩，以及熊的工具箱、链式防守、震庭威慑都可用于盟友建筑。"},
			],
			"tip": "据点失守后仍有队友作战时，团队对局会继续。",
			"icon": GUIDE_ICONS.get_meta(&"teams"),
		},
		{
			"id": &"controls", "title": "镜头与快捷键", "tag": "操作指南",
			"summary": "快速调整视野，在行军与据点管理之间切换。",
			"sections": [
				{"title": "镜头操作", "body": "将指针移至屏幕边缘，或按住鼠标中键拖动，可移动镜头。滚轮缩放；选中建筑后按空格聚焦。"},
				{"title": "战斗快捷键", "body": "数字键 1—4 对应派遣 25%、50%、75%、100%。Q、W、E、R 对应四项技能，按住瞄准、松手释放。"},
				{"title": "菜单与帮助", "body": "F1 查看战场操作说明，Esc 打开或关闭战场菜单。拖动派兵时，滚轮改为调整派遣比例。"},
			],
			"tip": "右键取消当前框选、派兵拖动或技能瞄准；没有拖动时清空选择。",
			"icon": GUIDE_ICONS.get_meta(&"controls"),
		},
	]
