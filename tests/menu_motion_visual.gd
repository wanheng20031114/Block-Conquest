extends SceneTree
## Reproducible native menu demonstration, rendered at 24 fps on a private desktop.
## Run with tools/run_godot_private_desktop.py; the first user argument is the
## frame directory. No preferences are applied and no battle or connection starts.

const FRAMES: int = 336
const RESOLUTION := Vector2i(1280, 720)
const LOBBY := "res://scenes/lobby.tscn"
const COMMANDERS := "res://scenes/block_war/commander_select.tscn"
const MAPS := "res://scenes/block_war/map_select.tscn"

var output_directory: String
var session: Node
var checks: int = 0
var failed: bool = false
var _original_commander: StringName
var _original_map: StringName

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failed = true
		printerr("FAIL MENU_MOTION_VISUAL ", label)
	return value

func _control(name: String) -> Control:
	return current_scene.get_node("%" + name)

func _move(target: Control) -> void:
	var event := InputEventMouseMotion.new()
	event.position = target.get_global_rect().get_center()
	event.global_position = event.position
	root.push_input(event, true)

func _button(target: Control, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = target.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)

func _click(target: Control) -> void:
	_move(target)
	_button(target, true)
	_button(target, false)

func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path

func _step(frame: int) -> void:
	match frame:
		28: _move(_control("BlockWarMode"))
		32: _button(_control("BlockWarMode"), true)
		34: _button(_control("BlockWarMode"), false)
		64: _check(_scene_is(COMMANDERS) and not session.transition.busy, "lobby button finishes the native commander transition")
		72: _move(_control("Animal1"))
		78: _button(_control("Animal1"), true)
		80: _button(_control("Animal1"), false)
		82: _check(session.block_war_commander == &"rabbit", "native rabbit selection")
		108: _move(_control("Animal5"))
		114: _button(_control("Animal5"), true)
		116: _button(_control("Animal5"), false)
		118: _check(session.block_war_commander == &"frog", "native frog selection")
		136: _move(_control("Next"))
		140: _button(_control("Next"), true)
		142: _button(_control("Next"), false)
		176: _check(_scene_is(MAPS) and not session.transition.busy, "commander button finishes the native map transition")
		178: _move(_control("Map1"))
		180: _button(_control("Map1"), true)
		181: _button(_control("Map1"), false)
		188: _check(current_scene.selected.map_id == &"lake", "small map switches to the lake")
		205: _move(_control("Size2"))
		207: _button(_control("Size2"), true)
		208: _button(_control("Size2"), false)
		218: _check(current_scene.selected.map_id == &"islands", "large size selects the islands")
		224: _move(_control("Map1"))
		226: _button(_control("Map1"), true)
		227: _button(_control("Map1"), false)
		236: _check(current_scene.selected.map_id == &"highland", "large map switches to highland")
		244: _move(_control("Settings"))
		246: _button(_control("Settings"), true)
		247: _button(_control("Settings"), false)
		256: _check(session.settings.is_open(), "map settings open")
		270: _click(session.settings.menu.get_node("%Categories").get_node("Audio"))
		284: _check(session.settings.menu.get_node("%Pages/Audio").visible, "audio category opens")
		293: _click(session.settings.menu.get_node("%Categories").get_node("Controls"))
		307: _check(session.settings.menu.get_node("%Pages/Controls").visible, "controls category opens")
		316: _click(session.settings.menu.get_node("%Close"))
		332: _check(not session.settings.is_open() and _scene_is(MAPS), "settings close immediately back to map selection")

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not _check(not arguments.is_empty(), "output directory argument is present"):
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path(arguments[0])
	if not _check(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "frame directory can be created"):
		quit(1)
		return
	create_timer(40.0, true, false, true).timeout.connect(func():
		printerr("FAIL MENU_MOTION_VISUAL timeout")
		quit(3))
	root.size = RESOLUTION
	session = root.get_node("Session")
	_original_commander = session.block_war_commander
	_original_map = session.block_war_map_id
	session.block_war_commander = &"squirrel"
	session.block_war_map_id = &"rift"
	var original_preferences: Dictionary = session.settings.snapshot()
	if not _check(change_scene_to_file(LOBBY) == OK, "lobby scene loads"):
		_finish()
		return
	await scene_changed
	for frame: int in FRAMES:
		_step(frame)
		if failed:
			_finish()
			return
		await RenderingServer.frame_post_draw
		var screenshot: Image = root.get_texture().get_image()
		if frame == 0:
			_check(screenshot.get_size() == RESOLUTION, "render resolution is 1280 by 720")
		var destination := output_directory.path_join("frame_%04d.png" % frame)
		if not _check(screenshot.save_png(destination) == OK, "frame %d saves" % frame):
			_finish()
			return
	_check(session.settings.snapshot() == original_preferences, "settings preferences remain unchanged")
	_check(not session.online and session.relay.connection_state == "disconnected", "demo stays offline")
	_finish()

func _finish() -> void:
	session.block_war_commander = _original_commander
	session.block_war_map_id = _original_map
	session.settings.close_menu()
	print("MENU_MOTION_VISUAL frames=", FRAMES, " checks=", checks, " failed=", failed, " output=", output_directory)
	quit(1 if failed else 0)
