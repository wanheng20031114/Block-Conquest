extends SceneTree
## The complete train must visibly travel before the new station claims arrival.
## Optional rendered evidence: -- --capture res://.local/campaign-train-travel

const MAP := "res://scenes/campaign/campaign_map.tscn"
const MANIFEST := "res://assets/campaign/reference_railway/manifest.json"
var checks := 0
var failures: Array[String] = []
var session: Node
var capture_directory := ""
var arrival_events: Array[int] = []
var car_offsets: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)

func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func capture(name: String) -> void:
	if capture_directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name + ".png")) == OK, "save " + name)

func settle_transition() -> void:
	while session.transition.busy:
		await process_frame

func load_map() -> Control:
	check(session.change_scene(MAP) == OK, "campaign transition starts")
	await scene_changed
	return current_scene

func station_offset(diorama: SubViewportContainer, index: int) -> float:
	return diorama.world_route.curve.get_closest_offset(diorama.world_route.to_local(diorama.parking_anchors[index].global_position))

func view_stays_inside(diorama: SubViewportContainer) -> bool:
	# Independent ground-plane reconstruction catches camera-follow excursions
	# even if the production footprint/constraining implementation changes.
	var camera: Camera3D = diorama.camera
	var extent: Vector2 = camera.get_viewport().get_visible_rect().size
	var ground := Plane(Vector3.UP, 5.0)
	for corner: Vector2 in [Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y)]:
		var hit: Variant = ground.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
		if hit == null or hit.x < -40.0 or hit.x > 128.0 or hit.z < 0.0 or hit.z > 40.0:
			return false
	return true

func train_stays_visible(diorama: SubViewportContainer) -> bool:
	var camera: Camera3D = diorama.camera
	var extent: Vector2 = camera.get_viewport().get_visible_rect().size
	return not camera.is_position_behind(diorama.train.global_position) and Rect2(Vector2.ZERO, extent).has_point(camera.unproject_position(diorama.train.global_position))

func verify_cars(diorama: SubViewportContainer, context: String) -> void:
	var route: Path3D = diorama.world_route
	var curve: Curve3D = route.curve
	var cars: Array[Node] = route.get_children()
	check(cars.size() == 9, context + " retains all nine vehicles")
	for index: int in cars.size():
		var car: PathFollow3D = cars[index]
		check(absf(diorama.train.progress - car.progress - car_offsets[index]) < 0.002, context + " carriage %d keeps its authored coupling distance" % index)
		check(car.position.distance_to(curve.sample_baked(car.progress, car.cubic_interp)) < 0.02, context + " carriage %d stays on the railway through turns and slopes" % index)
		var ahead := curve.sample_baked(car.progress + 0.1)
		var behind := curve.sample_baked(car.progress - 0.1)
		var tangent: Vector3 = (route.global_basis * (ahead - behind)).normalized()
		var model: Node3D = car.get_node("Model")
		check(model.global_basis.x.normalized().dot(tangent) > 0.98, context + " carriage %d faces its own track tangent" % index)

func verify_no_pending() -> void:
	session.campaign_completed_count = 2
	session.campaign_travel_from = -1
	session.set_meta("campaign_selected_stage", 5)
	var atlas: Control = await load_map()
	var diorama: SubViewportContainer = atlas.diorama
	await settle_transition()
	var parked: Vector3 = diorama.train.global_position
	await create_timer(0.25, true, false, true).timeout
	check(not diorama.train_moving and diorama.parked_station == 2, "ordinary saved-game entry parks at the saved station without replaying a trip")
	check(parked.distance_to(diorama.parking_anchors[2].global_position) < 0.03 and diorama.train.global_position.distance_to(parked) < 0.001, "an idle train does not drift while browsing another station")
	check(atlas.selected_index == 5, "ordinary entry preserves the inspected station separately from the train")
	check(atlas.stops[2].get_node("Badge/TrainMarker").visible, "ordinary entry shows the parked train badge immediately")

