extends SceneTree
## Verify the complete imported reference world, train, and campaign reveal.

const MAP := "res://scenes/campaign/campaign_map.tscn"
const LANDSCAPE := preload("res://scenes/campaign/campaign_landscape.tscn")
const MANIFEST := "res://assets/campaign/reference_railway/manifest.json"
const STATION_NAMES := ["花田站", "橡木镇", "林间驿站", "河岸驿站", "山麓驿站", "雪峰站"]
const MAP_IDS := ["rift", "lake", "rivers", "ridges", "switchback", "crown"]
const GEOMETRY := {
	"ReferenceTerrain": "terrain", "ReferenceProps": "props", "ReferenceTrack": "track",
	"ReferenceWater": "water", "ReferenceStations": "campaign_stations",
	"HydrangeaGarden": "hydrangeas",
}
var checks := 0
var failures: Array[String] = []
var manifest: Dictionary

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

func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func collect_mesh_bounds(node: Node, parent_transform: Transform3D, bounds: Array[AABB]) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	if node is MeshInstance3D:
		bounds.append(transform * node.mesh.get_aabb())
	for child: Node in node.get_children():
		collect_mesh_bounds(child, transform, bounds)

func verify_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for index: int in node.mesh.get_surface_count():
			if not node.mesh.surface_get_format(index) & Mesh.ARRAY_FORMAT_COLOR:
				continue
			var material: Material = node.get_active_material(index)
			check(material is StandardMaterial3D, "colored reference mesh uses a native material")
			if material is StandardMaterial3D:
				check(material.vertex_color_use_as_albedo, "original vertex colors contribute to the visible material")
				check(not material.vertex_color_is_srgb, "already linear reference colors avoid a second sRGB conversion")
	for child: Node in node.get_children():
		verify_materials(child)

func reference_point(s: float) -> Vector3:
	var samples: Array = manifest.path.samples
	var position := (s - float(samples[0].s)) / float(manifest.path.sample_step)
	var index := clampi(floori(position), 0, samples.size() - 2)
	var a: Dictionary = samples[index]
	var b: Dictionary = samples[index + 1]
	return Vector3(a.x, a.y, a.z).lerp(Vector3(b.x, b.y, b.z), position - index)

func verify_geometry(landscape: Node3D) -> void:
	check(manifest.source_project == "medieval-voxel-railway", "assets identify the requested reference project")
	check(manifest.coordinates.world_width == 168 and manifest.coordinates.world_depth == 40, "reference terrain retains its full 168 by 40 extent")
	check(manifest.coordinates.terrain_ground_y == 8, "reference terrain retains ground elevation 8")
	for filename: String in manifest.source_files_sha256:
		check(FileAccess.get_sha256("res://tools/railway_reference/src/" + filename) == manifest.source_files_sha256[filename], "reference source snapshot matches its export: " + filename)
	for node_name: String in GEOMETRY:
		var model: Node3D = landscape.get_node(NodePath(node_name))
		check(model.scene_file_path.contains("/native/") and model.scene_file_path.ends_with(".scn"), node_name + " uses a saved native imported scene")
		var parts: Array[AABB] = []
		collect_mesh_bounds(model, Transform3D.IDENTITY, parts)
		verify_materials(model)
		check(not parts.is_empty(), node_name + " contains real mesh geometry")
		var actual := parts[0]
		for part: AABB in parts.slice(1):
			actual = actual.merge(part)
		var expected: Dictionary = manifest.assets[GEOMETRY[node_name]].bounds
		check(actual.position.distance_to(vector(expected.min)) < 0.05, node_name + " preserves the source minimum bounds")
		check(actual.end.distance_to(vector(expected.max)) < 0.05, node_name + " preserves the source maximum bounds")
	check(manifest.assets.props.triangles > 145000, "village, castle, church and woodland remain after replacing the old flat flower rows")
	check(manifest.assets.terrain.bounds.max[1] == 34, "original high snow peaks remain present")
	check(manifest.additional_stations.size() == 3, "three added stations supplement the three original stations")
	for station: Dictionary in manifest.additional_stations:
		check(station.source_model == "props.js:haltPlatform", "added station reuses reference modeling: " + str(station.key))

func verify_railway(landscape: Node3D) -> void:
	var curve: Curve3D = landscape.get_node("Journey").curve
	check(curve.resource_path == "res://data/campaign/journey_3d.tres", "railway uses its authored Curve3D resource")
	var anchors := landscape.get_node("StageAnchors").get_children()
	var parks := landscape.get_node("ParkAnchors").get_children()
	check(anchors.size() == 6 and parks.size() == 6, "six station markers have separate locomotive parking anchors")
	var stops: Array = [manifest.original_stops[0].s, manifest.original_stops[1].s]
	for station: Dictionary in manifest.additional_stations:
		stops.append(station.park_s)
	stops.append(manifest.original_stops[2].s)
	var previous := -1.0
	for index: int in parks.size():
		var park: Marker3D = parks[index]
		var anchor: Marker3D = anchors[index]
		var offset := curve.get_closest_offset(park.position)
		check(park.name == "Stage%02d" % (index + 1) and anchor.name == park.name, "station and parking anchors retain their authored order")
		check(park.position.distance_to(reference_point(float(stops[index]))) < 0.015, "station %d parks at its reference railway position" % (index + 1))
		check(curve.get_closest_point(park.position).distance_to(park.position) < 0.02, "station %d parking lies on the curved railway" % (index + 1))
		check(anchor.position.distance_to(park.position) < 16.0, "station %d marker belongs to its platform" % (index + 1))
		if index > 0:
			check(offset - previous >= 21.95, "stations %d and %d are separated by at least a full 22-unit train" % [index, index + 1])
		previous = offset
	check(absf(parks[0].position.y - 8.27) < 0.001 and absf(parks[5].position.y - 13.27) < 0.001, "railway climbs five units from meadow to snow station")
	var longest_segment := 0.0
	var points := curve.get_baked_points()
	for index: int in range(1, points.size()):
		longest_segment = maxf(longest_segment, points[index].distance_to(points[index - 1]))
	check(longest_segment < 0.3, "railway follows the dense original route without discontinuities")
	check(is_equal_approx(landscape.get_node("Entrance").get_animation(&"unfold").length, 2.0), "world entrance completes in two seconds")

