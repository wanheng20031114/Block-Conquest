extends Button
## The hit area stays still while its scene-authored paper marker lifts.

@export var stage: CampaignStage
var selected := false
var unlocked := false
var completed := false
var train_here := false
var _hovered := false
var _motion: Tween

func _ready() -> void:
	$Badge/Number.text = "%02d" % stage.number
	$Caption.text = stage.title
	tooltip_text = "%02d · %s\n%s" % [stage.number, stage.title, stage.region]
	pressed.connect(func(): get_node("/root/Session/UIFeedback").play(&"order"))
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
	$State.text = "列车停靠" if parked else ("已通关" if cleared else ("可挑战" if available else "待解锁"))
	var instruction := "点击进入关卡 · Enter 进入所选关卡" if available else "通过第 %02d 站后解锁" % (stage.number - 1)
	tooltip_text = "%02d · %s\n%s\n%s\n%s\n%s" % [stage.number, stage.title, stage.region, stage.description, $State.text, instruction]
	_refresh(false)

func _hover(value: bool) -> void:
	_hovered = value
	_refresh()

func _refresh(animated: bool = true) -> void:
	if _motion and _motion.is_valid():
		_motion.kill()
	var engaged := selected or _hovered or has_focus(true)
	var lift := -9.0 if selected else (-4.0 if engaged else 0.0)
	var fill := Color("ddc48d") if selected else (Color("dce3d0") if completed else (Color("fcf8e9") if unlocked else Color("deded5")))
	var edge := Color("886b3d") if selected else (Color("456153") if unlocked else Color("81867d"))
	$Badge/Focus.visible = has_focus(true)
	$Caption.add_theme_color_override("font_color", Color("354d41") if not selected else Color("67491f"))
	$State.add_theme_color_override("font_color", Color("526854") if unlocked else Color("787d75"))
	if not animated:
		$Badge.position.y = lift
		$Badge/Paper.color = fill
		$Badge/Edge.default_color = edge
		return
	_motion = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_motion.tween_property($Badge, "position:y", lift, 0.18)
	_motion.tween_property($Badge/Paper, "color", fill, 0.16)
	_motion.tween_property($Badge/Edge, "default_color", edge, 0.16)