func verify_blocked_input(atlas: Control) -> void:
	var diorama: SubViewportContainer = atlas.diorama
	var selected: int = atlas.selected_index
	var camera_pose: Transform3D = diorama.camera_rig.transform
	var camera_distance: float = diorama.camera.position.z
	var progress: float = diorama.train.progress
	for shortcut: Key in [KEY_1, KEY_KP_6, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_ENTER]:
		key(shortcut)
	atlas.stops[0].pressed.emit()
	atlas.get_node("%ReturnTrain").pressed.emit()
	var point := Vector2(180, 160)
	mouse(point, MOUSE_BUTTON_WHEEL_UP, true)
	mouse(point, MOUSE_BUTTON_WHEEL_UP, false)
	mouse(point, MOUSE_BUTTON_LEFT, true)
	var drag := InputEventMouseMotion.new()
	drag.position = point + Vector2(200, 80)
	drag.global_position = drag.position
	drag.relative = Vector2(200, 80)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	mouse(drag.position, MOUSE_BUTTON_LEFT, false)
	check(current_scene == atlas and not session.transition.busy, "station clicks and Enter cannot launch a battle while travelling")
	check(atlas.selected_index == selected, "station keys cannot change selection during the trip")
	check(diorama.camera_rig.transform.is_equal_approx(camera_pose) and is_equal_approx(diorama.camera.position.z, camera_distance), "drag, zoom and return-to-train input cannot interrupt the following camera")
	check(is_equal_approx(diorama.train.progress, progress), "navigation input cannot move the train to a station")

func verify_pause(atlas: Control) -> void:
	var diorama: SubViewportContainer = atlas.diorama
	key(KEY_P)
	check(session.settings.is_open(), "settings remains accessible while the train travels")
	var progress: float = diorama.train.progress
	var camera_pose: Transform3D = diorama.camera_rig.transform
	await create_timer(0.35, true, false, true).timeout
	check(diorama.train_moving and is_equal_approx(diorama.train.progress, progress), "settings pauses the trip without silently reaching its destination")
	check(diorama.camera_rig.transform.is_equal_approx(camera_pose), "settings pauses the camera together with the train")
	check(session.campaign_travel_from >= 0, "pausing preserves the pending arrival")
	session.settings.menu.get_node("%Close").pressed.emit()
	await create_timer(0.2, true, false, true).timeout
	check(not session.settings.is_open() and diorama.train.progress > progress, "closing settings resumes actual forward movement")

func verify_leg(source: int) -> void:
	var destination := source + 1
	var context := "trip %d to %d" % [source + 1, destination + 1]
	session.campaign_completed_count = destination
	session.campaign_travel_from = source
	session.set_meta("campaign_selected_stage", 5)
	arrival_events.clear()
	var atlas: Control = await load_map()
	var diorama: SubViewportContainer = atlas.diorama
	diorama.train_arrived.connect(func(index: int): arrival_events.append(index))
	var start := station_offset(diorama, source)
	var finish := station_offset(diorama, destination)
	check(diorama.intro_running and not diorama.train_moving, context + " waits for the map's reveal before departing")
	check(absf(diorama.train.progress - start) < 0.002 and diorama.parked_station == source, context + " enters at the departure platform instead of teleporting to new progress")
	check(session.campaign_travel_from == source, context + " keeps pending travel while the map is covered")
	await settle_transition()
	check(diorama.train_moving and diorama.parked_station == -1, context + " starts continuous travel after the map is revealed")
	check(diorama.train.progress < finish - 1.0, context + " does not jump to the destination on its first visible frame")
	verify_blocked_input(atlas)
	if source == 0:
		await verify_pause(atlas)
	await capture("trip-%d-departure" % (source + 1))
	var before_refresh: float = diorama.train.progress
	session.campaign_progress_changed.emit()
	check(is_equal_approx(diorama.train.progress, before_refresh) and diorama.train_moving, context + " a progress refresh does not park or restart a moving train")
	var previous: float = diorama.train.progress
	var samples := 0
	var advances := 0
	var monotonic := true
	var continuous := true
	var contained := true
	var visible := true
	var badge_waited := true
	var pending_waited := true
	var sample_bin := -1
	var captured_middle := false
	var started_at := Time.get_ticks_msec()
	while diorama.train_moving and Time.get_ticks_msec() - started_at < 20000:
		var progress: float = diorama.train.progress
		monotonic = monotonic and progress >= previous - 0.0001 and progress <= finish + 0.002
		# At least several distinct visible updates are required, including through
		# curves. A single end-position assignment cannot satisfy this check.
		continuous = continuous and progress - previous < (finish - start) * 0.35
		if progress > previous + 0.0001:
			advances += 1
		contained = contained and view_stays_inside(diorama)
		visible = visible and train_stays_visible(diorama)
		badge_waited = badge_waited and atlas.stops.all(func(stop: Button): return not stop.get_node("Badge/TrainMarker").visible)
		pending_waited = pending_waited and session.campaign_travel_from == source
		var ratio := inverse_lerp(start, finish, progress)
		var next_bin := mini(3, floori(ratio * 4.0))
		if next_bin != sample_bin:
			sample_bin = next_bin
			verify_cars(diorama, context + " at %d%%" % roundi(ratio * 100.0))
		if ratio >= 0.45 and not captured_middle:
			captured_middle = true
			await capture("trip-%d-middle" % (source + 1))
		previous = progress
		samples += 1
		await process_frame
	check(not diorama.train_moving, context + " completes within the trip timeout")
	check(samples >= 8 and advances >= 6 and monotonic and continuous, context + " has multiple continuous forward updates rather than a teleport")
	check(contained and visible, context + " camera follows the actual locomotive while every ground corner stays inside the map")
	check(badge_waited and pending_waited, context + " cannot claim a parked station or consume pending travel before arrival")
	check(diorama.parked_station == destination and absf(diorama.train.progress - finish) < 0.002, context + " stops precisely at the next platform")
	check(diorama.train.global_position.distance_to(diorama.parking_anchors[destination].global_position) < 0.03, context + " reaches the authored destination in world space")
	check(arrival_events == [destination], context + " emits one arrival for the destination")
	check(session.campaign_travel_from == -1, context + " consumes pending travel only after arriving")
	check(atlas.selected_index == destination and atlas.stops[destination].selected, context + " selects the new station on arrival")
	check(atlas.stops[destination].get_node("Badge/TrainMarker").visible and atlas.stops.filter(func(stop: Button): return stop.get_node("Badge/TrainMarker").visible).size() == 1, context + " lights only the actual destination's train badge")
	verify_cars(diorama, context + " arrived")
	await capture("trip-%d-arrival" % (source + 1))
	var parked: float = diorama.train.progress
	await create_timer(0.12, true, false, true).timeout
	check(is_equal_approx(diorama.train.progress, parked) and arrival_events.size() == 1, context + " remains stopped without a duplicate arrival")

