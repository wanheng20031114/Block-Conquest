extends Control
## Pure presentation: the run/session owns choices, costs, discarding and saving.
signal unit_chosen(uid: int, kind: String)
signal batches_chosen(uid: int, batches: int)
signal back_requested
signal discard_requested(uid: int)

const CARD_EDGE: float = 0.055
const OPEN_STAGGER: float = 0.065
const ROLES: Dictionary = {
	"swordsman":"可靠的近战步兵，适合守住阵线。",
	"shield_guard":"厚重盾牌抵挡远程火力，为同伴争取空间。",
	"spearman":"长矛兵列阵迎敌，擅长对抗骑兵。",
	"archer":"在后方持续射击，需要近战部队保护。",
	"knight":"披甲骑兵突破阵线，适合集中突击。",
	"light_cavalry":"轻骑快速穿行战场，追击落单敌军。",
	"catapult":"投掷石弹攻击密集敌人，也能摧毁建筑。",
	"cannon":"远程火炮提供重击，注意保持射击距离。",
	"triple_cannon":"多管火炮连续开火，压制前方敌军。",
	"heavy_cannon":"四轮重炮远程轰击，需要前排保护。",
	"war_elephant":"庞大的战象冲入敌阵，撑起进攻正面。",
	"engineer":"跟随军队支援攻城器，维持器械作战能力。",
	"priest":"治疗受伤同伴，让军队守得更久。",
}

@onready var cards: Array[Button] = [
	$Center/Content/Cards/Slot0/Card,
	$Center/Content/Cards/Slot1/Card,
	$Center/Content/Cards/Slot2/Card,
]
@onready var heading: Label = $Center/Content/Header/Top/Heading
@onready var subheading: Label = $Center/Content/Header/Subheading
@onready var bread_value: Label = $Center/Content/Header/Top/Wallet/Value
@onready var back_button: Button = $Center/Content/Footer/Actions/Back
@onready var discard_button: Button = $Center/Content/Footer/Actions/Discard
@onready var status: Label = $Center/Content/Footer/Status
@onready var portraits: Node = $ModelPreviews

var _ticket: Dictionary = {}
var _bread: int = 0
var _selected_kind: String = ""
var _submitted: bool = false
var _animation: Tween
var _hover_tweens: Array[Tween] = []
var _serial: int = 0
var _rendered_once: bool = false

func _ready() -> void:
	hide()
	_hover_tweens.resize(3)
	for index: int in 3:
		cards[index].pressed.connect(_on_card_pressed.bind(index))
		cards[index].gui_input.connect(_on_card_input.bind(index))
		cards[index].mouse_entered.connect(_on_hover.bind(index, true))
		cards[index].mouse_exited.connect(_on_hover.bind(index, false))
		cards[index].focus_entered.connect(_on_hover.bind(index, true))
		cards[index].focus_exited.connect(_on_hover.bind(index, false))
	back_button.pressed.connect(_on_back)
	discard_button.pressed.connect(_on_discard)
	visibility_changed.connect(_on_visibility_changed)
	UIMotion.bind_buttons($Center/Content/Footer)

func render_ticket(ticket: Dictionary, bread: int, _state: RogueRunState, selected_kind: String = "") -> void:
	assert(ticket.has("uid") and ticket.has("candidates") and ticket.candidates.size() == 3)
	assert(selected_kind.is_empty() or ticket.candidates.has(selected_kind))
	if visible and not _submitted and _ticket == ticket and _bread == bread and _selected_kind == selected_kind:
		return
	var changed_phase: bool = _rendered_once and visible and int(_ticket.uid) == int(ticket.uid) and _selected_kind != selected_kind
	_finish_animation()
	_ticket = ticket.duplicate(true)
	_bread = bread
	_selected_kind = selected_kind
	_submitted = false
	_serial += 1
	_rendered_once = true
	show()
	if changed_phase:
		_flip_to_current(_serial)
	else:
		_populate()
		_play_entrance.call_deferred(_serial)

func _populate() -> void:
	bread_value.text = str(_bread)
	heading.text = "选择同行的部队" if _selected_kind.is_empty() else "带上多少同伴"
	subheading.text = "选择一支部队，再决定招募批次。" if _selected_kind.is_empty() else "选择 1—3 批，确认后使用当前招募券。"
	back_button.visible = not _selected_kind.is_empty()
	back_button.disabled = false
	discard_button.disabled = false
	status.text = "新部队加入待命区，可在编队中安排出战。"
	for index: int in 3:
		var kind: String = str(_ticket.candidates[index]) if _selected_kind.is_empty() else _selected_kind
		var definition: UnitDefinition = BalanceCatalog.unit(kind)
		var terms: Dictionary = RogueCatalog.RECRUIT[kind]
		var batches: int = 1 if _selected_kind.is_empty() else index + 1
		var cost: int = int(terms.bread) * batches
		var count: int = int(terms.count) * batches
		var card: Button = cards[index]
		var body: VBoxContainer = card.get_node("Margin/Body")
		body.get_node("Kicker").text = "部队招募" if _selected_kind.is_empty() else "招募数量"
		body.get_node("Portrait").texture = portraits.portrait(kind)
		body.get_node("Name").text = definition.name if _selected_kind.is_empty() else "%d 批" % batches
		body.get_node("Description").text = str(ROLES[kind]) if _selected_kind.is_empty() else "共 %d 名%s" % [count, definition.name]
		body.get_node("Quantity").text = "每批 %d 名" % int(terms.count)
		body.get_node("Cost/Value").text = "%d 面包 / 批" % cost if _selected_kind.is_empty() else "%d 面包" % cost
		var affordable: bool = _bread >= cost
		card.disabled = not affordable
		body.get_node("Action/Text").text = ("选择这支部队" if _selected_kind.is_empty() else "确认招募") if affordable else "还差 %d 面包" % (cost - _bread)
		body.get_node("Portrait").self_modulate = Color.WHITE if affordable else Color(.72,.75,.73,1)
		body.get_node("Action").self_modulate = Color.WHITE if affordable else Color(.85,.89,.86,1)
		body.get_node("Kicker").modulate = Color(1,1,1,1) if affordable else Color(.74,.77,.75,1)
		card.tooltip_text = definition.description
		card.set_meta("kind", kind)
		card.set_meta("batches", batches)
		card.set_meta("cost", cost)
		card.set_meta("count", count)
		body.show()
	if _bread < _cheapest_cost():
		status.text = "面包不足以招募当前候选。可以弃置这张招募券。"

