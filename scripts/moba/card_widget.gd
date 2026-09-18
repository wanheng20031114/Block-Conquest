extends Control
## Native Control dragging owns the preview and cancellation lifecycle.
var interface: Control
var slot: int = -1
var card_uid: int = 0
var definition: MobaCardDefinition
var _tween: Tween

func _ready() -> void:
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))

func bind(value: Control, index: int) -> void:
	interface = value
	slot = index

func present(entry: Dictionary, portrait: Texture2D, affordable: bool) -> void:
	var replaced: bool = card_uid != entry.uid
	card_uid = entry.uid
	definition = entry.card
	%Refill.visible = definition == null
	for child: CanvasItem in [%Title, %Portrait, %Category, %Count, %Cost, %Key, %Accent]: child.visible = definition != null
	if definition == null:
		%Refill.text = "补充中\n%.1f 秒" % maxf(0, entry.remaining)
		tooltip_text = "打出卡牌后，随机补充一张军队牌。"
	else:
		%Title.text = definition.title
		%Portrait.texture = portrait
		%Accent.color = definition.color
		%Category.text = definition.category
		%Count.text = "× %d" % definition.units.size()
		%Cost.text = str(definition.cost)
		%Cost.modulate = Color.WHITE if affordable else Color("d96b74")
		%Key.text = str(slot + 1) if slot >= 0 else ""
		%Portrait.modulate = Color.WHITE if affordable else Color(.65, .7, .72, 1)
		tooltip_text = "%s\n%s\n花费 %d 金币 · 从大本营派出\n双击 / 拖向战场 / 数字键 %d" % [definition.title, definition.description, definition.cost, slot + 1]
	if replaced and interface != null:
		if _tween: _tween.kill()
		%Visual.position.y = 12
		%Visual.modulate.a = .3
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(%Visual, "position:y", 0.0, .2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.tween_property(%Visual, "modulate:a", 1.0, .2)

func _hover(active: bool) -> void:
	if interface == null or definition == null or get_viewport().gui_is_dragging(): return
	if _tween: _tween.kill()
	z_index = 2 if active else 0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(%Visual, "position:y", -15.0 if active else 0.0, .14)
	_tween.tween_property(%Visual, "scale", Vector2.ONE * (1.04 if active else 1.0), .14)

func _gui_input(event: InputEvent) -> void:
	if interface == null or definition == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		interface.game.play_card(0, slot, card_uid)
		accept_event()

func _get_drag_data(_at: Vector2) -> Variant:
	if interface == null or definition == null: return null
	var error: String = interface.game.card_error(0, slot, card_uid)
	if not error.is_empty():
		interface.toast(error)
		return null
	var preview: Control = load("res://scenes/moba/card_drag_preview.tscn").instantiate()
	preview.theme = interface.theme
	preview.z_index = 100
	set_drag_preview(preview)
	preview.get_node("Card").present({"uid": card_uid, "card": definition}, %Portrait.texture, true)
	preview.scale = interface.get_node("Layout").scale
	if _tween: _tween.kill()
	%Visual.modulate.a = .4
	interface.drag_started()
	return {"kind": "moba_army_card", "slot": slot, "uid": card_uid}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and interface != null:
		interface.drag_finished()
		%Visual.modulate.a = 1.0
		_hover(false)