func verify_interrupted_trip() -> void:
	session.campaign_completed_count = 1
	session.campaign_travel_from = 0
	var atlas: Control = await load_map()
	await settle_transition()
	await create_timer(0.25, true, false, true).timeout
	check(atlas.diorama.train_moving, "interruption fixture departs before leaving")
	var departed_at: float = atlas.diorama.train.progress
	var old_map: WeakRef = weakref(atlas)
	key(KEY_ESCAPE)
	await scene_changed
	await settle_transition()
	check(current_scene.scene_file_path == session.LOBBY_SCENE and old_map.get_ref() == null, "Escape remains available and frees the travelling map")
	check(session.campaign_travel_from == 0, "leaving before arrival preserves the unfinished trip")
	await create_timer(0.2, true, false, true).timeout
	check(session.campaign_travel_from == 0, "a freed map cannot finish its Tween and consume pending travel")
	check(session.back_to_campaign() == OK, "reentering the railway starts normally")
	await scene_changed
	atlas = current_scene
	var diorama: SubViewportContainer = atlas.diorama
	check(diorama.parked_station == 0 and diorama.train.progress < departed_at, "reentry restores the departure station for the unfinished visible journey")
	await settle_transition()
	check(diorama.train_moving and session.campaign_travel_from == 0, "reentry replays the preserved trip instead of teleporting")
	var started_at := Time.get_ticks_msec()
	while diorama.train_moving and Time.get_ticks_msec() - started_at < 20000:
		await process_frame
	check(diorama.parked_station == 1 and session.campaign_travel_from == -1, "the replay consumes its pending trip at the actual arrival")

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	var capture_index := args.find("--capture")
	if capture_index >= 0:
		capture_directory = ProjectSettings.globalize_path(args[capture_index + 1] if capture_index + 1 < args.size() else "res://.local/campaign-train-travel")
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for car: Dictionary in manifest.train.cars:
		car_offsets.append(float(car.offset))
	session = root.get_node("Session")
	var previous := {
		"path": session.campaign_save_path,
		"completed": session.campaign_completed_count,
		"active": session.campaign_active_stage,
		"travel": session.campaign_travel_from,
		"had_selection": session.has_meta("campaign_selected_stage"),
		"selection": session.get_meta("campaign_selected_stage", 0),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/campaign-train-travel"))
	session.campaign_save_path = "res://.local/campaign-train-travel/progress.cfg"
	root.size = Vector2i(1600, 900)
	await verify_no_pending()
	for source: int in 5:
		await verify_leg(source)
	await verify_interrupted_trip()
	session.campaign_save_path = previous.path
	session.campaign_completed_count = previous.completed
	session.campaign_active_stage = previous.active
	session.campaign_travel_from = previous.travel
	if previous.had_selection:
		session.set_meta("campaign_selected_stage", previous.selection)
	else:
		session.remove_meta("campaign_selected_stage")
	print("CAMPAIGN_TRAIN_TRAVEL checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
