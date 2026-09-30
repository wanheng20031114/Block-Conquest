extends RefCounted
## Authored lessons: one concept, one real practice, then a clear result.
const BUILDING := preload("res://scripts/block_war/war_building.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const COMBAT := preload("res://scripts/block_war/war_combat_rules.gd")
const IDS: Array[String] = ["basics", "interface", "house", "tower", "forge", "energy", "morale", "recruit", "drum", "shield", "fire"]
const TITLES: Array[String] = ["第一道军令", "读懂战场", "住宅：壮大军团", "炮塔：守住路口", "铁匠铺：武装全军", "能量塔：积攒技力", "士气：越战越勇", "征召军令：补足兵力", "疾行战鼓：抢先增援", "防护罩：守住前哨", "天降冲击：截断敌军"]
const SUMMARIES: Array[String] = ["拖动派兵，占领据点。", "认识界面，调整出兵比例与视野。", "了解产兵，升级住宅。", "增援炮塔，守住路口。", "占领铁匠铺，提高全军攻防。", "占领能量塔，加快技力恢复。", "占领据点，点亮第一颗士气星星。", "突破住宅产兵上限，补兵扩张。", "在援军路线上放置加速区域。", "给前哨加盾，减少守军损失。", "瞄准密集敌军，避开己军。"]

static func title(id: String) -> String:
	return TITLES[IDS.find(id)]

static func summary(id: String) -> String:
	return SUMMARIES[IDS.find(id)]

static func ids() -> Array[String]:
	return IDS.duplicate()

static func minutes(id: String) -> String:
	return "约 2 分钟" if id in ["interface", "house", "recruit"] else "约 1 分钟"

static func step(heading: String, body: String, goal: String, action: String, focus: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"title": heading, "body": body, "goal": goal, "action": action, "focus": focus}
	result.merge(extra)
	return result

static func steps(id: String) -> Array[Dictionary]:
	match id:
		"basics": return [
			step("你的住宅", "金色旗帜表示己方，住宅会自动产兵。\n讲解时战场暂停，操作示范会继续播放。", "认识己方住宅", "read", "building:0"),
			step("己方与中立", "金旗是己方，灰旗是中立；花瓣里的数字是驻军。\n士兵离开时数字逐批减少，敌方驻军不公开。", "区分己方与中立建筑", "read", "buildings"),
			step("拖动派兵", "按住己方住宅，左键拖到中立住宅后松开。\n默认派出 50% 驻军；拖错时按右键取消。", "拖动己方住宅，攻占中立住宅", "capture", "buildings", {"source": 0, "target": 1}),
			step("占领成功", "旗帜变金，剩余士兵成为驻军。\n这座住宅也会为你产兵。", "已占领第一座据点", "read", "building:1")]
		"interface": return [
			step("顶部战况", "数字是总兵力，色条是兵力占比，下方是对局时间。\n总兵力包含建筑驻军和行军部队。", "认识兵力条与计时", "read", "top"),
			step("士气星星", "兵力条下的星星是士气，能提高攻防和移速。\n左侧是己方士气，右侧是敌方士气。", "找到士气星星", "read", "morale"),
			step("技能与技力", "四个图标是技能，下方细条是共用的技力。\n施法消耗技力，每个技能有独立冷却。", "区分技能图标与技力条", "read", "skills"),
			step("出兵比例", "点击左侧 25%，每次只派出四分之一可用驻军。\n100% 会派出全部可用驻军。", "点击左侧 25%", "ratio", "ratios"),
			step("滚轮缩放", "在地图空白处滚动滚轮，拉近或拉远视野。\n拖动建筑时，滚轮会改出兵比例。", "在地图空白处滚动滚轮", "zoom", "world"),
			step("移动视野", "在地图空白处按住中键拖动，再松开。\n也可用方向键移动；视野不会越出地图。", "中键拖动地图，或按方向键", "pan", "world")]
		"house": return [
			step("住宅产兵", "1 级住宅每秒产 1 人，达到 30 人停产。\n增援和征召可超过此上限。", "观察住宅驻军", "read", "building:0"),
			step("点击升级", "选中己方住宅，点击向上箭头升级到 2 级。\n升级消耗驻军，%d 秒完成；施工期间仍会产兵。" % BUILDING.upgrade_duration(0, 1), "点击升级，等待住宅升到 2 级", "upgrade", "upgrade", {"target": 0}),
			step("2 级住宅", "现在每秒产 1.25 人，达到 50 人停产。\n旁边的建筑图标用于改建，也会消耗驻军。", "认识升级结果与改建按钮", "read", "selection")]
		"tower": return [
			step("炮塔与射程", "虚线圈是射程，炮塔会自动射击圈内敌军。\n炮塔不产兵，需要住宅增援。", "找到炮塔射程圈", "read", "building:1"),
			step("增援炮塔", "从己方住宅拖到己方炮塔，送入援军。\n随后观察炮塔自动击退敌军。", "从住宅拖到己方炮塔", "reinforce_tower", "buildings", {"source": 0, "target": 1, "watch_goal": "观察增援抵达、炮塔击退敌军"}),
			step("防守完成", "援军已抵达，炮塔击退了敌军。", "确认炮塔防守结果", "read", "building:1"),
			step("守住路口", "在敌军必经之路布置炮塔，并用住宅补充守军。", "已完成炮塔防守", "read", "building:1")]
		"forge": return [
			step("铁匠铺加成", "1 座铁匠铺：攻击力 +%d%%、防御力 +%d%%。\n无移速加成，不产兵，需要住宅增援。" % [roundi(COMBAT.forge_attack_bonus(1) * 100.0), roundi(COMBAT.forge_defense_bonus(1) * 100.0)], "认识铁匠铺", "read", "building:1"),
			step("占领铁匠铺", "从住宅拖到中立铁匠铺，派兵占领。", "占领中立铁匠铺", "capture", "buildings", {"source": 0, "target": 1}),
			step("全军攻防提高", "持有铁匠铺，加成自动生效；失守后加成消失。", "已获得铁匠铺攻防加成", "read", "building:1")]
		"energy": return [
			step("能量塔与技力", "技能下方的细条是技力，施法会消耗它。\n能量塔加快技力恢复，不产兵；多塔收益递减。", "找到能量塔与技力条", "read", "energy"),
			step("占领能量塔", "从住宅拖到中立能量塔，派兵占领。", "占领中立能量塔", "capture", "buildings", {"source": 0, "target": 1}),
			step("观察技力恢复", "看技能下方的技力条，等待恢复 5 点。\n技力满后停止增长。", "等待技力恢复 5 点", "energy_watch", "skills"),
			step("四种建筑", "住宅产兵，炮塔守路。\n铁匠铺提高攻防，能量塔加快技力恢复。", "已认识四种建筑", "read", "building:1")]
		"morale": return [
			step("士气星星", "兵力条下的星星是士气，影响全军攻防和移速。\n占领据点可获得士气，500 点亮起第一颗星。", "找到己方士气星星", "read", "morale"),
			step("点亮第一颗星", "派兵占领空置的中立铁匠铺。\n占领后，看顶部己方的第一颗星亮起。", "占领铁匠铺，升到一星士气", "capture", "buildings", {"source": 0, "target": 1}),
			step("一星加成", "每颗完整星：攻击力 +5%%、防御力 +%d%%、移速 +10%%。\n最多 5 星；进攻伤亡、失守或久无战果会降低士气。" % roundi(WarMorale.DEFENSE_PER_STAR * 100.0), "确认一星士气加成", "read", "morale")]
		"recruit": return [
			step("征召军令", "这座住宅已有 30 人，停止自然产兵。\n征召军令能补充士兵，突破产兵上限。", "认识征召军令的用途", "read", "building:0"),
			step("拖动一技能", "把第一个技能拖到己方住宅上，松开施放。\n看完 %d 秒征召；右键可取消瞄准。" % RULES.DURATIONS[0], "将征召军令拖到己方住宅", "cast_building", "skill:0", {"skill": 0, "target": 0, "watch_goal": "观察征召结束、驻军增加"}),
			step("征召完成", "完整征召增加 %d 人，可突破住宅产兵上限。" % int(RULES.RECRUIT_RATE * RULES.DURATIONS[0]), "确认征召后的驻军", "read", "building:0"),
			step("补兵后扩张", "从住宅拖到中立据点，派出一半驻军进攻。", "派兵占领前方据点", "capture", "buildings", {"source": 0, "target": 1})]
		"drum": return [
			step("先派出援军", "从住宅拖到前方己方据点，派出援军。\n疾行战鼓可加速路上的己方部队。", "从住宅向前方据点派兵", "dispatch", "buildings", {"source": 0, "target": 1}),
			step("拖动二技能", "把第二个技能拖到金色队伍中央。\n圈内己军移速 +%d%%，离开后恢复；加速圈固定不动。" % roundi((RULES.HASTE_MULTIPLIER - 1.0) * 100.0), "将战鼓放在己方队伍中央", "cast_ground", "skill:1", {"skill": 1, "army": 0, "watch_goal": "观察加速圈消散、援军全部抵达"}),
			step("援军到达", "加速圈已消散，援军全部进入前方据点。", "确认增援后的驻军", "read", "building:1")]
		"shield": return [
			step("防护罩", "建筑防御力 +%d%%，持续 %d 秒。\n本课在施法成功后开始敌军进攻。" % [roundi(RULES.SHIELD_DEFENSE * 100.0), RULES.DURATIONS[2]], "认识防护罩的用途", "read", "building:1"),
			step("拖动三技能", "把第三个技能拖到金色前哨，高亮后松开。\n观察前哨带盾迎敌，直到护盾消失。", "把防护罩拖到己方前哨", "cast_building", "skill:2", {"skill": 2, "target": 1, "watch_goal": "观察护盾消失，守住前哨"}),
			step("前哨守住了", "护盾已消失，前哨仍有守军。\n护盾减伤但不无敌，适合临近交战时施放。", "确认护盾防守结果", "read", "building:1")]
		"fire": return [
			step("天降冲击", "小范围火焰适合攻击密集敌军。\n接触的敌我行军士兵都会死亡，注意避开己军。", "瞄准密集敌军，避开己军", "read", "army:1"),
			step("拖动四技能", "把第四个技能拖到青绿色敌军中央，松开施放。\n观察火焰展开、消散；右键可取消瞄准。", "用天降冲击消灭至少 3 名敌军", "fire_hit", "skill:3", {"skill": 3, "army": 1, "watch_goal": "消灭至少 3 名敌军，观察火焰消散"}),
			step("四个技能", "征召补兵，战鼓加速，护盾守点，冲击清敌。", "已完成松鼠的四项技能练习", "read", "skills")]
	return []
