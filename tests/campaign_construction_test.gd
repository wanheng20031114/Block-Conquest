extends SceneTree
## Verify saved paving against actual terrain meshes, and the full intro lifecycle.

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

func terrain_surfaces(landscape: Node3D) -> Dictionary:
	var heights := {}
	for child: Node in landscape.get_node("Terrain").get_children():
		if not str(child.name).ends_with("Surface"):
			continue
		var mesh: MultiMesh = child.multimesh
		for index: int in mesh.instance_count:
			var transform := mesh.get_instance_transform(index)
			var size := transform.basis.get_scale()
			var low := transform.origin - size * 0.5
			var high := transform.origin + size * 0.5
			for x: int in range(floori((low.x + 0.001) * 4), ceili((high.x - 0.001) * 4)):
				for z: int in range(floori((low.z + 0.001) * 4), ceili((high.z - 0.001) * 4)):
					heights[Vector2i(x, z)] = high.y
	return heights

func verify_road(landscape: Node3D) -> void:
	# Independent measurement of the saved native geometry, not the author's
	# Python height function: check all four corners of every paving brick.
	var ground := terrain_surfaces(landscape)
	check(ground.size() > 15000, "terrain measurements contain the authored heightfield; use a real renderer")
	var brick_count := 0
	var unsupported := 0
	var excessive_lip := 0
	var buried := 0
	var max_lip := 0.0
	for name: String in ["Trail", "TrailShoulder"]:
		var mesh: MultiMesh = landscape.get_node("Terrain/" + name).multimesh
		for index: int in mesh.instance_count:
			var transform := mesh.get_instance_transform(index)
			var size := transform.basis.get_scale()
			brick_count += 1
			for dx: float in [-0.499, 0.499]:
				for dz: float in [-0.499, 0.499]:
					var at := transform.origin + Vector3(dx * size.x, 0, dz * size.z)
					var cell := Vector2i(floori(at.x * 4), floori(at.z * 4))
					if not ground.has(cell):
						unsupported += 1
						continue
					var top := at.y + size.y * 0.5
					var bottom := at.y - size.y * 0.5
					var elevation: float = ground[cell]
					max_lip = maxf(max_lip, top - elevation)
					if bottom > elevation:
						unsupported += 1
					if top - elevation > 0.012:
						excessive_lip += 1
					if top < elevation - 0.001:
						buried += 1
	check(brick_count > 2000, "the whole route is authored from small paving blocks")
	check(unsupported == 0, "every paving corner embeds into actual terrain: %d unsupported" % unsupported)
	check(excessive_lip == 0, "road lips stay within 12 mm of the surface")
	check(buried == 0, "every road brick keeps its walking surface exposed")
	var bridge: Node3D = landscape.get_node("Landmarks/Crossing")
	var bridge_mesh: MultiMesh = bridge.get_node("Timber").multimesh
	var bank_contacts := 0
	for index: int in bridge_mesh.instance_count:
		var transform := bridge_mesh.get_instance_transform(index)
		var size := transform.basis.get_scale()
		if not is_equal_approx(size.y, 0.16) or absf(transform.origin.x) < 3.3:
			continue
		var top := bridge.transform * (transform.origin + Vector3(0, size.y * 0.5, 0))
		var cell := Vector2i(floori(top.x * 4), floori(top.z * 4))
		check(ground.has(cell) and absf(top.y - float(ground.get(cell, -100))) < 0.14, "bridge end meets its graded bank")
		bank_contacts += 1
	check(bank_contacts == 2, "both bridge approaches were measured")
	print("PAVING bricks=", brick_count, " unsupported=", unsupported, " maximum_lip=", max_lip)

