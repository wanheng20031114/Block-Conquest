extends SceneTree
## Native clicks choose each size/map, launch the selected layout and retain it on restart.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _settle() -> void:
	for frame: int in 3:
		await process_frame
	while root.get_node("Session").transition.busy:
		await process_frame

func _click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	for index: int in CATALOG.MAPS.size():
		var definition: Resource = CATALOG.MAPS[index]
		change_scene_to_file("res://scenes/block_war/map_select.tscn")
		await scene_changed
		await _settle()
		var picker := current_scene
		_click(picker.get_node("%%Size%d" % definition.size_class))
		await _settle()
		_click(picker.get_node("%%Map%d" % (index % 2)))
		await _settle()
		check(picker.selected == definition, "size and map clicks select %s" % definition.map_id)
		check(picker.get_node("%Preview").definition == definition, "the preview follows the chosen map")
		check(picker.get_node("%Start").text.contains(definition.mode_label()), "start shows the selected team size")
		_click(picker.get_node("%%Map%d" % (index % 2)))
		check(picker.get_node("%%Map%d" % (index % 2)).button_pressed, "clicking the selected map keeps a selection")
		_click(picker.get_node("%Start"))
		await scene_changed
		await _settle()
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.audio.muted = true
		check(game.map.definition == definition and game.faction_count == definition.team_size * 2, "native Start loads the chosen layout and commanders")
		check(game._other_ai.size() == game.faction_count - 2, "every teammate and extra opponent has an independent AI")
		game.restart()
		await scene_changed
		await _settle()
		game = current_scene
		game.set_process(false)
		check(game.map.definition == definition and game.marches.team_total_for(0) == 0, "restart retains the selected map and resets its armies")
		game.exit_to_lobby()
		await scene_changed
		await _settle()
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "each size returns to the lobby")
		check(session.block_war_map_id == definition.map_id, "returning remembers the battlefield choice")
	session.block_war_map_id = "rift"
	print("BLOCK_WAR_MAP_SELECT checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
