extends CanvasLayer
## Scene-authored tutorial chrome. Only the lesson controller changes simulation
## time; this layer and its native animations remain responsive while teaching.

signal continue_requested
signal replay_requested
signal retry_requested
signal exit_requested
signal next_requested

const MAX_SPOTLIGHTS := 8
const CALLOUT_GAP := 24.0
const SCREEN_MARGIN := 20.0

@onready var ui: Control = $UI
@onready var dimmer: ColorRect = %Dimmer
@onready var objective: PanelContainer = %Objective
@onready var chapter_label: Label = %Chapter
@onready var objective_title: Label = %ObjectiveTitle
@onready var objective_progress: Label = %ObjectiveProgress
@onready var instruction: PanelContainer = %Instruction
@onready var instruction_title: Label = %InstructionTitle
@onready var instruction_body: Label = %InstructionBody
@onready var pause_note: Label = %PauseNote
@onready var continue_button: Button = %Continue
@onready var next_button: Button = %Next
@onready var completion_actions: HBoxContainer = %CompletionActions
@onready var gesture: Control = %Gesture
@onready var hint: PanelContainer = %Hint
@onready var hint_text: Label = %HintText
@onready var hint_timer: Timer = $HintTimer
@onready var annotations: Control = $UI/Annotations

var _spotlights: Array[Rect2] = []
var _completion := false
var _layout_pending := false
var _layout_profile := -1


func _ready() -> void:
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	next_button.pressed.connect(func() -> void: next_requested.emit())
	%Replay.pressed.connect(func() -> void: replay_requested.emit())
	%Retry.pressed.connect(func() -> void: retry_requested.emit())
	%Exit.pressed.connect(func() -> void: exit_requested.emit())
	%CompletionRetry.pressed.connect(func() -> void: retry_requested.emit())
	%CompletionExit.pressed.connect(func() -> void: exit_requested.emit())
	hint_timer.timeout.connect(hint.hide)
	ui.resized.connect(_queue_layout)
	instruction.resized.connect(_queue_layout)
	objective.resized.connect(_queue_layout)
	# Wrapped text computes its new minimum after Container sorting. A hidden
	# label's old width must never leave its parent at a one-character column.
	hint_text.minimum_size_changed.connect(_queue_layout)
	instruction_body.minimum_size_changed.connect(_queue_layout)
	UIMotion.bind_menu_buttons(ui)
	get_node("/root/Session/UIFeedback").bind_buttons(ui)
	instruction.add_theme_stylebox_override("panel", instruction.get_theme_stylebox("panel").duplicate())
	_queue_layout()


func set_objective(chapter: String, title: String, progress: String) -> void:
	chapter_label.text = chapter
	objective_title.text = title
	objective_progress.text = progress
	objective_progress.visible = not progress.is_empty()
	_queue_layout()


func show_instruction(title: String, body: String, button_text: String = "继续", direct_action: bool = false) -> void:
	_completion = false
	instruction_title.text = title
	instruction_body.text = body
	continue_button.text = button_text
	continue_button.visible = not direct_action
	completion_actions.hide()
	%Replay.disabled = true
	%Retry.disabled = true
	pause_note.text = "已暂停 · 可直接操作" if direct_action else "已暂停"
	instruction.show()
	dimmer.show()
	hint.hide()
	_queue_layout()
	UIMotion.reveal_menu(instruction, Vector2.ZERO)
	if not direct_action:
		continue_button.grab_focus.call_deferred()
	else:
		continue_button.release_focus()


func dismiss_instruction() -> void:
	instruction.hide()
	dimmer.hide()
	%Replay.disabled = false
	%Retry.disabled = false
	continue_button.release_focus()
	next_button.release_focus()
	set_interaction_regions([])


func set_interaction_regions(rects: Array[Rect2]) -> void:
	dimmer.interaction_regions.assign(rects)


func set_annotations(items: Array[Dictionary]) -> void:
	if annotations.set_annotations(items):
		_queue_layout()


func set_spotlights(rects: Array[Rect2]) -> void:
	if rects == _spotlights:
		return
	_spotlights.assign(rects.slice(0, MAX_SPOTLIGHTS))
	_update_spotlights()
	if instruction.visible:
		_queue_layout()


