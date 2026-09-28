extends SceneTree
## Also runnable with --main-pack <exported PCK> --script <absolute test path>.
## Resolves every battle's assets from the pack and shuts audio down normally.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	check(ProjectSettings.get_setting("application/config/name") == "积木战争", "standalone product identity")
	check(not session.has_node("RelayClient") and not session.has_node("Rogue"), "standalone session")
	check(not FileAccess.file_exists("res://scenes/main.tscn") and not FileAccess.file_exists("res://scenes/main.tscn.remap"), "no traditional RTS battle in product")
	check(change_scene_to_file("res://scenes/lobby.tscn") == OK, "home loads")
	await scene_changed
	for map_id: String in ["rift", "lake", "rivers", "ridges", "islands", "highland"]:
		session.block_war_map_id = map_id
		check(session.start_war(true) == OK, map_id + " starts")
		await session.transition.completed
		var battle: Node = current_scene
		check(battle.map.definition.map_id == map_id, map_id + " selected map instantiated")
		check(battle.buildings.size() == battle.map.definition.building_positions.size(), map_id + " authored buildings loaded")
		check(battle.get_node("Audio/Music").playing, map_id + " packaged music plays")
		battle.camera_rig.focus_at(Vector3.ZERO, true)
		Input.action_press("war_pan_right")
		battle.camera_rig._process(0.1)
		Input.action_release("war_pan_right")
		check(battle.camera_rig.destination.length() > 0, map_id + " camera consumes standalone actions")
		await battle.prepare_shutdown()
		session.back_to_lobby()
		await session.transition.completed
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", map_id + " returns home")
	print("PRODUCT_RELEASE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
