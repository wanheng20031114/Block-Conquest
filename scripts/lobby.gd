extends Control
## The standalone game's home screen and its quiet interactive miniature.
@onready var session: Node = get_node("/root/Session")
@onready var backdrop: ShaderMaterial = $Background.material
var _pointer := Vector2(0.5, 0.5)
var _pointer_target := Vector2(0.5, 0.5)
var _pointer_presence := 0.0
var _mouse_inside := false
var _presentation_active := true

func _ready() -> void:
	get_tree().auto_accept_quit = true
	%Version.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	%BlockWarMode.pressed.connect(_start)
	%OnlineMode.pressed.connect(_start_online)
	%Tutorial.pressed.connect(_start_tutorial)
	%Codex.pressed.connect(_open_codex)
	%Settings.pressed.connect(session.settings.open_menu)
	%Quit.pressed.connect(_quit)
	session.load_failed.connect(_show_error)
	session.settings.closed.connect(_settings_closed)
	session.settings.opened.connect(_set_presentation_active.bind(false))
	get_window().mouse_exited.connect(_leave_mouse)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	%BlockWarMode.grab_focus(true)
	if session.get_meta("codex_return_focus", false):
		session.remove_meta("codex_return_focus")
		%Codex.grab_focus(true)
	if session.get_meta("tutorial_return_focus", false):
		session.remove_meta("tutorial_return_focus")
		%Tutorial.grab_focus(true)
	if OS.get_cmdline_user_args().has("--block-war") and not session.get_meta("block_war_cli_consumed", false):
		session.set_meta("block_war_cli_consumed", true)
		_start.call_deferred(true)

func _start(direct_launch: bool = false) -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	_set_presentation_active(false)
	if session.start_war(direct_launch) != OK:
		_set_presentation_active(true)
		_show_error("战争暂时无法开始，请检查游戏文件后重试。")

func _settings_closed() -> void:
	_set_presentation_active(true)
	%Settings.grab_focus(true)

func _open_codex() -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	_set_presentation_active(false)
	if session.change_scene("res://scenes/codex/codex.tscn") != OK:
		_set_presentation_active(true)
		_show_error("图鉴暂时无法打开，请检查游戏文件后重试。")

func _start_online() -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	_set_presentation_active(false)
	if session.start_online() != OK:
		_set_presentation_active(true)
		_show_error("联机大厅暂时无法打开，请检查游戏文件后重试。")

func _start_tutorial() -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	_set_presentation_active(false)
	if session.start_tutorial() != OK:
		_set_presentation_active(true)
		_show_error("入门教程暂时无法打开，请检查游戏文件后重试。")

func _set_presentation_active(value: bool) -> void:
	_presentation_active = value
	%Diorama.set_interactive(value)
	if not value:
		_leave_mouse()

func _leave_mouse() -> void:
	_mouse_inside = false
	%Diorama._leave()

func _input(event: InputEvent) -> void:
	if _presentation_active and event is InputEventMouseMotion:
		_pointer_target = (event.position / size).clamp(Vector2.ZERO, Vector2.ONE)
		_mouse_inside = true

func _process(delta: float) -> void:
	var response := 1.0 - exp(-delta * 4.0)
	_pointer = _pointer.lerp(_pointer_target, response)
	_pointer_presence = lerpf(_pointer_presence, 1.0 if _mouse_inside else 0.0, response)
	backdrop.set_shader_parameter("pointer", _pointer)
	backdrop.set_shader_parameter("pointer_presence", _pointer_presence)

func _show_error(message: String) -> void:
	%Message.text = message
	UIMotion.reveal_menu(%Message)

func _quit() -> void:
	if not session.settings.is_open() and not session.transition.busy:
		get_tree().quit()