func _cheapest_cost() -> int:
	var cheapest: int = 2147483647
	for kind: String in _ticket.candidates:
		cheapest = mini(cheapest, int(RogueCatalog.RECRUIT[kind].bread))
	return cheapest

func _play_entrance(serial: int) -> void:
	if serial != _serial or not visible or _submitted:
		return
	_animation = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	for index: int in 3:
		var card: Button = cards[index]
		card.pivot_offset = card.size * .5
		card.position.y = 12
		card.modulate.a = 0
		card.scale = Vector2(.97,.97)
		var delay: float = index * OPEN_STAGGER
		_animation.tween_property(card,"position:y",0.0,.24).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_animation.tween_property(card,"modulate:a",1.0,.18).set_delay(delay)
		_animation.tween_property(card,"scale",Vector2.ONE,.24).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.finished.connect(_on_animation_finished.bind(serial))

func _flip_to_current(serial: int) -> void:
	_populate()
	for card: Button in cards:
		card.get_node("Margin/Body").hide()
	_animation = create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	for index: int in 3:
		_stop_hover(index)
		cards[index].pivot_offset = cards[index].size * .5
		_animation.tween_property(cards[index],"scale:x",CARD_EDGE,.12).set_delay(index*.035).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_animation.chain().tween_callback(func():
		for card: Button in cards:
			card.get_node("Margin/Body").show()
	)
	for index: int in 3:
		_animation.parallel().tween_property(cards[index],"scale:x",1.0,.19).set_delay(index*.035).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_animation.finished.connect(_on_animation_finished.bind(serial))

func _on_animation_finished(serial: int) -> void:
	if serial != _serial:
		return
	_animation = null
	for index: int in 3:
		cards[index].scale = Vector2.ONE
		cards[index].modulate = Color.WHITE
		cards[index].position.y = 0

func _finish_animation() -> void:
	if _animation != null:
		_animation.kill()
		_animation = null
	for index: int in 3:
		_stop_hover(index)
		cards[index].scale = Vector2.ONE
		cards[index].modulate = Color.WHITE
		cards[index].position.y = 0
	if not _ticket.is_empty():
		_populate()

func _on_card_input(event: InputEvent, index: int) -> void:
	# The second press of a native double-click belongs to the previous choice.
	# Accept it before BaseButton processes it so a phase flip cannot buy a batch.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		cards[index].accept_event()

func _on_card_pressed(index: int) -> void:
	if _submitted or not visible:
		return
	# Fast input finishes the reveal AND performs the requested choice on this click.
	_finish_animation()
	if cards[index].disabled:
		return
	_submitted = true
	_lock_actions()
	if _selected_kind.is_empty():
		unit_chosen.emit(int(_ticket.uid), str(cards[index].get_meta("kind")))
	else:
		batches_chosen.emit(int(_ticket.uid), index + 1)

func _on_back() -> void:
	if _submitted or _selected_kind.is_empty():
		return
	_finish_animation()
	_submitted = true
	_lock_actions()
	back_requested.emit()

func _on_discard() -> void:
	if _submitted:
		return
	_finish_animation()
	_submitted = true
	_lock_actions()
	discard_requested.emit(int(_ticket.uid))

func _lock_actions() -> void:
	for card: Button in cards:
		card.disabled = true
	back_button.disabled = true
	discard_button.disabled = true
	portraits.set_animated("")

func _on_hover(index: int, entered: bool) -> void:
	if not visible or _submitted or cards[index].disabled or _animation != null:
		return
	_stop_hover(index)
	_hover_tweens[index] = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true)
	_hover_tweens[index].tween_property(cards[index],"position:y",-4.0 if entered else 0.0,.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	portraits.set_animated(str(cards[index].get_meta("kind")) if entered else "")

func _stop_hover(index: int) -> void:
	if _hover_tweens[index] != null:
		_hover_tweens[index].kill()
		_hover_tweens[index] = null

func _on_visibility_changed() -> void:
	if not visible and is_node_ready():
		_serial += 1
		_finish_animation()
		portraits.set_animated("")

func _exit_tree() -> void:
	if _animation != null:
		_animation.kill()
	for animation: Tween in _hover_tweens:
		if animation != null:
			animation.kill()