func set_gesture(from: Vector2, to: Vector2, kind: String = "drag") -> void:
	var previous_bounds: Rect2 = gesture.gesture_bounds()
	var was_visible := gesture.visible
	gesture.set_gesture(from, to, kind)
	if instruction.visible and (not was_visible or not previous_bounds.is_equal_approx(gesture.gesture_bounds())):
		_queue_layout()


func clear_gesture() -> void:
	gesture.clear_gesture()


func show_completion(title: String, body: String, has_next: bool) -> void:
	_completion = true
	clear_gesture()
	set_spotlights([])
	set_annotations([])
	set_interaction_regions([])
	instruction_title.text = title
	instruction_body.text = body
	continue_button.hide()
	completion_actions.show()
	%Replay.disabled = true
	%Retry.disabled = true
	next_button.visible = has_next
	pause_note.text = "本课完成"
	instruction.show()
	dimmer.show()
	hint.hide()
	_queue_layout()
	UIMotion.reveal_menu(instruction, Vector2.ZERO)
	if has_next:
		next_button.grab_focus.call_deferred()
	else:
		%CompletionExit.grab_focus.call_deferred()


func show_hint(message: String) -> void:
	if message.is_empty():
		hint.hide()
		hint_timer.stop()
		return
	hint.size.x = objective.size.x
	hint_text.text = message
	hint.show()
	hint_timer.start()
	_queue_layout()
	UIMotion.reveal_menu(hint, Vector2.ZERO)


func is_instruction_visible() -> bool:
	return instruction.visible


func _queue_layout() -> void:
	if _layout_pending:
		return
	_layout_pending = true
	_layout.call_deferred()


func _layout() -> void:
	_layout_pending = false
	var viewport_size := ui.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var compact := viewport_size.x < 1350.0
	var small := viewport_size.x < 1150.0
	_configure_density(2 if small else (1 if compact else 0))
	objective.size.x = 280.0 if small else (302.0 if compact else 340.0)
	objective.position = Vector2(24.0, 112.0)
	# The left-hand percentage column must remain wholly visible when taught.
	for target: Rect2 in _spotlights:
		if target.position.x < 150.0 and target.size.x < 180.0 and target.size.y > 250.0:
			objective.position.x = maxf(objective.position.x, target.end.x + 16.0)
	objective.size.y = objective.get_combined_minimum_size().y
	hint.position = objective.position + Vector2(0.0, objective.size.y + 10.0)
	hint.size.x = objective.size.x
	hint.size.y = hint.get_combined_minimum_size().y
	instruction.size.x = minf(440.0 if compact else 500.0, viewport_size.x - 48.0)
	instruction.size.y = instruction.get_combined_minimum_size().y
	instruction.pivot_offset = instruction.size * 0.5
	if _completion:
		instruction.position = (viewport_size - instruction.size) * 0.5
	else:
		instruction.position = _instruction_position(viewport_size)
	var occupied: Array[Rect2] = [objective.get_rect()]
	if instruction.visible: occupied.append(instruction.get_rect().grow(10.0))
	if hint.visible: occupied.append(hint.get_rect())
	if gesture.visible: occupied.append_array(gesture.annotation_exclusion_rects())
	annotations.layout_annotations(viewport_size, occupied)
	_update_spotlights()


