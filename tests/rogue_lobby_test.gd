extends SceneTree
## Current catalogue baseline plus the new lobby route with the real Session.
## No external connection, game launch, or user-checkpoint modification.
var checks := 0
var failures: Array[String] = []
var session: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(35, true, false, true).timeout.connect(func() -> void: quit(3))
	session = root.get_node("Session")
	session.rogue.save_path = "user://rogue_lobby_ui_test.json"
	await _inspect_existing_catalogue()
	check(change_scene_to_file("res://scenes/lobby.tscn") == OK, "lobby loads with real Session")
	await scene_changed
	for frame: int in 3:
		await process_frame
	var lobby: Node3D = current_scene
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var ui: Control = lobby.get_node("CanvasLayer/UI")
		var names: Array[String] = ["SoloMenu", "Multiplayer", "RogueMode", "Codex", "Sandbox", "Settings", "QuitGame"]
		var buttons: Array[Control] = []
		for button_name: String in names:
			var button: Control = lobby.get_node("%" + button_name)
			check(button.is_visible_in_tree() and ui.get_global_rect().encloses(button.get_global_rect()), "%s: %s visible within lobby" % [dimensions, button_name])
			buttons.append(button)
		for first: int in buttons.size():
			for second: int in range(first + 1, buttons.size()):
				check(not buttons[first].get_global_rect().intersects(buttons[second].get_global_rect()), "%s: %s does not overlap %s" % [dimensions, names[first], names[second]])
	await _click(lobby.get_node("%SoloMenu"))
	check(lobby.get_node("%SoloPanel").visible, "old solo entry still opens")
	await _click(lobby.get_node("CanvasLayer/UI/SoloPanel/SoloScroll/Content/Heading/CloseSolo"))
	check(not lobby.get_node("%SoloPanel").visible, "old solo panel returns to lobby")
	await _click(lobby.get_node("%RogueMode"))
	for frame: int in 3:
		await process_frame
	check(current_scene.scene_file_path == "res://scenes/rogue/rogue_map.tscn", "native new entry reaches forest setup")
	var forest: Node3D = current_scene
	var setup: Control = forest.get_node("Canvas/UI/Setup")
	check(setup.visible, "new route presents strategy selection before a run")
	check(session.rogue.state == null and not session.online, "entry has no active run and remains offline")
	check(not FileAccess.file_exists(session.rogue.save_path), "opening setup does not create a checkpoint")
	await _click(forest.get_node("Canvas/UI/Setup/Margin/Content/Choices/Choice1"))
	check(forest._setup_step == 1, "strategy selection advances to initial army choice")
	await _click(forest.get_node("Canvas/UI/Setup/Margin/Content/Actions/Back"))
	check(forest._setup_step == 0, "back from army choice returns to strategy selection")
	await _click(forest.get_node("Canvas/UI/Setup/Margin/Content/Actions/Back"))
	for frame: int in 3:
		await process_frame
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "back from strategy selection returns to lobby")
	check(current_scene.get_node("%RogueMode").visible and current_scene.get_node("%SoloMenu").visible, "returned lobby retains both new and existing entries")
	check(not FileAccess.file_exists(session.rogue.save_path), "cancelled setup leaves isolated checkpoint untouched")
	print("ROGUE_LOBBY: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _inspect_existing_catalogue() -> void:
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	var expected: Array[int] = [BalanceCatalog.UNITS.size(), 5, BalanceCatalog.UPGRADES.size()]
	var observed: Array[int] = []
	for category: int in 3:
		codex._on_category_changed(category)
		var count: int = codex.get_node("%Entries").item_count
		observed.append(count)
		check(count == expected[category], "standalone catalogue category %d matches live resources" % category)
	var model_child_counts: Array[int] = []
	for sample: Array in [[0, "swordsman"], [1, "headquarters"], [2, "recovery_1"]]:
		codex.select_entry(sample[0], sample[1])
		var anchor: Node3D = codex.get_node("%ModelAnchor")
		var support: Node3D = codex.get_node("%SupportPreview")
		var previews: Array[Node] = []
		for child: Node in anchor.get_children():
			if child != support:
				previews.append(child)
		model_child_counts.append(anchor.get_child_count())
		check(previews.size() == 1 and previews[0] == codex._model, "%s has exactly one current model alongside authored support preview" % sample[1])
		check(anchor.get_child_count() == 2 and not support.visible, "%s retains existing hidden support preview" % sample[1])
	print("CODEX_EXISTING_BASELINE: category_counts=%s anchor_counts=%s; one model plus authored SupportPreview" % [observed, model_child_counts])
	codex.queue_free()
	await process_frame

func _click(control: Control) -> void:
	var center: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = center
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	if session.transition.busy:
		await session.transition.completed
	await process_frame
