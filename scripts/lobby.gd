extends Control
## The standalone game's home screen; all play begins with its animal roster.
@onready var session: Node = get_node("/root/Session")

func _ready() -> void:
	get_tree().auto_accept_quit = true
	%Version.text = "v%s" % ProjectSettings.get_setting("application/config/version")
	%BlockWarMode.pressed.connect(_start)
	%Settings.pressed.connect(session.settings.open_menu)
	%Quit.pressed.connect(_quit)
	session.load_failed.connect(_show_error)
	session.settings.closed.connect(_settings_closed)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	%BlockWarMode.grab_focus(true)
	if OS.get_cmdline_user_args().has("--block-war") and not session.get_meta("block_war_cli_consumed", false):
		session.set_meta("block_war_cli_consumed", true)
		_start.call_deferred(true)

func _start(direct_launch: bool = false) -> void:
	if session.settings.is_open() or session.transition.busy:
		return
	if session.start_war(direct_launch) != OK:
		_show_error("战争暂时无法开始，请检查游戏文件后重试。")

func _settings_closed() -> void:
	%Settings.grab_focus(true)

func _show_error(message: String) -> void:
	%Message.text = message
	UIMotion.reveal_menu(%Message)

func _quit() -> void:
	if not session.settings.is_open() and not session.transition.busy:
		get_tree().quit()