func verify_train(diorama: SubViewportContainer) -> void:
	var curve: Curve3D = diorama.world_route.curve
	var followers: Array[Node] = diorama.world_route.get_children()
	check(followers.size() == 9 and manifest.train.cars.size() == 9, "all nine original train vehicles are present")
	check(is_equal_approx(float(manifest.train.length), 22.0), "complete reference train retains its 22-unit length")
	for follower: PathFollow3D in followers:
		verify_materials(follower.get_node("Model"))
	for station: int in 6:
		diorama.park_train(station)
		var stop: Vector3 = diorama.parking_anchors[station].position
		var progress := curve.get_closest_offset(stop)
		check(diorama.train.position.distance_to(stop) < 0.025, "locomotive parks at station %d" % (station + 1))
		for index: int in followers.size():
			var follower: PathFollow3D = followers[index]
			var offset := float(manifest.train.cars[index].offset)
			check(not follower.loop and follower.rotation_mode != PathFollow3D.ROTATION_NONE, "carriage follows an open railway with its authored orientation")
			check(is_equal_approx(float(follower.get_meta(&"rail_offset")), offset), "carriage %d preserves its original coupling offset" % (index + 1))
			check(absf(follower.progress - (progress - offset)) < 0.001, "station %d preserves carriage %d spacing" % [station + 1, index + 1])
			check(follower.position.distance_to(curve.sample_baked(progress - offset, follower.cubic_interp)) < 0.015, "carriage %d follows railway height and turns" % (index + 1))
			var ahead := curve.sample_baked(follower.progress + 0.1)
			var behind := curve.sample_baked(follower.progress - 0.1)
			var tangent: Vector3 = (diorama.world_route.global_basis * (ahead - behind)).normalized()
			var model: Node3D = follower.get_node("Model")
			check(model.global_basis.x.normalized().dot(tangent) > 0.98, "carriage %d source +X faces forward along the railway" % (index + 1))
	diorama.park_train(root.get_node("Session").campaign_current_stage())
	var parked: float = diorama.train.progress
	diorama.focus_station(5, false)
	diorama.show_overview(false)
	diorama.focus_station(0, false)
	check(is_equal_approx(diorama.train.progress, parked), "browsing either end and overview never moves the progress train")
	diorama.focus_station(current_scene.selected_index, false)

func verify_finished(diorama: SubViewportContainer) -> void:
	check(not diorama.intro_running, "intro reports completion")
	check(diorama.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "reference landscape uses a perspective camera")
	check(is_equal_approx(diorama.camera.position.z, diorama.STATION_DISTANCE), "camera settles at the station inspection distance")
	check(diorama.landscape.position.is_equal_approx(Vector3.ZERO), "landscape settles at its authored origin")
	check(current_scene.get_node("%Stops").visible and current_scene.stops.all(func(stop: Button): return not stop.disabled), "station controls appear after the world settles")
	for node_name: String in GEOMETRY:
		check(diorama.landscape.get_node(NodePath(node_name)).visible, node_name + " remains visible after the reveal")

func _run() -> void:
	create_timer(70.0, true, false, true).timeout.connect(func(): quit(3))
	manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var authored: Node3D = LANDSCAPE.instantiate()
	verify_geometry(authored)
	verify_railway(authored)
	authored.free()
	change_scene_to_file(MAP)
	await scene_changed
	var diorama: SubViewportContainer = current_scene.diorama
	var session := root.get_node("Session")
	for index: int in 6:
		check(session.CAMPAIGN_STAGES[index].title == STATION_NAMES[index], "station %d title matches its scenery" % (index + 1))
		check(session.CAMPAIGN_STAGES[index].map_id == MAP_IDS[index], "station %d retains its existing battle mapping" % (index + 1))
	check(diorama.intro_running, "entering starts a fresh railway reveal")
	check(not current_scene.get_node("%Stops").visible, "station markers stay hidden while the camera is moving")
	check(diorama.landscape.position.y < -0.9, "first render uses the authored lowered world pose")
	check(is_equal_approx(diorama.camera_motion.get_animation(&"unfold").length, 2.0), "camera entrance completes in two seconds")
	var sun: DirectionalLight3D = diorama.get_node("World/Stage/Sun")
	var environment: Environment = diorama.get_node("World/Stage/Environment").environment
	check(sun.shadow_enabled and sun.light_energy > 0.0, "daylight casts clear shadows across the reference landscape")
	check(environment.ambient_light_energy > 0.0 and environment.ambient_light_color.v > 0.0, "sky fill preserves shaded terrain and building detail")
	await create_timer(0.55).timeout
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
	for shortcut: Key in [KEY_SPACE, KEY_KP_4]:
		change_scene_to_file(MAP)
		await scene_changed
		await create_timer(0.15).timeout
		check(current_scene.diorama.intro_running, "a subsequent visit replays the opening")
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
