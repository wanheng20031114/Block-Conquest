extends Button
## The hit area stays still while its scene-authored paper marker lifts.

const BATTLE_ICON := preload("res://assets/ui/campaign/station_battle.svg")
const COMPLETE_ICON := preload("res://assets/ui/campaign/station_complete.svg")
const LOCKED_ICON := preload("res://assets/ui/campaign/station_locked.svg")

@export var stage: CampaignStage
var selected := false
var unlocked := false
var completed := false
var train_here := false
var _hovered := false
var _motion: Tween

func _ready() -> void:
	$Badge/Number.text = str(stage.number)
	$Caption.text = stage.title
	pressed.connect(func():
		if unlocked:
			get_node("/root/Session/UIFeedback").play(&"order")
	)
	mouse_entered.connect(_hover.bind(true))
	mouse_exited.connect(_hover.bind(false))
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)
	_refresh(false)

func set_selected(value: bool, animated: bool = true) -> void:
	selected = value
	_refresh(animated)

func set_progress(available: bool, cleared: bool, parked: bool) -> void:
	unlocked = available
	completed = cleared
	train_here = parked
	tooltip_text = ("重玩关卡" if cleared else "进入关卡") if available else "通过第 %d 站后解锁" % (stage.number - 1)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
	_refresh(false)

func _hover(value: bool) -> void:
	_hovered = value
	_refresh()

func _refresh(animated: bool = true) -> void:
	if _motion and _motion.is_valid():
		_motion.kill()
	var engaged := selected or _hovered or has_focus(true)
	var lift := -5.0 if selected else (-3.0 if engaged else 0.0)
	var fill := Color("f0dfb7") if selected else (Color("e1ead9") if completed else (Color("fcf8e9") if unlocked else Color("deded5")))
	var edge := Color("886b3d") if selected else (Color("456153") if unlocked else Color("81867d"))
	$Badge/Focus.visible = selected or has_focus(true)
	$Badge/StateIcon.texture = COMPLETE_ICON if completed else (BATTLE_ICON if unlocked else LOCKED_ICON)
	$Badge/TrainMarker.visible = train_here
	$Caption.visible = engaged
	$Caption.add_theme_color_override("font_color", Color("354d41") if not selected else Color("67491f"))
	if not animated:
		$Badge.position.y = lift
		$Badge/Paper.color = fill
		$Badge/Edge.default_color = edge
		return
	_motion = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_motion.tween_property($Badge, "position:y", lift, 0.18)
	_motion.tween_property($Badge/Paper, "color", fill, 0.16)
	_motion.tween_property($Badge/Edge, "default_color", edge, 0.16)
