extends SceneTree
## GPU regression: silent HUD updates, interruption and paused-time motion.

var game: Node3D
var failures: Array[String] = []
var checks := 0
var buttons: Dictionary[int, Button] = {}


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)


func frames(count: int = 2) -> void:
	for index: int in count:
		await process_frame
	await RenderingServer.frame_post_draw


func ink(ratio: int, parameter: StringName) -> float:
	return float(buttons[ratio].get_node("Outline").get_instance_shader_parameter(parameter))


func settled(ratio: int, label: String) -> void:
	for value: int in buttons:
		check(buttons[value].button_pressed == (value == ratio), label + " native selection %d" % value)
		check(is_equal_approx(ink(value, &"selection"), 1.0 if value == ratio else 0.0), label + " visible selection %d" % value)
		check(is_equal_approx(ink(value, &"phase"), 1.0), label + " settled motion %d" % value)


func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.get_node("Session").block_war_map_id = "lake"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for ratio: int in [25, 50, 75, 100]:
		buttons[ratio] = game.hud.get_node("UI/Percentages/Stack/P%d" % ratio)
	await create_timer(0.65).timeout
	await frames()
	settled(50, "initial")
	check(game.hud.get_node("UI/Percentages/Symbol").text == "%", "heading is the percentage symbol")
	for ratio: int in buttons:
		check(buttons[ratio].get_node("Shortcut").text == "[%d]" % (ratio / 25), "visible shortcut %d" % ratio)
		check(game.hud.get_node("UI/Percentages").get_global_rect().encloses(buttons[ratio].get_global_rect()), "HUD avoidance bounds include button %d" % ratio)

	# HUD deliberately uses set_pressed_no_signal; motion must still start.
	game.set_percentage(25)
	await frames()
	check(game.percentage == 25 and ink(25, &"selection") == 1.0, "ratio and visible feedback respond immediately")
	check(ink(25, &"phase") > 0.0 and ink(25, &"phase") < 1.0, "silent native update starts the flow")
	check(ink(75, &"selection") == 0.0 and ink(100, &"selection") == 0.0, "shared material keeps inactive instances untouched")
	var previous_phase := ink(25, &"phase")
	for index: int in 4:
		game.update_hud()
		await frames(1)
	check(ink(25, &"phase") > previous_phase, "frequent HUD refresh does not restart the animation")
	await create_timer(0.3).timeout
	settled(25, "after refresh")

	# Repeated changes must cancel the previous fill, including a reselected item.
	for ratio: int in [100, 75, 25, 75, 50, 100]:
		game.set_percentage(ratio)
		await frames(1)
	await create_timer(0.35).timeout
	settled(100, "rapid interruption")
	Engine.time_scale = 0.0
	game.set_percentage(50)
	await create_timer(0.35, true, false, true).timeout
	settled(50, "zero simulation time")
	paused = true
	game.set_percentage(75)
	await create_timer(0.35, true, false, true).timeout
	settled(75, "paused tree")
	paused = false
	Engine.time_scale = 1.0

	game.set_percentage(25)
	await frames()
	game.hud.get_node("UI/Percentages").hide()
	await frames()
	settled(25, "hide cancels motion")
	game.hud.get_node("UI/Percentages").show()
	game.set_percentage(100)
	await frames()
	buttons[100].disabled = true
	await frames()
	check(is_equal_approx(ink(100, &"phase"), 1.0), "disabling settles in-flight motion")
	check(is_equal_approx(ink(100, &"availability"), 0.42), "disabled outline is visibly muted")
	buttons[100].disabled = false
	await frames()
	check(ink(100, &"availability") == 1.0, "reenabling restores outline visibility")
	game.set_percentage(50)
	await create_timer(0.3).timeout
	await frames()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		check(root.get_texture().get_image().save_png(args[0].path_join("hud.png")) == OK, "native HUD capture saved")
	await game.prepare_shutdown()
	print("BLOCK_WAR_PERCENTAGE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
