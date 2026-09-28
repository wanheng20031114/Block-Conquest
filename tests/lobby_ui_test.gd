extends SceneTree
## Native input verifies the standalone home, settings and commander round trip.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func settle() -> void:
	await create_timer(0.65, true, false, true).timeout

func click(button: Button) -> void:
	var at := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	var original: Dictionary = session.settings.snapshot()
	check(not session.has_node("RelayClient") and not session.has_node("Rogue"), "standalone session has no other product services")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = resolution
		change_scene_to_file("res://scenes/lobby.tscn")
		await scene_changed
		await settle()
		var lobby: Control = current_scene
		check(lobby.get_node("%Title").text == "积木战争", "standalone product title is correct")
		var menu: VBoxContainer = lobby.get_node("Margin/Column/Body/Welcome/Menu")
		var entries: Array[String] = ["BlockWarMode", "OnlineMode", "Codex", "Settings", "Quit"]
		check(menu.get_children().map(func(child: Node): return String(child.name)) == entries, "home offers the current standalone multiplayer codex settings and quit entries")
		for name: String in entries:
			var button: Button = lobby.get_node("%" + name)
			check(not button.pressed.get_connections().is_empty(), "%s has an active navigation action" % name)
			check(lobby.get_global_rect().encloses(button.get_global_rect()), "%s fits at %s" % [name, resolution])
			check(is_equal_approx(button.modulate.a, 1.0), "%s finishes its entrance" % name)
		click(lobby.get_node("%Settings"))
		await settle()
		check(session.settings.is_open(), "native settings button opens the shared settings layer")
		for page: String in ["Graphics", "Audio", "Controls", "Hotkeys"]:
			click(session.settings.menu.get_node("%Categories/" + page))
			check(session.settings.menu.get_node("%Pages/" + page).visible, "native category opens: " + page)
		click(session.settings.menu.get_node("%Close"))
		check(not session.settings.is_open(), "settings close without leaving home")
		await settle()
		click(lobby.get_node("%BlockWarMode"))
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.scene_file_path == "res://scenes/block_war/commander_select.tscn", "start enters commander selection")
		click(current_scene.get_node("%Back"))
		await scene_changed
		await session.transition.completed
		await settle()
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "commander Back returns to the independent home")
	check(session.settings.snapshot() == original, "home navigation never saves or changes preferences")
	print("LOBBY_UI_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
