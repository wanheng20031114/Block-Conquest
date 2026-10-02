extends SceneTree
## Measure the native railway geometry and exercise its complete intro lifecycle.

const MAP := "res://scenes/campaign/campaign_map.tscn"
const LANDSCAPE := preload("res://scenes/campaign/campaign_landscape.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func vertical_bounds(mesh: MultiMesh) -> Vector2:
	var low := INF
	var high := -INF
	for index: int in mesh.instance_count:
		var transform := mesh.get_instance_transform(index)
		var half_height := transform.basis.y.length() * 0.5
		low = minf(low, transform.origin.y - half_height)
		high = maxf(high, transform.origin.y + half_height)
	return Vector2(low, high)

func verify_railway(landscape: Node3D) -> void:
	# Read the saved MultiMesh transforms through the real renderer. A headless
	# dummy server returns zero transforms and must fail these measurements.
	var rails: MultiMesh = landscape.get_node("Terrain/Rails").multimesh
	var sleepers: MultiMesh = landscape.get_node("Terrain/Sleepers").multimesh
	var ballast: MultiMesh = landscape.get_node("Terrain/TrackBallast").multimesh
	var bridge: MultiMesh = landscape.get_node("Terrain/Bridge").multimesh
	var rail_bounds := vertical_bounds(rails)
	var sleeper_bounds := vertical_bounds(sleepers)
	check(rails.instance_count >= 800, "two continuous steel rails have authored foot and cap profiles")
	check(sleepers.instance_count >= 100, "sleepers run along the full railway")
	check(absf(rail_bounds.y - 0.52) < 0.0001, "actual rail caps meet the 0.52 train contact plane")
	check(absf(sleeper_bounds.y - 0.4) < 0.0001, "actual sleeper tops reach 0.40")
	check(rail_bounds.x <= sleeper_bounds.y and sleeper_bounds.y - rail_bounds.x < 0.01, "steel feet contact their sleepers without floating")
	check(absf(vertical_bounds(ballast).y - 0.31) < 0.0001, "ballast supports the sleepers at 0.31")
	check(sleeper_bounds.x <= vertical_bounds(ballast).y, "sleepers embed into the ballast")
	var decks := 0
	var west_end := INF
	var east_end := -INF
	for index: int in bridge.instance_count:
		var transform := bridge.get_instance_transform(index)
		var size := transform.basis.get_scale()
		if absf(size.z - 1.62) > 0.001 or absf(size.y - 0.15) > 0.001:
			continue
		decks += 1
		west_end = minf(west_end, transform.origin.x - size.x * 0.5)
		east_end = maxf(east_end, transform.origin.x + size.x * 0.5)
		check(absf(transform.origin.y + size.y * 0.5 - 0.31) < 0.0001, "timber bridge deck meets both railway approaches")
	check(decks >= 16 and west_end <= -1.8 and east_end >= 1.8, "native timber bridge spans the complete river channel")
	check(bridge.instance_count > decks + 20, "bridge includes supporting beams, piers and parapets")
	var curve: Curve3D = landscape.get_node("Journey").curve
	var anchors := landscape.get_node("StageAnchors").get_children()
	check(anchors.size() == 6, "six authored railway station anchors exist")
	check(landscape.get_node("Stations").get_child_count() == 6, "each level owns one visible station model")
	var previous := -1.0
	for index: int in anchors.size():
		var anchor: Marker3D = anchors[index]
		var offset := curve.get_closest_offset(anchor.position)
		check(curve.get_closest_point(anchor.position).distance_to(anchor.position) < 0.005, "station %d is on the physical railway" % (index + 1))
		check(absf(anchor.position.y - rail_bounds.y) < 0.0001, "station %d uses measured rail elevation" % (index + 1))
		if index > 0:
			check(offset - previous > 6.5 and offset - previous < 8.5, "successive stations remain close together")
		else:
			check(offset > 4.3, "the first station has enough rear approach for all three carriages")
		previous = offset
	var points := curve.get_baked_points()
	var longest_segment := 0.0
	for index: int in range(1, points.size()):
		longest_segment = maxf(longest_segment, points[index].distance_to(points[index - 1]))
	check(longest_segment < 0.08, "railway path has no discontinuity between station segments")
	print("RAILWAY rails=", rails.instance_count, " sleepers=", sleepers.instance_count, " bridge_decks=", decks, " rail_top=", rail_bounds.y)

func verify_train(diorama: SubViewportContainer) -> void:
	var curve: Curve3D = diorama.world_route.curve
	var followers: Array[PathFollow3D] = [diorama.train, diorama.tender, diorama.coach]
	var offsets: Array[float] = [0.0, 1.51, 2.94]
	for station: int in 6:
		diorama.park_train(station)
		var stop: Vector3 = diorama.anchors[station].position
		var progress := curve.get_closest_offset(stop)
		check(diorama.train.position.distance_to(stop) < 0.025, "locomotive parks at station %d" % (station + 1))
		for index: int in followers.size():
			var follower := followers[index]
			check(not follower.loop and follower.rotation_mode == PathFollow3D.ROTATION_Y, "carriage uses an open native railway follower")
			check(absf(follower.progress - (progress - offsets[index])) < 0.001, "station %d preserves carriage %d spacing" % [station + 1, index])
			check(follower.position.distance_to(curve.sample_baked(progress - offsets[index], false)) < 0.005, "carriage follows the actual curved rails")
			check(absf(follower.position.y - 0.52) < 0.0001, "carriage wheel origin rests on the steel rail surface")
	diorama.park_train(root.get_node("Session").campaign_current_stage())

func verify_finished(diorama: SubViewportContainer) -> void:
	check(not diorama.intro_running, "intro reports completion")
	check(diorama.camera.get_parent().rotation_degrees.is_equal_approx(Vector3(-48, -6, 0)), "camera settles before projecting station controls")
	check(diorama.landscape.position.is_equal_approx(Vector3.ZERO), "landscape settles at its authored origin")
	check(current_scene.get_node("%Stops").visible and current_scene.stops.all(func(stop: Button): return not stop.disabled), "station controls appear only after the world settles")
	check(diorama.landscape.get_node("Stations").get_children().all(func(node: Node3D): return node.visible), "all six physical stations remain visible")

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	var authored: Node3D = LANDSCAPE.instantiate()
	verify_railway(authored)
	authored.free()
	change_scene_to_file(MAP)
	await scene_changed
	var diorama: SubViewportContainer = current_scene.diorama
	check(diorama.intro_running, "entering starts a fresh railway reveal")
	check(not current_scene.get_node("%Stops").visible, "station markers stay hidden while the camera is moving")
	check(diorama.landscape.position.y < -0.9, "first render uses the authored lowered world pose")
	await create_timer(0.55).timeout
	var session := root.get_node("Session")
	session.settings.open_menu()
	var paused_at: float = diorama.entrance.current_animation_position
	var camera_time: float = diorama.camera_motion.current_animation_position
	var camera_at: Transform3D = diorama.camera.get_parent().transform
	var world_at: Transform3D = diorama.landscape.transform
	await create_timer(0.35).timeout
	check(is_equal_approx(diorama.entrance.current_animation_position, paused_at), "settings pauses the landscape timeline")
	check(is_equal_approx(diorama.camera_motion.current_animation_position, camera_time), "settings pauses the camera timeline")
	check(diorama.camera.get_parent().transform.is_equal_approx(camera_at), "settings keeps the camera pose unchanged")
	check(diorama.landscape.transform.is_equal_approx(world_at), "settings keeps the world pose unchanged")
	key(KEY_SPACE)
	check(diorama.intro_running, "a modal dialog blocks intro skip")
	session.settings.menu.get_node("%Close").pressed.emit()
	await create_timer(0.35).timeout
	check(diorama.entrance.current_animation_position > paused_at, "closing settings resumes the reveal")
	check(not current_scene.get_node("%Stops").visible, "markers stay hidden until the reveal completes")
	if diorama.intro_running:
		await diorama.intro_finished
	verify_finished(diorama)
	verify_train(diorama)
	await create_timer(0.5).timeout
	check(is_equal_approx(current_scene.stops[current_scene.selected_index].get_node("Badge").position.y, -9.0), "marker reveal preserves the selected station lift")
	# Each visit owns new animation players and can be skipped by either shortcut.
	for shortcut: Key in [KEY_SPACE, KEY_KP_4]:
		change_scene_to_file(MAP)
		await scene_changed
		await create_timer(0.15).timeout
		check(current_scene.diorama.intro_running, "a subsequent visit replays the opening")
		check(not current_scene.get_node("%Stops").visible, "reentry hides markers before the new reveal")
		key(shortcut)
		verify_finished(current_scene.diorama)
		await create_timer(0.5).timeout
		if shortcut == KEY_KP_4:
			check(current_scene.selected_index == 3, "keypad skips directly to the requested station")
	change_scene_to_file(MAP)
	await scene_changed
	await create_timer(0.15).timeout
	var departing: Control = current_scene
	key(KEY_ESCAPE)
	await scene_changed
	while session.transition.busy:
		await process_frame
	check(not is_instance_valid(departing), "exiting mid-intro frees its animation players")
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "escape returns to the lobby during the reveal")
	print("CAMPAIGN_CONSTRUCTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
