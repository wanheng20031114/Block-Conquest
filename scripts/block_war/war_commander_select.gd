extends Control
## Six authored roster slots; only implemented commanders can enter a match.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const PLAYABLE: Array[StringName] = [&"squirrel", &"rabbit"]
var _portrait_tween: Tween
@onready var session: Node = get_node("/root/Session")

func _ready() -> void:
	get_tree().auto_accept_quit = true
	for index: int in 2:
		get_node("%%Animal%d" % index).pressed.connect(_select.bind(index))
	%Next.pressed.connect(_next)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	_select(PLAYABLE.find(session.block_war_commander), false)
	UIMotion.bind_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)

func _select(index: int, animate: bool = true) -> void:
	if index < 0 or index >= PLAYABLE.size():
		return
	var commander := PLAYABLE[index]
	session.block_war_commander = commander
	for i: int in 2:
		get_node("%%Animal%d" % i).set_pressed_no_signal(i == index)
	%Portrait.texture = RULES.PORTRAITS[commander]
	%AnimalName.text = RULES.name_for(commander)
	%Next.text = "就选%s   →" % RULES.name_for(commander)
	%Personality.text = "稳稳扎营，也能一鼓作气。" if index == 0 else "跑得轻快，打个出其不意。"
	%Role.text = "增援 · 加速 · 守护 · 范围火攻" if index == 0 else "冲刺 · 停工 · 召回 · 兔洞突袭"
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
	for i: int in 4:
		get_node("%%SkillIcon%d" % i).texture = RULES.icons_for(commander)[i]
		get_node("%%SkillName%d" % i).text = RULES.names_for(commander)[i]
		get_node("%%SkillDetail%d" % i).text = summaries[i]
		get_node("%%SkillCost%d" % i).text = "%d 技力\n%d 秒冷却" % [RULES.costs_for(commander)[i], RULES.cooldowns_for(commander)[i]]
		get_node("%%SkillIcon%d" % i).get_parent().get_parent().tooltip_text = RULES.description(i, commander)
	if animate:
		if _portrait_tween != null and _portrait_tween.is_valid():
			_portrait_tween.kill()
		%Portrait.pivot_offset = %Portrait.size * Vector2(0.5, 0.85)
		%Portrait.scale = Vector2(0.96, 0.96)
		_portrait_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_portrait_tween.tween_property(%Portrait, "scale", Vector2.ONE, 0.18)

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
