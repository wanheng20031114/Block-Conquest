extends Control
## Two core chapters followed by optional advanced practice; all remain replayable.

const CATALOG := preload("res://scripts/tutorial/tutorial_catalog.gd")
const PROGRESS := preload("res://scripts/tutorial/tutorial_progress.gd")

@onready var session: Node = get_node("/root/Session")
@onready var cards: Array[Button] = [%LessonCoreCommand, %LessonCoreBuildings, %LessonHouse,
	%LessonMorale, %LessonTower, %LessonForge, %LessonEnergy, %LessonRecruit,
	%LessonDrum, %LessonShield, %LessonFire]
var _next := "core_command"

func _ready() -> void:
	get_tree().paused = false
	var completed := PROGRESS.completed_lessons(session.tutorial_progress_path)
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
	var core_completed := 0
	for lesson_id: String in CATALOG.CORE_IDS:
		if completed.has(lesson_id):
			core_completed += 1
	%Progress.text = "核心 %d / 2 · 进阶 %d / 9" % [core_completed, completed.size() - core_completed]
	%ProgressBar.value = float(completed.size()) / CATALOG.IDS.size() * 100.0
	%Continue.pressed.connect(_continue_learning)
	%Back.pressed.connect(_back)
	if _next.is_empty():
		%ContinueTitle.text = "全部完成，随时回来练一练"
		%ContinueNote.text = "重温核心章节，或挑选一项进阶技巧。"
		%Continue.text = "重温核心教学  →"
	elif completed.is_empty():
		%ContinueTitle.text = "先掌握两章核心教学"
		%ContinueNote.text = "从指挥部队到经营据点，边讲边练，循序完成。"
		%Continue.text = "继续核心教学  →"
	else:
		%ContinueTitle.text = "接下来：" + CATALOG.title(_next)
		%ContinueNote.text = "核心教学已完成，进阶练习可按兴趣选择。" if core_completed == 2 else "完成记录已保存，每章都可以重新练习。"
		%Continue.text = "继续学习  →"
	session.load_failed.connect(_show_error)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	resized.connect(_resize_columns)
	_resize_columns()
	%Continue.grab_focus(true)

func _continue_learning() -> void:
	_start(CATALOG.CORE_IDS[0] if _next.is_empty() else _next)

func _resize_columns() -> void:
	%AdvancedCards.columns = 2 if size.x < 1150.0 else 3

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
