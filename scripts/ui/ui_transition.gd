class_name UITransition
extends CanvasLayer
## A light, scene-authored folded map sheet. SceneTree's scene_changed
## remains the loading boundary; completed additionally signals ready input.

signal completed
signal failed(path: String, error: Error)

const CLOSE_SECONDS: float = 0.20
const OPEN_SECONDS: float = 0.25
var busy: bool = false
var _curtain: float = 0.0
var _tween: Tween
var _held_input_nodes: Array[Node] = []
@onready var veil: Control = $Veil
@onready var page: Control = $Veil/Page
@onready var map_mark: Control = $Veil/Page/MapMark

func _ready() -> void:
	veil.hide()
	veil.resized.connect(_layout_curtains)
	get_tree().scene_changed.connect(_on_scene_changed)
	_layout_curtains()

func change_scene(path: String) -> Error:
	if busy:
		return ERR_BUSY
	if not ResourceLoader.exists(path, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	var packed := load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return ERR_CANT_CREATE
	busy = true
	_hold_scene_input()
	veil.show()
	_animate_scene.call_deferred(packed, path)
	return OK

func _animate_scene(packed: PackedScene, path: String) -> void:
	_tween = _create_motion()
	_tween.tween_method(_set_curtain, 0.0, 1.0, CLOSE_SECONDS).set_ease(Tween.EASE_IN_OUT)
	await _tween.finished
	var error: Error = get_tree().change_scene_to_packed(packed)
	if error == OK:
		await get_tree().scene_changed
	else:
		failed.emit(path, error)
	_tween = _create_motion()
	_tween.tween_method(_set_curtain, 1.0, 0.0, OPEN_SECONDS).set_ease(Tween.EASE_OUT)
	await _tween.finished
	veil.hide()
	_release_scene_input()
	busy = false
	completed.emit()

func _input(event: InputEvent) -> void:
	# The full-screen Control blocks pointer clicks. This also prevents keyboard
	# shortcuts and camera commands reaching either scene under the curtains.
	if busy and (event is InputEventKey or event is InputEventMouse or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		get_viewport().set_input_as_handled()

func _hold_scene_input() -> void:
	_release_scene_input()
	var scene: Node = get_tree().current_scene
	if scene != null:
		_hold_input_branch(scene)

func _on_scene_changed() -> void:
	# Connect once from the persistent layer before callers await scene_changed,
	# so the new scene is protected at the same public loading boundary.
	if busy:
		_hold_scene_input()

func _hold_input_branch(node: Node) -> void:
	# CanvasLayer order controls drawing, not _input dispatch. Scene callbacks
	# can run before this persistent layer, so suspend those callbacks while
	# the sheet owns input. Processing, physics, and networking keep running.
	if node.is_processing_input():
		_held_input_nodes.append(node)
		node.set_process_input(false)
	for child: Node in node.get_children():
		_hold_input_branch(child)

func _release_scene_input() -> void:
	for node: Node in _held_input_nodes:
		# A successful scene replacement has already freed the previous branch.
		if is_instance_valid(node):
			node.set_process_input(true)
	_held_input_nodes.clear()

func _create_motion() -> Tween:
	return create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_ignore_time_scale(true).set_trans(Tween.TRANS_CUBIC)

func _set_curtain(value: float) -> void:
	_curtain = value
	_layout_curtains()

func _layout_curtains() -> void:
	var extent: Vector2 = veil.size
	# The folded lower edge lives just beyond the viewport at full coverage,
	# so scene replacement is hidden by a single continuous sheet of paper.
	page.size = Vector2(extent.x, extent.y + 28.0)
	page.position = Vector2(0, -page.size.y * (1.0 - _curtain))
	map_mark.modulate.a = smoothstep(0.45, 1.0, _curtain)
	map_mark.scale = Vector2.ONE * lerpf(0.98, 1.0, _curtain)
	map_mark.pivot_offset = map_mark.size * 0.5

func _exit_tree() -> void:
	_release_scene_input()
	if _tween != null and _tween.is_valid():
		_tween.kill()
