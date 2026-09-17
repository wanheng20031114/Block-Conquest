extends Control
## Displays an immutable settlement snapshot; claiming belongs to Session.
signal claim_requested

@onready var heading: Label = $Center/Paper/Margin/Content/Heading
@onready var record: Label = $Center/Paper/Margin/Content/Record
@onready var growth: Label = $Center/Paper/Margin/Content/Growth
@onready var status: Label = $Center/Paper/Margin/Content/Status
@onready var claim: Button = $Center/Paper/Margin/Content/Claim
@onready var reward_tiles: Array[Control] = [
	$Center/Paper/Margin/Content/Rewards/Gold,
	$Center/Paper/Margin/Content/Rewards/Bread,
	$Center/Paper/Margin/Content/Rewards/Experience,
	$Center/Paper/Margin/Content/Rewards/Tickets,
]
const REWARD_KEYS: Array[String] = ["gold","bread","xp","tickets"]
var _animation: Tween
var _submitted: bool = false
var _summary: Dictionary = {}
var _serial: int = 0

func _ready() -> void:
	hide()
	claim.pressed.connect(_on_claim)
	visibility_changed.connect(_on_visibility_changed)
	UIMotion.bind_buttons(claim)

func render_settlement(settlement: Dictionary, _state: RogueRunState) -> void:
	assert(settlement.has("rewards") and settlement.has("claimed"))
	if visible and not _submitted and _summary == settlement:
		return
	_finish_reveal()
	_summary = settlement.duplicate(true)
	_submitted = bool(settlement.claimed)
	_serial += 1
	heading.text = "前哨已肃清" if str(settlement.battle_kind) == "outpost" else "守住了营地"
	var description: String = "前哨站 · 紧急作战" if bool(settlement.emergency) else "前哨站 · 普通作战"
	if str(settlement.battle_kind) == "siege":
		description = "围剿 · 营地防守"
	var facts: Array[String] = []
	if settlement.has("duration"):
		var seconds: int = roundi(float(settlement.duration))
		facts.append("作战 %d 分 %02d 秒" % [floori(float(seconds) / 60.0), seconds % 60])
	if settlement.has("defeated"):
		facts.append("击败敌军 %d" % int(settlement.defeated))
	if settlement.has("casualties"):
		facts.append("本场战损 %d" % int(settlement.casualties))
	record.text = description + ("\n" + "  ·  ".join(facts) if not facts.is_empty() else "\n军队已完成作战目标，补给正在清点。")
	for index: int in 4:
		reward_tiles[index].get_node("Value").text = "+%d" % int(settlement.rewards[REWARD_KEYS[index]])
	var siege: bool = str(settlement.battle_kind) == "siege"
	$Center/Paper/Margin/Content/Rewards.visible = not siege
	$Center/Paper/Margin/Content/Recovery.visible = siege
	var maximum_ap: int = int(RogueCatalog.BALANCE.initial.max_ap)
	$Center/Paper/Margin/Content/Recovery/Copy/Action.text = "行动力恢复  %d / %d" % [maximum_ap, maximum_ap]
	var levels: int = int(settlement.get("levels", 0))
	growth.visible = levels > 0
	growth.text = "提升 %d 级  ·  额外面包 +%d  ·  人口上限 +%d" % [levels, int(settlement.get("bonus_bread", 0)), int(settlement.get("bonus_population", 0))]
	status.text = "奖励已领取" if _submitted else "确认领取后，继续处理本次获得的招募券与收藏品。"
	claim.text = "已领取" if _submitted else "领取奖励"
	if siege:
		status.text = "整备已完成" if _submitted else "确认结算后保存军团进度。当前版本仅开放第一层。"
		claim.text = "已完成整备" if _submitted else "完成整备"
	claim.disabled = _submitted
	show()
	_reveal.call_deferred(_serial)

func _reveal(serial: int) -> void:
	if serial != _serial or not visible or _submitted:
		return
	_animation = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	if str(_summary.battle_kind) == "siege":
		var recovery: Control = $Center/Paper/Margin/Content/Recovery
		recovery.modulate.a = 0
		_animation.tween_property(recovery,"modulate:a",1.0,.25)
		_animation.finished.connect(func(): _animation = null)
		return
	for index: int in 4:
		var tile: Control = reward_tiles[index]
		tile.pivot_offset = tile.size * .5
		tile.modulate.a = 0
		tile.scale = Vector2(.95,.95)
		_animation.tween_property(tile,"modulate:a",1.0,.21).set_delay(index*.085)
		_animation.tween_property(tile,"scale",Vector2.ONE,.25).set_delay(index*.085).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.finished.connect(func(): _animation = null)

func _finish_reveal() -> void:
	if _animation != null:
		_animation.kill()
		_animation = null
	for tile: Control in reward_tiles:
		tile.modulate = Color.WHITE
		tile.scale = Vector2.ONE
	$Center/Paper/Margin/Content/Recovery.modulate = Color.WHITE

func _on_claim() -> void:
	if _submitted or not visible:
		return
	_finish_reveal()
	_submitted = true
	claim.disabled = true
	claim.text = "已确认领取"
	status.text = "正在整备下一步行程。"
	if str(_summary.battle_kind) == "siege":
		claim.text = "正在完成整备"
		status.text = "正在保存军队与成长。"
	claim_requested.emit()

func _on_visibility_changed() -> void:
	if not visible and is_node_ready():
		_serial += 1
		_finish_reveal()

func _exit_tree() -> void:
	if _animation != null:
		_animation.kill()
