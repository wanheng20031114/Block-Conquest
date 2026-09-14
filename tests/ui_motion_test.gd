extends SceneTree
## Exercise interrupted native tweens, container geometry, and the persistent
## transition under pause. It never reads or writes a player's checkpoint.

const FIXTURE: String = "res://tests/ui_motion_fixture.tscn"
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	root.visible = false
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func settle(seconds: float = 0.20) -> void:
	await create_timer(seconds, true, false, true).timeout

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file(FIXTURE)
	await scene_changed
	await process_frame
	var fixture: Control = current_scene
	var button: Button = fixture.get_node("Buttons/Primary")
	var next_button: Button = fixture.get_node("Buttons/Secondary")
	UIMotion.bind_buttons(fixture)
	UIMotion.bind_buttons(fixture)
	check(button.mouse_entered.get_connections().size() == 1, "binding is idempotent")
	var origin: Vector2 = button.position
	var next_origin: Vector2 = next_button.position
	button.mouse_entered.emit()
	await settle()
	check(button.scale.is_equal_approx(Vector2.ONE * 1.02), "hover raises by two percent")
	check(button.position == origin and next_button.position == next_origin, "hover preserves container layout")
	next_button.mouse_entered.emit()
	await settle()
	check(next_button.scale == Vector2.ONE and next_button.self_modulate.r > 1.0, "compact buttons keep their footprint with material feedback")
	next_button.mouse_exited.emit()
	button.button_down.emit()
	await settle()
	check(button.scale.is_equal_approx(Vector2.ONE * 0.98), "press has a restrained physical response")
	button.button_up.emit()
	button.mouse_exited.emit()
	await settle()
	check(button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate == Color.WHITE, "pointer exit restores transform and material")
	button.grab_focus()
	await settle()
	check(button.has_focus() and button.scale.is_equal_approx(Vector2.ONE) and button.self_modulate.r > 1.0, "default keyboard focus stays visible without enlarging the option")
	button.grab_focus(true)
	button.draw.emit()
	await settle()
	check(button.has_focus() and not button.has_focus(true), "hidden focus preserves the keyboard return target")
	check(button.scale == Vector2.ONE and button.self_modulate == Color.WHITE, "hidden focus on the same owner restores its authored appearance")
	button.grab_focus()
	button.draw.emit()
	await settle()
	check(button.has_focus(true) and button.self_modulate.r > 1.0, "revealing focus on the same owner restores keyboard feedback")
	button.button_down.emit()
	next_button.grab_focus(true)
	await settle()
	check(not button.get_meta(UIMotion.BUTTON_META).down and button.scale == Vector2.ONE and button.self_modulate == Color.WHITE, "losing focus cancels an interrupted press")
	button.grab_focus()
	button.mouse_entered.emit()
	await settle()
	check(button.scale.is_equal_approx(Vector2.ONE * 1.02), "a focused button still enlarges on pointer hover")
	button.mouse_exited.emit()
	await settle()
	check(button.has_focus() and button.scale.is_equal_approx(Vector2.ONE), "pointer exit restores size even while keyboard focus remains")
	button.disabled = true
	button.draw.emit()
	button.mouse_entered.emit()
	await settle()
	check(button.scale == Vector2.ONE and button.self_modulate == Color.WHITE, "disabled control stays still")
	button.disabled = false
	button.release_focus()
	button.mouse_entered.emit()
	await process_frame
	button.hide()
	check(button.scale == Vector2.ONE, "hiding cancels an active button tween")
	button.show()
	await process_frame
	var panel: Control = fixture.get_node("Independent")
	var panel_origin: Vector2 = panel.position
	UIMotion.reveal(panel)
	await process_frame
	UIMotion.reveal(panel)
	await settle(0.25)
	check(panel.position.is_equal_approx(panel_origin) and is_equal_approx(panel.modulate.a, 1.0), "repeated reveals do not compound displacement or opacity")
	UIMotion.dismiss(panel)
	await process_frame
	UIMotion.reveal(panel)
	await settle(0.25)
	check(panel.visible and panel.position.is_equal_approx(panel_origin), "reopening interrupts a dismissal cleanly")
	UIMotion.dismiss(panel)
	await settle()
	check(not panel.visible and panel.position.is_equal_approx(panel_origin), "dismiss hides and restores the authored layout")
	panel.show()
	UIMotion.reveal(panel)
	panel.hide()
	await settle()
	check(not panel.visible and is_equal_approx(panel.modulate.a, 1.0), "external hide cancels reveal without making a future show transparent")
	var managed: Control = fixture.get_node("ManagedBox/Managed")
	var managed_origin: Vector2 = managed.position
	UIMotion.reveal(managed, Vector2(80, 60))
	await settle(0.25)
	check(managed.position == managed_origin and managed.scale == Vector2.ONE, "container-owned offsets are never animated")
	var anchored: Control = fixture.get_node("Anchored")
	UIMotion.reveal(anchored, Vector2(12, 8))
	await process_frame
	fixture.size.x += 100.0
	await settle(0.25)
	check(is_equal_approx(anchored.offset_left, -90.0) and is_equal_approx(anchored.offset_top, 350.0), "native anchored resize survives an active reveal")
	button.mouse_entered.emit()
	var active: Tween = button.get_meta(UIMotion.BUTTON_META).tween
	fixture.remove_child(fixture.get_node("Buttons"))
	check(not active.is_valid(), "leaving the tree kills the bound button tween")
	button.get_parent().free()

	var session: Node = root.get_node("Session")
	var transition: UITransition = session.transition
	check(session.change_scene("res://tests/no_such_ui_scene.tscn") == ERR_FILE_NOT_FOUND, "invalid scene fails synchronously")
	check(not transition.busy and not transition.veil.visible, "invalid scene never traps input")
	check(session.change_scene(FIXTURE) == OK, "valid transition accepts the scene")
	check(transition.busy and transition.veil.visible, "transition claims input immediately")
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_F10
	shortcut.pressed = true
	root.push_input(shortcut, true)
	check(current_scene.key_presses == 0, "scene _input callbacks cannot run before the closing sheet consumes a shortcut")
	check(session.change_scene(FIXTURE) == ERR_BUSY, "double transition is rejected")
	var previous_config: Dictionary = session.config.duplicate(true)
	check(session.start_offline("1v1") == ERR_BUSY and session.config == previous_config, "repeated launch does not mutate the accepted match configuration")
	await scene_changed
	check(current_scene.scene_file_path == FIXTURE and transition.busy, "native scene_changed remains the loading boundary")
	root.push_input(shortcut, true)
	check(current_scene.key_presses == 0, "new scene shortcuts stay blocked while the sheet opens")
	await transition.completed
	check(not transition.busy and not transition.veil.visible, "completed transition releases input")
	root.push_input(shortcut, true)
	check(current_scene.key_presses == 1, "scene input resumes when the transition completes")
	paused = true
	Engine.time_scale = 0.01
	check(session.change_scene(FIXTURE) == OK, "transition can start from a paused menu")
	await scene_changed
	root.size = Vector2i(1280, 720)
	await transition.completed
	check(paused and not transition.busy, "paused gameplay does not freeze the real-time curtain")
	check(transition.page.size == transition.veil.size + Vector2(0, 28), "single folded sheet resizes to fully cover the viewport")
	paused = false
	Engine.time_scale = 1.0
	print("UI_MOTION_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
