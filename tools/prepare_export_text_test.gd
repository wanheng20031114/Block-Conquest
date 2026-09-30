extends SceneTree
## Mount the finished product PCK from an empty --path. Copy its resources with
## PCKPacker and add only an isolated test autoload and startup configuration.
## Official release templates cannot run external scripts/path overrides.

var packer := PCKPacker.new()
var copied: int = 0
var failed: bool = false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists("res://project.godot"):
		push_error("Use an isolated exported PCK; arguments: output directory, absolute test script")
		quit(1)
		return
	var output: String = args[0]
	var test_script: String = args[1]
	ProjectSettings.set_setting("autoload/ExportTextTest", "*res://__release_checks__/text_layout.gd")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/codex/codex.tscn")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "BlockConquestReleaseChecks")
	if ProjectSettings.save_custom(output.path_join("project.binary")) != OK or packer.pck_start(output.path_join("text-check.pck")) != OK:
		quit(1)
		return
	_copy_resources("res://")
	if failed or packer.add_file("res://project.binary", output.path_join("project.binary")) != OK or packer.add_file("res://__release_checks__/text_layout.gd", test_script) != OK or packer.flush() != OK:
		quit(1)
		return
	print("EXPORT_TEXT_FIXTURE copied_resources=", copied)
	quit(0)

func _copy_resources(path: String) -> void:
	var directory := DirAccess.open(path)
	directory.include_hidden = true
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var source := path.path_join(name)
		if directory.current_is_dir():
			_copy_resources(source)
		elif source != "res://project.binary":
			if packer.add_file(source, source) != OK:
				push_error("Cannot copy packed resource " + source)
				failed = true
			copied += 1
		name = directory.get_next()
	directory.list_dir_end()
