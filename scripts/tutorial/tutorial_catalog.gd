extends RefCounted
## Two continuous core chapters and optional focused advanced practice.
const BUILDING := preload("res://scripts/block_war/war_building.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const COMBAT := preload("res://scripts/block_war/war_combat_rules.gd")
const CORE_IDS: Array[String] = ["core_command", "core_buildings"]
const ADVANCED_IDS: Array[String] = ["house", "morale", "tower", "forge", "energy", "recruit", "drum", "shield", "fire"]
const IDS: Array[String] = ["core_command", "core_buildings", "house", "morale", "tower", "forge", "energy", "recruit", "drum", "shield", "fire"]
const TITLES: Array[String] = ["第一章 · 基础指挥", "第二章 · 建筑与技能", "住宅升级", "士气与战果", "炮塔防线", "铁匠铺加成", "技力恢复", "征召军令", "疾行战鼓", "防护罩", "天降冲击"]
const SUMMARIES: Array[String] = ["移动视野、拖动调兵，读懂战场面板。", "亲手改建三种建筑，连贯使用四个技能。", "了解产兵与容量，亲手升级住宅。", "占领据点，点亮士气星星。", "增援炮塔，守住路口。", "占领铁匠铺，提高全军攻防。", "占领能量塔，加快技力恢复。", "突破产兵上限，补兵扩张。", "加速行军，及时增援。", "给前哨加盾，减少守军损失。", "瞄准密集敌军，避开己军。"]

static func title(id: String) -> String:
	return TITLES[IDS.find(id)]

static func summary(id: String) -> String:
	return SUMMARIES[IDS.find(id)]

static func ids() -> Array[String]:
	return IDS.duplicate()

static func minutes(id: String) -> String:
	if id == "core_command": return "约 2 分钟"
	if id == "core_buildings": return "约 4 分钟"
	return "约 2 分钟" if id in ["house", "recruit"] else "约 1 分钟"

static func step(heading: String, body: String, goal: String, action: String, focus: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"title": heading, "body": body, "goal": goal, "action": action, "focus": focus, "labels": []}
	result.merge(extra, true)
	return result

static func steps(id: String) -> Array[Dictionary]:
	match id:
		"core_command": return [
			step("先看清战场", "在地图空白处滚动滚轮，试着拉近视野。", "滚动滚轮，缩放视野", "zoom", "world"),
			step("移动视野", "按住中键拖动地图，再松开。\n也可以按方向键移动。", "中键拖动，或按方向键", "pan", "world"),
			step("认出你的部队", "金旗是己方，灰旗是中立。\n建筑上的数字是驻军，住宅会自动产兵。", "找到己方住宅与中立据点", "read", "buildings", {"labels": ["ownership", "population"], "reset_view": true}),
			step("拖动调兵", "按住金旗住宅，拖到灰旗据点后松开。\n默认派出一半驻军；右键可取消。", "拖动派兵，占领中立据点", "capture", "buildings", {"source": 0, "target": 1}),
			step("顶部：战况", "两侧数字是总兵力，色条显示兵力占比。\n下方计时记录对局时长。", "认识兵力与计时", "read", "top"),
			step("星星：士气", "占领与防守能提高士气。\n星星越多，全军攻防和移速越高。", "找到双方士气", "read", "morale"),
			step("左侧：出兵比例", "比例决定每次派出多少驻军。\n尝试一次调节比例，点击任意其他比例。", "尝试一次调节比例", "ratio", "ratios", {"any_ratio": true}),
			step("下方：技能与技力", "四个图标是技能，细条是共用技力。\n施法消耗技力，冷却结束后才能再用。", "认识技能栏与技力条", "read", "skills"),
			step("建筑旁：升级与改建", "选中己方建筑，就能升级或改建。\n第二章会带你逐一试用建筑与技能。", "已掌握基础指挥", "read", "selection")]
		"core_buildings": return [
			step("先建一座炮塔", "点击炮塔图标，改建选中的住宅。\n本章已备好兵力，改建只需 1.2 秒。", "点击炮塔图标", "convert", "convert", {"beat": "make_tower", "target": 1, "kind": 1}),
			step("炮塔：守住路口", "炮塔会自动射击射程内的敌军。\n一小队敌人即将来袭，看看它怎样守住路口。", "观察炮塔击退敌军", "tower_watch", "building:1", {"beat": "tower_demo", "labels": ["range"], "stats": [["射击间隔", "%s 秒" % COMBAT.tower_attack_interval(1)], ["防御加成", "+%d%%" % roundi(COMBAT.tower_defense_bonus(1) * 100)], ["自然产兵", "不产兵"]]}),
			step("换成铁匠铺", "这次点击铁匠铺图标，改建刚才的炮塔。", "将炮塔改建为铁匠铺", "convert", "convert", {"beat": "make_forge", "target": 1, "kind": 2}),
			step("铁匠铺：以少胜多", "全军攻防已提高。\n从后方住宅派出 20 人，攻下驻军 24 人的据点。", "拖动后方住宅，用 20 人攻下 24 人据点", "capture", "buildings", {"beat": "forge_trial", "source": 0, "target": 2, "stats": [["全军攻击", "+%d%%" % roundi(COMBAT.forge_attack_bonus(1) * 100)], ["全军防御", "+%d%%" % roundi(COMBAT.forge_defense_bonus(1) * 100)], ["自然产兵", "不产兵"]]}),
			step("再改建能量塔", "铁匠铺可以改建为能量塔。\n点击能量塔图标试一试。", "将铁匠铺改建为能量塔", "convert", "convert", {"beat": "make_energy", "target": 1, "kind": 3}),
			step("能量塔：更快恢复技力", "看下方的技力条，恢复速度已经提高。", "观察技力条增长", "energy_watch", "energy", {"beat": "energy_demo", "stats": [["基础恢复", "%s 点/秒" % RULES.ENERGY_REGEN], ["首座塔额外恢复", "+%s 点/秒" % RULES.ENERGY_TOWER_BONUSES[0]], ["自然产兵", "不产兵"]]}),
			step("一技能：征召守城", "前哨兵力不足。把一技能拖到前哨，立即补兵。\n敌军将在施法后进攻。", "把征召军令拖到前哨", "cast_building", "skill:0", {"beat": "recruit_defense", "skill": 0, "target": 2, "watch_goal": "观察征召补兵，守住前哨"}),
			step("守住了，立刻反击", "援军已经补齐。\n从前哨拖向敌方据点，派兵反击。", "从前哨向敌方据点派兵", "dispatch", "buildings", {"beat": "counterattack", "source": 2, "target": 3}),
			step("二技能：加速进攻", "把二技能拖到己方队伍中央，加快推进。\n这次先削弱守军，敌方据点还会反击。", "用疾行战鼓加速进攻部队", "cast_ground", "skill:1", {"beat": "haste_attack", "skill": 1, "army": 0, "watch_goal": "观察加速进攻，削弱敌方驻军"}),
			step("三技能：挡住反扑", "敌军反扑了！\n把三技能拖到前哨，用防护罩减少损失。", "给前哨施放防护罩", "cast_building", "skill:2", {"beat": "shield_defense", "skill": 2, "target": 2, "watch_goal": "观察护盾抵挡敌军，守住前哨"}),
			step("四技能：截断大军", "更多敌军正在靠近。\n把四技能拖到敌军中央，烧毁这支部队。", "用天降冲击清除敌军，守住前哨", "fire_hit", "skill:3", {"beat": "fire_defense", "skill": 3, "army": 1, "watch_goal": "观察火焰清除敌军"})]
		"house": return [
			step("住宅产兵", "1 级住宅产兵 %s 人/秒，驻扎容量 %d 人。\n达到容量只停自然产兵，增援和征召人数不限。" % [BUILDING.HOUSE_PRODUCTION_RATES[0], BUILDING.HOUSE_PRODUCTION_LIMITS[0]], "观察住宅驻军", "read", "building:0", {"labels": ["population"]}),
			step("点击升级", "选中己方住宅，点击向上箭头升级到 2 级。\n消耗 %d 人，%d 秒完成；施工仍按原等级产兵和防守。" % [BUILDING.HOUSE_UPGRADE_COSTS[0], BUILDING.upgrade_duration(0, 1)], "点击升级，等待住宅升到 2 级", "upgrade", "upgrade", {"target": 0}),
			step("2 级住宅", "产兵 %s 人/秒，容量 %d，防御 +%d%%。\n改建消耗驻军，数量见图标下方。" % [BUILDING.HOUSE_PRODUCTION_RATES[1], BUILDING.HOUSE_PRODUCTION_LIMITS[1], roundi(COMBAT.house_defense_bonus(2) * 100.0)], "认识升级结果与改建按钮", "read", "selection")]
		"tower": return [
			step("炮塔与射程", "虚线圈是射程，1 级炮塔每 %s 秒射击 1 名敌兵。\n防御力 +%d%%；不产兵，需要住宅增援。" % [COMBAT.tower_attack_interval(1), roundi(COMBAT.tower_defense_bonus(1) * 100.0)], "找到炮塔射程圈", "read", "building:1", {"labels": ["kind", "range"]}),
			step("增援炮塔", "从己方住宅拖到己方炮塔，送入援军。\n随后观察炮塔自动击退敌军。", "从住宅拖到己方炮塔", "reinforce_tower", "buildings", {"source": 0, "target": 1, "watch_goal": "观察增援抵达、炮塔击退敌军"}),
			step("防守完成", "援军已抵达，炮塔击退了敌军。", "确认炮塔防守结果", "read", "building:1"),
			step("守住路口", "在敌军必经之路布置炮塔，并用住宅补充守军。", "已完成炮塔防守", "read", "building:1")]
		"forge": return [
			step("铁匠铺加成", "1 座铁匠铺：攻击力 +%d%%、防御力 +%d%%。\n无移速加成，不产兵，需要住宅增援。" % [roundi(COMBAT.forge_attack_bonus(1) * 100.0), roundi(COMBAT.forge_defense_bonus(1) * 100.0)], "认识铁匠铺", "read", "building:1", {"labels": ["kind"]}),
			step("占领铁匠铺", "从住宅拖到中立铁匠铺，派兵占领。", "占领中立铁匠铺", "capture", "buildings", {"source": 0, "target": 1}),
			step("全军攻防提高", "持有铁匠铺，加成自动生效；失守后加成消失。", "已获得铁匠铺攻防加成", "read", "building:1")]
		"energy": return [
			step("能量塔与技力", "技能下方的细条是技力，施法会消耗它。\n能量塔加快技力恢复，不产兵；多塔收益递减。", "找到能量塔与技力条", "read", "energy"),
			step("占领能量塔", "从住宅拖到中立能量塔，派兵占领。", "占领中立能量塔", "capture", "buildings", {"source": 0, "target": 1}),
			step("观察技力恢复", "看技能下方的技力条，等待恢复 5 点。\n技力满后停止增长。", "等待技力恢复 5 点", "energy_watch", "energy_meter"),
			step("四种建筑", "住宅产兵，炮塔守路。\n铁匠铺提高攻防，能量塔加快技力恢复。", "已认识四种建筑", "read", "building:1")]
		"morale": return [
			step("士气星星", "兵力条下的星星是士气，影响全军攻防和移速。\n占领据点可获得士气，500 点亮起第一颗星。", "找到己方士气星星", "read", "morale"),
			step("点亮第一颗星", "派兵占领空置的中立铁匠铺。\n占领后，看顶部己方的第一颗星亮起。", "占领铁匠铺，升到一星士气", "capture", "buildings", {"source": 0, "target": 1}),
			step("一星加成", "每颗完整星：攻击力 +5%%、防御力 +%d%%、移速 +10%%。\n最多 5 星；进攻伤亡、失守或久无战果会降低士气。" % roundi(WarMorale.DEFENSE_PER_STAR * 100.0), "确认一星士气加成", "read", "morale")]
		"recruit": return [
			step("征召军令", "这座住宅已有 30 人，超过 %d 人驻扎容量，已停产。\n征召仍可补充士兵，驻军容纳人数不限。" % BUILDING.HOUSE_PRODUCTION_LIMITS[0], "认识征召军令的用途", "read", "building:0", {"labels": ["population"]}),
			step("拖动一技能", "把第一个技能拖到己方住宅上，松开施放。\n看完 %d 秒征召；右键可取消瞄准。" % RULES.DURATIONS[0], "将征召军令拖到己方住宅", "cast_building", "skill:0", {"skill": 0, "target": 0, "watch_goal": "观察征召结束、驻军增加"}),
			step("征召完成", "完整征召增加 %d 人，超过 %d 人驻扎容量也可接收。" % [int(RULES.RECRUIT_RATE * RULES.DURATIONS[0]), BUILDING.HOUSE_PRODUCTION_LIMITS[0]], "确认征召后的驻军", "read", "building:0"),
			step("补兵后扩张", "从住宅拖到中立据点，派出一半驻军进攻。", "派兵占领前方据点", "capture", "buildings", {"source": 0, "target": 1})]
		"drum": return [
			step("先派出援军", "从住宅拖到前方己方据点，派出援军。\n疾行战鼓可加速路上的己方部队。", "从住宅向前方据点派兵", "dispatch", "buildings", {"source": 0, "target": 1}),
			step("拖动二技能", "把第二个技能拖到金色队伍中央。\n己军移速 +%d%%，离圈后延续 %d 秒。" % [roundi((RULES.HASTE_MULTIPLIER - 1.0) * 100.0), RULES.HASTE_LINGER], "将战鼓放在己方队伍中央", "cast_ground", "skill:1", {"skill": 1, "army": 0, "watch_goal": "观察加速圈消散、援军全部抵达"}),
			step("援军到达", "加速圈已消散，援军全部进入前方据点。", "确认增援后的驻军", "read", "building:1")]
		"shield": return [
			step("防护罩", "建筑防御力 +%d%%，持续 %d 秒。\n本课在施法成功后开始敌军进攻。" % [roundi(RULES.SHIELD_DEFENSE * 100.0), RULES.DURATIONS[2]], "认识防护罩的用途", "read", "building:1"),
			step("拖动三技能", "把第三个技能拖到金色前哨，高亮后松开。\n观察前哨带盾迎敌，直到护盾消失。", "把防护罩拖到己方前哨", "cast_building", "skill:2", {"skill": 2, "target": 1, "watch_goal": "观察护盾消失，守住前哨"}),
			step("前哨守住了", "护盾已消失，前哨仍有守军。\n护盾减伤但不无敌，适合临近交战时施放。", "确认护盾防守结果", "read", "building:1")]
		"fire": return [
			step("天降冲击", "小范围火焰适合攻击密集敌军。\n接触的敌我行军士兵都会死亡，注意避开己军。", "瞄准密集敌军，避开己军", "read", "army:1"),
			step("拖动四技能", "把第四个技能拖到青绿色敌军中央，松开施放。\n观察火焰展开、消散；右键可取消瞄准。", "用天降冲击消灭至少 3 名敌军", "fire_hit", "skill:3", {"skill": 3, "army": 1, "watch_goal": "消灭至少 3 名敌军，观察火焰消散"}),
			step("四个技能", "征召补兵，战鼓加速，护盾守点，冲击清敌。", "已完成松鼠的四项技能练习", "read", "skill_row")]
	return []
