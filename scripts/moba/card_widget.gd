extends Control
## Card identity belongs to the hand. Motion never delays a purchase or a refill.
enum Phase { STEADY, DEALING, DISPATCHING, WAITING }
var interface: Control
var slot: int = -1
var card_uid: int = -1
var definition: MobaCardDefinition
var phase: Phase = Phase.STEADY
var _hovered := false
var _dragging := false
var _affordable := true
var _lift_tween: Tween
var _frame: StyleBoxFlat
var _art: StyleBoxFlat
var _accent: StyleBoxFlat
var _keycap: StyleBoxFlat

func _ready() -> void:
	_frame = %Visual.get_theme_stylebox("panel").duplicate()
	_art = %Art.get_theme_stylebox("panel").duplicate()
	_accent = %Accent.get_theme_stylebox("panel").duplicate()
	_keycap = %KeyBadge.get_theme_stylebox("panel").duplicate()
	%Visual.add_theme_stylebox_override("panel", _frame)
	%Art.add_theme_stylebox_override("panel", _art)
	%Accent.add_theme_stylebox_override("panel", _accent)
	%KeyBadge.add_theme_stylebox_override("panel", _keycap)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	%Motion.animation_finished.connect(_motion_finished)

func bind(value: Control, index: int) -> void:
	interface = value
	slot = index

func present(entry: Dictionary, portrait: Texture2D, affordable: bool) -> void:
	var changed: bool = card_uid != entry.uid
	var previous: MobaCardDefinition = definition
	card_uid = entry.uid
	definition = entry.card
	_affordable = affordable
	%Refill.visible = definition == null
	if definition == null:
		var seconds: float = maxf(0, entry.remaining)
		%RefillTime.text = "%.1f 秒" % seconds
		var duration: float = interface.game.DECK.refill_seconds if interface != null else 1.5
		%RefillProgress.value = (1.0 - seconds / duration) * 100.0
		tooltip_text = "补充援军中"
		if changed and previous != null:
			phase = Phase.DISPATCHING
			_reset_lift()
			%Motion.play("dispatch")
		elif phase != Phase.DISPATCHING:
			phase = Phase.WAITING
			%Visual.hide()
		return
	if changed:
		%Title.text = definition.title
		%Category.text = definition.category
		%Count.text = "×%d" % definition.units.size()
		%Cost.text = str(definition.cost)
		%Key.text = str(slot + 1) if slot >= 0 else ""
		%Portrait.texture = portrait
		_art.bg_color = definition.color.lerp(Color.WHITE, .89)
		_accent.bg_color = definition.color
		_keycap.bg_color = definition.color
		%Visual.show()
		if interface != null:
			phase = Phase.DEALING
			%Motion.play("enter")
		else:
			phase = Phase.STEADY
	%Cost.modulate = Color.WHITE if affordable else Color("c07369")
	%Portrait.modulate = Color.WHITE if affordable else Color(.77,.81,.83,1)
	_frame.border_color = definition.color if _hovered and affordable else Color("ccdce1")
	tooltip_text = "%s\n%s\n花费 %d 金币 · 从大本营派出\n双击 / 上拖 / 数字键 %d%s" % [definition.title, definition.description, definition.cost, slot + 1, "" if affordable else "\n金币不足"]

func _motion_finished(animation: StringName) -> void:
	if animation == &"dispatch" and definition == null:
		phase = Phase.WAITING
		%Visual.hide()
	elif animation == &"enter":
		phase = Phase.STEADY

func _reset_lift() -> void:
	if _lift_tween: _lift_tween.kill()
	%Lift.position = Vector2.ZERO
	%Lift.scale = Vector2.ONE
	%Lift.rotation = 0
	%Lift.modulate = Color.WHITE
	z_index = 0

func _hover(active: bool) -> void:
	_hovered = active
	if interface == null or definition == null or _dragging or get_viewport().gui_is_dragging(): return
	interface.card_hover(self, active)
	if _lift_tween: _lift_tween.kill()
	z_index = 4 if active else 0
	_frame.border_color = definition.color if active and _affordable else Color("ccdce1")
	_lift_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_property(%Lift, "position", Vector2(0,-17 if active else 0), .18)
	_lift_tween.tween_property(%Lift, "scale", Vector2.ONE * (1.035 if active else 1.0), .18)
	_lift_tween.tween_property(%Lift, "rotation", 0.0, .18)

func reject() -> void:
	if definition != null and phase == Phase.STEADY: %Motion.play("reject")

func _gui_input(event: InputEvent) -> void:
	if interface == null or definition == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		interface.game.play_card(0, slot, card_uid)
		accept_event()

func _get_drag_data(at: Vector2) -> Variant:
	if interface == null or definition == null: return null
	var error: String = interface.game.card_error(0, slot, card_uid)
	if not error.is_empty():
		interface.toast(error)
		reject()
		return null
	# Runtime loading avoids a cyclic preload: preview contains another ArmyCard.
	var preview: Control = load("res://scenes/moba/card_drag_preview.tscn").instantiate()
	preview.theme = interface.theme
	preview.z_index = 100
	set_drag_preview(preview)
	preview.get_node("Card").present({"uid":card_uid,"card":definition}, %Portrait.texture, true)
	preview.get_node("Card").get_node("%Key").text = str(slot + 1)
	preview.scale = get_global_transform().get_scale()
	preview.rotation = -.025
	_dragging = true
	_reset_lift()
	%Lift.modulate.a = .25
	interface.drag_started(get_global_transform() * at)
	return {"kind":"moba_army_card", "slot":slot, "uid":card_uid}

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END or not _dragging: return
	_dragging = false
	var succeeded := is_drag_successful()
	interface.drag_finished()
	%Lift.modulate.a = 1.0
	if succeeded or definition == null:
		_reset_lift()
	else:
		# The native preview is gone; the same card returns from its release point.
		if _lift_tween: _lift_tween.kill()
		z_index = 5
		%Lift.position = get_global_transform().affine_inverse() * interface.drag_pointer - Vector2(80,196)
		%Lift.rotation = -.025
		%Lift.scale = Vector2.ONE * 1.02
		_lift_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_lift_tween.tween_property(%Lift, "position", Vector2.ZERO, .24)
		_lift_tween.tween_property(%Lift, "scale", Vector2.ONE, .24)
		_lift_tween.tween_property(%Lift, "rotation", 0.0, .24)
		_lift_tween.chain().tween_callback(func(): z_index = 0)
