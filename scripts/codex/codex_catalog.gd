extends RefCounted
## Read-only catalogue text; shared rules remain the source of skill values.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const BUILDING := preload("res://scripts/block_war/war_building.gd")
const HEROES: Array[StringName] = [&"squirrel", &"rabbit", &"bear", &"frog"]


static func hero_profile(id: StringName) -> Dictionary:
	assert(id in HEROES)
	var profiles: Dictionary = {
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
			"summary": "加快据点建设，限制敌军推进，并保护关键阵地。",
			"note": "建筑技能仅作用于自己的据点；链式防守需要附近的自有建筑支援。",
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
	match id:
		&"squirrel":
			return [
				"为自己或盟友的住宅额外征召士兵，每秒 %d 人，持续 %d 秒。征召可超过自然产兵上限。" % [RULES.RECRUIT_RATE, RULES.DURATIONS[0]],
				"建立半径 %.1f 米的疾行区域，持续 %d 秒。自己的部队在区域内移速提高 %d%%，离开后恢复。" % [RULES.HASTE_RADIUS, RULES.DURATIONS[1], roundi((RULES.HASTE_MULTIPLIER - 1.0) * 100.0)],
				"为自己或盟友的建筑提供防护，守备提高 %d%%，持续 %d 秒。同类防护不叠加。" % [roundi(RULES.SHIELD_DEFENSE * 100.0), RULES.DURATIONS[2]],
				"火焰扩散至半径 %.1f 米，消灭接触的双方士兵。对敌方或中立驻军造成基础 %d 点伤害，不直接占领建筑。" % [RULES.FIRE_RADIUS, RULES.FIRE_DAMAGE],
			][index]
		&"rabbit":
			return [
				"强化施放时半径 %.1f 米内的自有行军，移速与攻击分别提高 %d%%、%d%%，持续 %d 秒。离开落点仍然有效。" % [RULES.RABBIT_RUSH_RADIUS, roundi((RULES.RABBIT_RUSH_MULTIPLIER - 1.0) * 100.0), roundi(RULES.RABBIT_RUSH_ATTACK_BONUS * 100.0), RULES.RABBIT_DURATIONS[0]],
				"干扰一座敌方建筑，持续 %d 秒。住宅停止产兵，炮塔停止射击，铁匠铺暂停提供攻击增益。" % RULES.DISABLE_DURATION,
				"令半径 %d 米内所有阵营的行军部队，各自返回出发建筑。返程途中仍会受到攻击。" % RULES.RECALL_RADIUS,
				"使自己的建筑进入 %d 秒兔洞待命。下一次派兵经兔洞抵达目标附近，按所选比例最多派出 %d 人。" % [RULES.BURROW_READY_DURATION, RULES.BURROW_LIMIT],
			][index]
		&"bear":
			return [
				"立即完成自己建筑的升级或改建，返还本次消耗人口的 50%。",
				"建立半径 %.1f 米的震地区域，持续 %d 秒。区域内敌军移速降低 %d%%，离开后恢复，盟友不受影响。" % [RULES.BEAR_SLOW_RADIUS, RULES.BEAR_DURATIONS[1], roundi((1.0 - RULES.BEAR_SLOW_MULTIPLIER) * 100.0)],
				"连接 %d 米内最近的另一座自己的建筑，由其分担目标所受驻军伤害的一半，持续 %d 秒。支援兵力耗尽或一端失守时解除。" % [RULES.BEAR_LINK_RADIUS, RULES.BEAR_DURATIONS[2]],
				"使自己的建筑无敌 %d 秒，敌军在外围等待。法术球优先攻击 %d 米内较远的敌兵，每 %.1f 秒击杀 1 人。" % [RULES.BEAR_DURATIONS[3], RULES.BEAR_ORB_RANGE, RULES.BEAR_ORB_INTERVAL],
			][index]
		&"frog":
			return [
				"建立半径 %.1f 米的薄雾，持续 %d 秒。接触的敌军攻击降低 %d%%，持续至入城；炮塔无法攻击雾内士兵。" % [RULES.FROG_RADII[0], RULES.FROG_DURATIONS[0], roundi(RULES.FROG_WEAKNESS * 100.0)],
				"使半径 %.1f 米内当前的双方士兵滞空 %d 秒。期间无法移动，也不会被炮塔命中；落地后继续原路线。" % [RULES.FROG_RADII[1], RULES.FROG_DURATIONS[1]],
				"使施放时半径 %.1f 米内的自有士兵隐身，持续至进入建筑。可避开炮塔攻击，仍会受到火焰和法术伤害。" % RULES.FROG_RADII[2],
				"移除敌方或中立建筑当前驻军的 %d%%，按整个人口计算，降至 1 级并中断施工。不会直接占领；无敌可阻挡，链式防守无法分担。" % roundi(RULES.FROG_STRIKE_FRACTION * 100.0),
			][index]
	return ""


static func skill_target(id: StringName, index: int) -> String:
	assert(id in HEROES and index >= 0 and index < 4)
	var targets: Dictionary = {
		&"squirrel": ["自己或盟友住宅", "地面区域", "自己或盟友建筑", "地面区域"],
		&"rabbit": ["自己的行军部队", "敌方建筑", "所有阵营的行军部队", "自己的建筑"],
		&"bear": ["自己正在施工的建筑", "地面区域", "自己的建筑", "自己的建筑"],
		&"frog": ["地面区域", "双方行军部队", "自己的行军部队", "敌方或中立建筑"],
	}
	return targets[id][index]


static func guides() -> Array[Dictionary]:
	return [
		{
			"id": &"dispatch", "title": "派兵与增援", "tag": "基础指挥",
			"summary": "按所选比例派遣驻军，进攻据点或支援队友。",
			"sections": [
				{"title": "下达军令", "body": "从自己的建筑拖向目标，松手派兵。进入敌方或中立建筑时交战，进入自己或盟友的建筑时补充驻军。"},
				{"title": "派遣比例", "body": "可选择 25%、50%、75% 或 100%，人数按可用驻军向下取整。数字键 1—4 切换比例，拖动时也可用滚轮调整。"},
				{"title": "出发队列", "body": "部队依次出发。已编入队列的士兵无法重复派遣，但离开建筑前仍参与防守。"},
			],
			"tip": "增援进入盟友建筑后，归接收方指挥。",
			"icon": preload("res://assets/ui/block_war/action_population.svg"),
		},
		{
			"id": &"victory", "title": "占领与胜负", "tag": "对局目标",
			"summary": "夺取据点，消灭敌方队伍最后的行军部队。",
			"sections": [
				{"title": "据点占领", "body": "击败驻军后，存活的进攻部队占领建筑。建筑被占领时降低 1 级，最低为 1 级，并中断尚未完成的施工。"},
				{"title": "胜利条件", "body": "敌方队伍失去全部建筑与行军部队后，我方获胜。敌方仍有行军部队时，对局继续。"},
				{"title": "僵局", "body": "若双方均只剩无法产兵且不足 1 人的据点，也没有行军部队，对局以平局结束。"},
			],
			"tip": "技能削减驻军不会直接改变建筑归属。",
			"icon": preload("res://assets/ui/block_war/bulwark.svg"),
		},
		{
			"id": &"residence", "title": "住宅", "tag": "建筑 · 兵力生产",
			"summary": "持续补充驻军，是维持战线的兵力来源。",
			"sections": [
				{"title": "产兵速度", "body": "住宅共有 4 级，各级每秒产兵 %s / %s / %s / %s 人。升级可提高产兵速度。" % BUILDING.HOUSE_PRODUCTION_RATES},
				{"title": "自然产兵上限", "body": "各级自然产兵上限为 %d / %d / %d / %d 人。达到上限后暂停自然产兵，驻军减少后继续。" % BUILDING.HOUSE_PRODUCTION_LIMITS},
			],
			"tip": "自然产兵上限不是驻军上限；增援与征召可以超出。",
			"icon": preload("res://assets/ui/block_war/action_house.svg"),
		},
		{
			"id": &"tower", "title": "炮塔", "tag": "建筑 · 区域防守",
			"summary": "自动拦截附近敌军，并为驻军提供额外守备。",
			"sections": [
				{"title": "射程与火力", "body": "炮塔共有 3 级。射程依次为 11 / 13 / 15 米，每轮最多攻击 1 / 2 / 3 名敌兵；射击间隔为 1.5 / 1.2 / 0.9 秒。"},
				{"title": "守备与限制", "body": "各级守备为 5% / 10% / 15%。炮塔不会自然产兵；隐身、滞空或处于薄雾内的士兵可避开炮塔攻击。"},
			],
			"tip": "将炮塔布置在必经路线附近，可持续削弱敌方行军。",
			"icon": preload("res://assets/ui/block_war/action_tower.svg"),
		},
		{
			"id": &"smithy", "title": "铁匠铺", "tag": "建筑 · 攻击支援",
			"summary": "为所属玩家的全军提供可累加的攻击增益。",
			"sections": [
				{"title": "攻击增益", "body": "每座正在运作的铁匠铺提供 10% 攻击加成，多座效果累加。增益只属于建筑拥有者，不共享给队友。"},
				{"title": "建筑特性", "body": "铁匠铺仅有 1 级，不支持升级，也不会自然产兵。受到封条急件干扰时，暂时停止提供增益。"},
			],
			"tip": "铁匠铺加成与守备先加减，再应用士气的攻防系数。",
			"icon": preload("res://assets/ui/block_war/action_forge.svg"),
		},
		{
			"id": &"construction", "title": "升级与改建", "tag": "据点经营",
			"summary": "消耗驻军提升建筑等级，或更换据点功能。",
			"sections": [
				{"title": "升级", "body": "住宅升至 2 / 3 / 4 级，依次消耗 10 / 20 / 30 人；炮塔升至 2 / 3 级，依次消耗 30 / 60 人。只能使用尚未编入出发队列的驻军。"},
				{"title": "改建", "body": "改建消耗 20 人，可在住宅、炮塔和铁匠铺之间转换。完成后，新建筑从 1 级开始。"},
				{"title": "施工", "body": "升级与改建均需 %d 秒。期间保留原有功能；失守时施工中断，已消耗的人口不会返还。" % BUILDING.CONSTRUCTION_DURATION},
			],
			"tip": "封条急件暂停建筑运作，不暂停升级或改建计时。",
			"icon": preload("res://assets/ui/block_war/action_upgrade.svg"),
		},
		{
			"id": &"terrain", "title": "地形与行军", "tag": "战场路线",
			"summary": "利用桥梁和山道组织进攻，控制关键通路。",
			"sections": [
				{"title": "通行路线", "body": "部队沿可通行路线前进。水域和山地阻挡通行，桥梁连接两岸；派兵前的路线预览显示实际行进方向。"},
				{"title": "途中交互", "body": "双方行军部队可以互相穿行，不在途中进行近战。炮塔、火焰与其他技能仍可影响行军。"},
				{"title": "兔洞运输", "body": "兔洞可将部队快速送至目标附近，但两座建筑之间仍须存在可通行路线。出洞后继续向目标行军。"},
			],
			"tip": "派兵时同时观察路线长度与沿途敌方炮塔。",
			"icon": preload("res://assets/ui/block_war/skill_haste.svg"),
		},
		{
			"id": &"morale", "title": "士气", "tag": "军团状态",
			"summary": "通过战斗和建设积累士气，提高全军表现。",
			"sections": [
				{"title": "士气变化", "body": "占领据点、完成升级和击杀敌军可积累士气。进攻损失与据点失守会降低士气；建筑改建本身不提供升级奖励。"},
				{"title": "星级增益", "body": "每颗完整士气星提供攻击 5%、防御 25%、移速 10% 加成，最多 5 星。下一颗星的部分充能尚不提供增益。"},
				{"title": "自然衰减", "body": "没有士气事件时，士气会在一段时间后逐渐衰减。星级越高，开始衰减越早，衰减速度也越快。"},
			],
			"tip": "每位玩家独立计算士气，队友之间不共享星级。",
			"icon": preload("res://assets/ui/block_war/morale_star.svg"),
		},
		{
			"id": &"skills", "title": "技力与施法", "tag": "指挥官技能",
			"summary": "技力决定施法资源，冷却限制技能使用频率。",
			"sections": [
				{"title": "技力恢复", "body": "每局初始技力为 30 点，每秒恢复 %d 点，上限 %d 点。四项技能共用技力，各自独立冷却。" % [RULES.ENERGY_REGEN, RULES.ENERGY_MAX]},
				{"title": "瞄准与释放", "body": "拖动技能图标，或按住 Q、W、E、R 瞄准，松手施放。不同技能需要指定建筑、士兵或地面区域。"},
				{"title": "取消施法", "body": "右键可以取消瞄准。取消或无效施放不扣除技力，也不进入冷却；电脑遵循相同的技力与冷却规则。"},
			],
			"tip": "查看技能的目标与作用范围，避免对友军造成误伤。",
			"icon": preload("res://assets/ui/block_war/skill_muster.svg"),
		},
		{
			"id": &"teams", "title": "队伍协作", "tag": "多人战术",
			"summary": "与队友共享胜负，通过增援和协同进攻扩大优势。",
			"sections": [
				{"title": "队伍规模", "body": "战场支持 1v1、2v2 和 3v3。团队对局以整支队伍的建筑和行军部队判定胜负。"},
				{"title": "独立资源", "body": "建筑、技力、士气与铁匠铺攻击加成分别归各玩家所有。玩家只能从自己的建筑派兵、升级或改建。"},
				{"title": "相互支援", "body": "派往盟友建筑的部队会补充其驻军，抵达后归接收方指挥。松鼠的征召军令与防护罩也可用于盟友建筑。"},
			],
			"tip": "据点失守后仍有队友作战时，团队对局会继续。",
			"icon": preload("res://assets/ui/block_war/skill_bear_link.svg"),
		},
		{
			"id": &"controls", "title": "镜头与快捷键", "tag": "操作指南",
			"summary": "快速调整视野，在行军与据点管理之间切换。",
			"sections": [
				{"title": "镜头操作", "body": "将指针移至屏幕边缘，或按住鼠标中键拖动，可移动镜头。滚轮缩放；选中建筑后按空格聚焦。"},
				{"title": "战斗快捷键", "body": "数字键 1—4 对应派遣 25%、50%、75%、100%。Q、W、E、R 对应四项技能，按住瞄准、松手释放。"},
				{"title": "菜单与帮助", "body": "F1 查看战场操作说明，Esc 打开或关闭战场菜单。拖动派兵时，滚轮改为调整派遣比例。"},
			],
			"tip": "右键可以取消当前派兵拖动或技能瞄准。",
			"icon": preload("res://assets/ui/block_war/drum.svg"),
		},
	]
