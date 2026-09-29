extends Control
## Six authored roster slots; only implemented commanders can enter a match.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const PLAYABLE := {0: &"squirrel", 1: &"rabbit", 2: &"bear", 3: &"pig", 4: &"fox", 5: &"frog"}
@onready var session: Node = get_node("/root/Session")

func _ready() -> void:
	get_tree().auto_accept_quit = true
	for index: int in PLAYABLE:
		get_node("%%Animal%d" % index).pressed.connect(_select.bind(index))
	%Next.pressed.connect(_next)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	_select(PLAYABLE.find_key(session.block_war_commander), false)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)

func _select(index: int, animate: bool = true) -> void:
	if not PLAYABLE.has(index):
		return
	var commander: StringName = PLAYABLE[index]
	var changed: bool = session.block_war_commander != commander
	session.block_war_commander = commander
	for i: int in PLAYABLE:
		get_node("%%Animal%d" % i).set_pressed_no_signal(i == index)
	%Portrait.texture = RULES.PORTRAITS[commander]
	%AnimalName.text = RULES.name_for(commander)
	%Next.text = "就选%s   →" % RULES.name_for(commander)
	%Personality.text = {0: "稳稳扎营，也能一鼓作气。", 1: "跑得轻快，打个出其不意。", 2: "修好小屋，举盾守住大家。", 3: "整整队，下一波就起飞。", 4: "借一颗星，让对面乱了阵脚。", 5: "呼一口雾，藏好下一步。"}[index]
	%Role.text = {0: "增援 · 加速 · 守护 · 范围火攻", 1: "冲刺 · 停工 · 召回 · 兔洞突袭", 2: "赶工 · 牵制 · 互保 · 无敌守护", 3: "冲锋 · 飞行 · 密集出兵 · 重击", 4: "投弹 · 窃星 · 招降 · 恐慌", 5: "弱化 · 浮力 · 隐身 · 致命打击"}[index]
	var summaries := PackedStringArray([
		"每秒增援 %d 人，持续 %d 秒。" % [RULES.RECRUIT_RATE, RULES.DURATIONS[0]],
		"区域内自己的部队提速 %d%%，持续 %d 秒。" % [roundi((RULES.HASTE_MULTIPLIER - 1.0) * 100), RULES.DURATIONS[1]],
		"建筑守备 +%d%%，持续 %d 秒。" % [RULES.SHIELD_DEFENSE * 100, RULES.DURATIONS[2]],
		"瞬间点燃区域，火焰对双方士兵都致命。",
	] if index == 0 else [
		"选中部队移速 +%d%%、攻击 +%d%%，持续 %d 秒。" % [roundi((RULES.RABBIT_RUSH_MULTIPLIER - 1.0) * 100), RULES.RABBIT_RUSH_ATTACK_BONUS * 100, RULES.RABBIT_DURATIONS[0]],
		"让敌方建筑停止运作 %d 秒。" % RULES.DISABLE_DURATION,
		"让区域内双方部队各自返回出发建筑。",
		"建筑待命 %d 秒，下次派兵经兔洞突袭。" % RULES.BURROW_READY_DURATION,
	])
	if commander == RULES.BEAR:
		summaries = PackedStringArray(["施工立即完成，返还 50% 消耗人口。", "区域内敌军减速 60%，持续 4 秒。", "连接附近己方建筑，分担一半伤害，持续 8 秒。", "建筑无敌 5 秒，法术球优先攻击远处敌兵。"])
	elif commander == RULES.FROG:
		summaries = PackedStringArray(["薄雾遮挡炮塔，敌军虚弱 -20% 至入城。", "双方士兵滞空 3 秒，停步并避开炮塔。", "己军隐身至入城，避开炮塔的攻击。", "削减当前驻军 80%，建筑降至 1 级。"])
	elif commander == RULES.FOX:
		summaries = PackedStringArray(["投下炸弹，削减 50% 驻军，最多 30 人。", "通过敌方建筑，偷取所属英雄最多 1 星士气。", "招降小范围内的敌军，保持阵型和行军路线。", "80% 驻军逃往较近的同阵营建筑，距离不限。"])
	elif commander == &"pig":
		summaries = PackedStringArray(["下一次出兵移速 +20%、攻击 +10%。", "下一次出兵直线飞行，最多派出 30 人。", "下一次出兵更加密集，最多派出 60 人。", "小范围砸落：行军全灭，建筑驻军减半。"])
	for i: int in 4:
		get_node("%%SkillIcon%d" % i).texture = RULES.icons_for(commander)[i]
		get_node("%%SkillName%d" % i).text = RULES.names_for(commander)[i]
		get_node("%%SkillDetail%d" % i).text = summaries[i]
		get_node("%%SkillCost%d" % i).text = "%d 技力\n%d 秒冷却" % [RULES.costs_for(commander)[i], RULES.cooldowns_for(commander)[i]]
		get_node("%%SkillIcon%d" % i).get_parent().get_parent().tooltip_text = RULES.description(i, commander)
	if animate and changed:
		_animate_selection()

func _animate_selection() -> void:
	UIMotion.reveal_menu(%Portrait, Vector2(-14, 8))
	UIMotion.reveal_menu(%AnimalName, Vector2(0, 8), 0.035)
	UIMotion.reveal_menu(%Personality, Vector2.ZERO, 0.045)
	UIMotion.reveal_menu(%Role, Vector2.ZERO, 0.065)
	for index: int in 4:
		UIMotion.reveal_menu(get_node("Margin/Column/Content/Details/Skill%d" % index), Vector2.ZERO, 0.08 + index * 0.035)

func _next() -> void:
	if session.transition.busy or session.settings.is_open():
		return
	if session.change_scene("res://scenes/block_war/map_select.tscn") != OK:
		%Hint.text = "战场选择暂时无法载入，请重试。"

func _back() -> void:
	if not session.transition.busy:
		session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if session.settings.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
