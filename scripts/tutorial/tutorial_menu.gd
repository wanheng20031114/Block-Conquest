extends Control
## Eleven independent practice maps; every lesson stays available for replay.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")

@onready var session: Node = get_node("/root/Session")
@onready var cards: Array[Button] = [%LessonBasics, %LessonInterface, %LessonHouse,
	%LessonTower, %LessonForge, %LessonEnergy, %LessonMorale, %LessonRecruit,
	%LessonDrum, %LessonShield, %LessonFire]
var _next := "basics"

func _ready() -> void:
	get_tree().paused = false
	var completed := PROGRESS.completed_lessons()
	_next = ""
	for lesson_id: String in CATALOG.IDS:
		if not completed.has(lesson_id):
			_next = lesson_id
			break
	for card: Button in cards:
		var lesson_id: String = card.get_meta("lesson_id")
		var done := completed.has(lesson_id)
		card.get_node("Margin/Column/Headline/Title").text = CATALOG.title(lesson_id)
		card.get_node("Margin/Column/Summary").text = CATALOG.summary(lesson_id)
		card.get_node("Margin/Column/Meta/Duration").text = CATALOG.minutes(lesson_id)
		card.get_node("Margin/Column/Meta/State").text = "已完成 · 可重玩" if done else "进入练习  →"
		if done:
			card.get_node("Margin/Column/Meta/State").add_theme_color_override("font_color", Color(0.27, 0.49, 0.34))
		card.tooltip_text = "%s\n%s\n%s · %s" % [CATALOG.title(lesson_id), CATALOG.summary(lesson_id), CATALOG.minutes(lesson_id), "已完成，可再次练习" if done else "独立练习场景"]
		card.pressed.connect(_start.bind(lesson_id))
	%Progress.text = "%d / %d  已完成" % [completed.size(), CATALOG.IDS.size()]
	%ProgressBar.value = float(completed.size()) / CATALOG.IDS.size() * 100.0
	%Continue.pressed.connect(_continue_learning)
	%Back.pressed.connect(_back)
	if _next.is_empty():
		%ContinueTitle.text = "基础已掌握，随时回来练一练"
		%ContinueNote.text = "所有课程都已完成。挑选任意场景，温习一项战场技巧。"
		%Continue.text = "重温第一课  →"
	elif completed.is_empty():
		%ContinueTitle.text = "第一次指挥，从这里开始"
		%ContinueNote.text = "先看演示，再亲手试一试。每次只学习一件事。"
		%Continue.text = "开始第一课  →"
	else:
		%ContinueTitle.text = "下一课：" + CATALOG.title(_next)
		%ContinueNote.text = "完成记录已保存。每节课都可以单独进入、重新练习。"
		%Continue.text = "继续学习  →"
	session.load_failed.connect(_show_error)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	%Continue.grab_focus(true)

func _continue_learning() -> void:
	_start("basics" if _next.is_empty() else _next)

func _start(lesson_id: String) -> void:
	if session.transition.busy:
		return
	if session.start_tutorial(lesson_id) != OK:
		_show_error("练习地图暂时无法打开，请检查游戏文件后重试。")

func _back() -> void:
	if session.transition.busy:
		return
	session.set_meta("tutorial_return_focus", true)
	session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()

func _show_error(message: String) -> void:
	%Message.text = message
	%Message.show()
	UIMotion.reveal_menu(%Message)
