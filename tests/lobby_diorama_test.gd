extends SceneTree
## Native viewport input: picking, interruption, modal blocking and window sizing.
var checks := 0
var failures: Array[String] = []
var taps := 0
var hover_changes := 0
var toy: LobbyDiorama
var mouse_point := Vector2(610, 710)

func _initialize() -> void:
	# Supply an event each physics tick so passive picking never reads the real
	# Windows cursor. The private desktop must not move or capture that cursor.
	physics_frame.connect(func(): move(mouse_point))
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func settle(seconds: float = 0.3) -> void:
	await create_timer(seconds, true, false, true).timeout

func move(at: Vector2) -> void:
	mouse_point = at
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)

func click(at: Vector2) -> void:
	move(at)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)

func project(at: Vector3) -> Vector2:
	return toy.global_position + toy.camera.unproject_position(at) * toy.size / Vector2(toy.viewport.size)

func building_point(building: LobbyOutpost) -> Vector2:
	return project(building.global_position + Vector3(0, 1.3, 0))

func _run() -> void:
	create_timer(28.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	change_scene_to_file("res://scenes/lobby.tscn")
	await scene_changed
	await settle(0.75)
	var lobby: Control = current_scene
	toy = lobby.get_node("%Diorama")
	var home: LobbyOutpost = toy.outposts[0]
	var east: LobbyOutpost = toy.outposts[1]
	var session: Node = root.get_node("Session")
	var preferences: Dictionary = session.settings.snapshot()
	var drift: AnimationPlayer = toy.get_node("World/Stage/Island/Drift")
	var ferry: PathFollow3D = toy.ferry
	var rotor: Node3D = toy.get_node("World/Stage/Island/Windmill/Rotor")
	var title: Control = lobby.get_node("%Title")
	var title_position := title.global_position
	var version: Label = lobby.get_node("%Version")
	var version_position := version.global_position
	var shape: CollisionShape3D = home.get_node("Pick/Shape")
	var pick_rest := shape.global_transform
	home.touched.connect(func(_building): taps += 1)
	east.touched.connect(func(_building): taps += 1)
	home.hover_changed.connect(func(_building, _hover): hover_changes += 1)
	check(toy.viewport.own_world_3d, "miniature has its own world")
	check(drift.is_playing(), "background drift plays on entry")
	var ferry_before := ferry.position
	var rotor_before := rotor.rotation.z
	move(building_point(home))
	await settle(0.5)
	check(home.hovered and not east.hovered, "native mouse finds the first building")
	check(home.visual.position.y > 0.1, "hover visibly lifts the building")
	check(toy.hover_owner == home and toy.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "hover exposes a hand cursor")
	check(shape.global_transform.is_equal_approx(pick_rest), "hover never displaces its pick shape")
	check(hover_changes == 1, "stationary pointer does not flicker")
	check(not toy.pointer_target.is_zero_approx(), "native container motion drives parallax")
	check(ferry.position.distance_to(ferry_before) > 0.3, "ferry makes visible progress through the river in half a second")
	check(absf(rotor.rotation.z - rotor_before) > 0.2, "windmill turns visibly without user input")
	click(building_point(home))
	await settle(0.1)
	check(taps == 1 and home.reaction > 0.0, "one native click reacts once")
	check(absf(home.get_node("Lift/Model").rotation.z) > 0.001, "click has visible intermediate motion")
	await settle(0.5)
	check(home.get_node("Lift/Model").rotation.is_zero_approx(), "click returns exactly to rest")
	move(building_point(east))
	await settle()
	check(east.hovered and not home.hovered and toy.hover_owner == east, "hover transfers between buildings")
	for index: int in 10:
		move(building_point(home if index % 2 == 0 else east))
		await settle(0.055)
	move(Vector2(610, 710))
	await settle()
	check(not home.hovered and not east.hovered and toy.hover_owner == null, "rapid alternation and leaving clear hover")
	check(home.visual.position.is_zero_approx() and east.visual.position.is_zero_approx(), "interrupted hover returns to rest")
	check(shape.global_transform.is_equal_approx(pick_rest), "rapid input cannot accumulate pick transforms")
	click(project(Vector3(3.0, -0.6, 4.1)))
	await settle(0.1)
	check(toy.ripple_age < 0.3 and taps == 1, "water receives a click without tapping a building")
	await settle(1.4)
	check(toy.ripple_age > 1.3, "water ring fades rather than loops")
	check(title.global_position.is_equal_approx(title_position) and version.global_position.is_equal_approx(version_position), "idle motion leaves text anchored")
	check(version.text == "v" + str(ProjectSettings.get_setting("application/config/version")), "current configured release version remains visible")
	click(lobby.get_node("%Settings").get_global_rect().get_center())
	await settle()
	check(session.settings.is_open() and not toy.interactive, "settings disables miniature input")
	check(not toy.viewport.physics_object_picking and toy.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings stops picking and rendering")
	var frozen_clock := toy.clock
	var frozen_ferry := ferry.position
	var frozen_rotor := rotor.rotation
	click(building_point(home))
	await settle()
	check(taps == 1 and not home.hovered, "settings shields the building from background clicks")
	check(is_equal_approx(toy.clock, frozen_clock) and ferry.position.is_equal_approx(frozen_ferry) and rotor.rotation.is_equal_approx(frozen_rotor), "settings pauses shaders, ferry and windmill")
	click(session.settings.menu.get_node("%Close").get_global_rect().get_center())
	await settle()
	check(not session.settings.is_open() and toy.interactive and toy.clock > frozen_clock, "closing settings resumes the miniature")
	move(building_point(home))
	await settle()
	check(home.hovered, "native picking works again after closing settings")
	click(building_point(home))
	await settle(0.1)
	check(taps == 2, "click works again after closing settings")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(1024, 768)]:
		root.size = resolution
		await settle()
		check(lobby.get_global_rect().encloses(toy.get_global_rect()), "miniature fits at %s" % resolution)
		var controls: Rect2 = lobby.get_node("Margin/Column/Body/Welcome").get_global_rect()
		for building: LobbyOutpost in toy.outposts:
			check(not controls.has_point(building_point(building)), "buildings stay clear of menu text and buttons at %s" % resolution)
		move(building_point(east))
		await settle()
		check(east.hovered, "native picking follows viewport resizing at %s" % resolution)
	check(session.settings.snapshot() == preferences, "validation leaves settings unchanged")
	print("LOBBY_DIORAMA_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