func _instruction_position(viewport_size: Vector2) -> Vector2:
	var limit := (viewport_size - instruction.size - Vector2.ONE * SCREEN_MARGIN).max(Vector2.ONE * SCREEN_MARGIN)
	var candidates: Array[Vector2] = []
	# The first spotlight is the subject of this explanation. Other spotlights
	# (a skill's destination, for example) remain visible without making one
	# huge bounding rectangle that would push the explanation across the screen.
	for target: Rect2 in _spotlights:
		candidates.append_array(_adjacent_positions(target))
	# Include the demonstration's edge, so a caption between the highlighted
	# control and the explanation does not force the explanation far away.
	if gesture.visible:
		candidates.append_array(_adjacent_positions(gesture.gesture_bounds()))
	for x: float in [SCREEN_MARGIN, limit.x * 0.5, limit.x]:
		for y: float in [SCREEN_MARGIN, limit.y]:
			candidates.append(Vector2(x, y))
	var anchor: Rect2 = _spotlights[0] if not _spotlights.is_empty() else gesture.gesture_bounds()
	var best_position := limit
	var best_overlap := INF
	var best_distance := INF
	for candidate: Vector2 in candidates:
		# Score the actual on-screen position, including after a window resize.
		candidate = candidate.clamp(Vector2.ONE * SCREEN_MARGIN, limit)
		var panel := Rect2(candidate, instruction.size)
		var overlap := panel.grow(8.0).intersection(objective.get_rect()).get_area() * 4.0
		for target: Rect2 in _spotlights:
			overlap += panel.intersection(target.grow(16.0)).get_area() * 2.0
		if gesture.visible:
			overlap += panel.intersection(gesture.gesture_bounds()).get_area()
		var separation := (anchor.position - panel.end).max(panel.position - anchor.end).max(Vector2.ZERO)
		var distance := separation.length() * 8.0 + panel.get_center().distance_to(anchor.get_center()) * 0.05
		if overlap < best_overlap or (is_equal_approx(overlap, best_overlap) and distance < best_distance):
			best_overlap = overlap
			best_distance = distance
			best_position = candidate
	return best_position


func _adjacent_positions(target: Rect2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var panel_size := instruction.size
	var objective_rect := objective.get_rect()
	# Center on the subject when possible; slide along the same edge to avoid
	# the objective card, rather than moving to an unrelated screen corner.
	var columns := [target.get_center().x - panel_size.x * 0.5, target.position.x, target.end.x - panel_size.x,
		objective_rect.end.x + CALLOUT_GAP, objective_rect.position.x - panel_size.x - CALLOUT_GAP]
	var rows := [target.get_center().y - panel_size.y * 0.5, target.position.y, target.end.y - panel_size.y,
		objective_rect.end.y + CALLOUT_GAP, objective_rect.position.y - panel_size.y - CALLOUT_GAP]
	for x: float in columns:
		result.append(Vector2(x, target.end.y + CALLOUT_GAP))
		result.append(Vector2(x, target.position.y - panel_size.y - CALLOUT_GAP))
	for y: float in rows:
		result.append(Vector2(target.end.x + CALLOUT_GAP, y))
		result.append(Vector2(target.position.x - panel_size.x - CALLOUT_GAP, y))
	return result


func _configure_density(profile: int) -> void:
	if profile == _layout_profile:
		return
	_layout_profile = profile
	var small := profile == 2
	var compact := profile >= 1
	var column: VBoxContainer = instruction.get_node("Column")
	var portrait: TextureRect = instruction.get_node("Column/Guide/Portrait")
	var paper: StyleBoxFlat = instruction.get_theme_stylebox("panel")
	var inset := 18.0 if small else (22.0 if compact else 28.0)
	paper.content_margin_left = inset
	paper.content_margin_right = inset
	paper.content_margin_top = 16.0 if small else (18.0 if compact else 25.0)
	paper.content_margin_bottom = 16.0 if small else (18.0 if compact else 24.0)
	column.add_theme_constant_override("separation", 10 if small else (12 if compact else 16))
	portrait.visible = not small
	portrait.custom_minimum_size = Vector2.ONE * (32.0 if compact else 36.0)
	pause_note.add_theme_font_size_override("font_size", 13 if small else (14 if compact else 15))
	instruction_title.add_theme_font_size_override("font_size", 23 if small else (25 if compact else 28))
	instruction_body.add_theme_font_size_override("font_size", 17 if small else (18 if compact else 20))
	instruction_body.add_theme_constant_override("line_spacing", 3 if compact else 4)
	continue_button.custom_minimum_size.y = 42.0 if small else (46.0 if compact else 50.0)
	continue_button.add_theme_font_size_override("font_size", 19 if small else (20 if compact else 22))
	objective_title.add_theme_font_size_override("font_size", 20 if small else (22 if compact else 25))


func _update_spotlights() -> void:
	var values := PackedVector4Array()
	values.resize(MAX_SPOTLIGHTS)
	for index: int in _spotlights.size():
		var rect := _spotlights[index]
		values[index] = Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)
	var material := dimmer.material as ShaderMaterial
	material.set_shader_parameter("viewport_size", ui.size)
	material.set_shader_parameter("spotlight_count", _spotlights.size())
	material.set_shader_parameter("spotlights", values)