func verify_finished(diorama: SubViewportContainer, authored: Node3D) -> void:
	check(not diorama.intro_running, "intro reports completion")
	check(diorama.camera.get_parent().rotation_degrees.is_equal_approx(Vector3(-48, -8, 0)), "camera settles before projecting UI")
	var clock: float = diorama.landscape.get_node("Terrain/WestSurface").material_override.get_shader_parameter("build_time")
	check(is_equal_approx(clock, 1.6), "all terrain columns reach their full authored height")
	for path: NodePath in [^"Landmarks", ^"Groves"]:
		var originals: Array[Node] = authored.get_node(path).get_children()
		if path == NodePath("Groves"):
			var trees: Array[Node] = []
			for grove: Node in originals:
				trees.append_array(grove.get_children())
			originals = trees
		for node: Node3D in originals:
			var actual: Node3D = diorama.landscape.get_node(authored.get_path_to(node))
			check(actual.visible and actual.transform.is_equal_approx(node.transform), "settled pose matches saved model " + str(node.name))
	check(current_scene.get_node("%Stops").visible and current_scene.stops.all(func(stop: Button): return not stop.disabled), "stage controls appear only after the models settle")

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	var authored: Node3D = LANDSCAPE.instantiate()
	verify_road(authored)
	change_scene_to_file(MAP)
	await scene_changed
	var diorama: SubViewportContainer = current_scene.diorama
	check(diorama.intro_running, "entering starts a fresh construction intro")
	check(not current_scene.get_node("%Stops").visible, "markers stay hidden while the camera is moving")
	check(diorama.landscape.get_node("Landmarks").get_children().all(func(node: Node3D): return not node.visible), "buildings start hidden above the flat map")
	check(float(diorama.landscape.get_node("Terrain/WestSurface").material_override.get_shader_parameter("build_time")) < 0.1, "first render starts flat")
	await create_timer(0.55).timeout
	var session := root.get_node("Session")
	session.settings.open_menu()
	var paused_at: float = diorama.entrance.current_animation_position
	var camera_at: Transform3D = diorama.camera.get_parent().transform
	await create_timer(0.35).timeout
	check(is_equal_approx(diorama.entrance.current_animation_position, paused_at), "settings pauses the terrain and landing timeline")
	check(diorama.camera.get_parent().transform.is_equal_approx(camera_at), "settings pauses camera motion")
	key(KEY_SPACE)
	check(diorama.intro_running, "a modal dialog blocks intro skip")
	session.settings.menu.get_node("%Close").pressed.emit()
	await create_timer(1.0).timeout
	var airborne := 0
	for original: Node3D in authored.get_node("Landmarks").get_children():
		var actual: Node3D = diorama.landscape.get_node(authored.get_path_to(original))
		if actual.visible and actual.position.y > original.position.y + 0.3:
			airborne += 1
	check(airborne > 0, "buildings visibly descend after the terrain rises")
	check(not current_scene.get_node("%Stops").visible, "markers cannot float over airborne buildings")
	if diorama.intro_running:
		await diorama.intro_finished
	verify_finished(diorama, authored)
	await create_timer(0.5).timeout
	check(is_equal_approx(current_scene.stops[current_scene.selected_index].get_node("Badge").position.y, -9.0), "marker reveal does not disturb selection lift")
	# Every new visit reinitializes local materials and animation tracks.
	for shortcut: Key in [KEY_SPACE, KEY_KP_4]:
		change_scene_to_file(MAP)
		await scene_changed
		await create_timer(0.15).timeout
		check(current_scene.diorama.intro_running, "a subsequent visit replays the opening")
		key(shortcut)
		verify_finished(current_scene.diorama, authored)
		await create_timer(0.5).timeout
		if shortcut == KEY_KP_4:
			check(current_scene.selected_index == 3, "keypad skips directly to the requested stage")
	change_scene_to_file(MAP)
	await scene_changed
	await create_timer(0.15).timeout
	var departing: Control = current_scene
	key(KEY_ESCAPE)
	await scene_changed
	await session.transition.completed
	check(not is_instance_valid(departing), "exiting mid-intro frees its animation players")
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "escape returns during unfolding")
	authored.free()
	print("CAMPAIGN_CONSTRUCTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
