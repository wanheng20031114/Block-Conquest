extends SceneTree
## Fullscreen railway, centered vector markers, and native station input.

var checks := 0
var failures: Array[String] = []
var capture_directory := ""

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func settle() -> void:
	await create_timer(0.8, true, false, true).timeout

func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func click(button: Button) -> void:
	for down: bool in [true, false]:
		mouse(button.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, down)

func move_mouse(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func key(code: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func capture(name: String) -> void:
	if capture_directory.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(capture_directory.path_join(name + ".png")) == OK, "save " + name)

func view_stays_inside(diorama: SubViewportContainer) -> bool:
	# Independently intersect corner rays with the lowest authored terrain surface.
	var camera: Camera3D = diorama.camera
	var extent: Vector2 = camera.get_viewport().get_visible_rect().size
	var ground := Plane(Vector3.UP, 5.0)
	for corner: Vector2 in [Vector2.ZERO, Vector2(extent.x, 0), extent, Vector2(0, extent.y)]:
		var hit: Variant = ground.intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
		if hit == null or hit.x < -40.0 or hit.x > 128.0 or hit.z < 0.0 or hit.z > 40.0:
			return false
	return true

func check_vector(texture: Texture2D, displayed_pixels: Vector2, context: String) -> void:
	check(texture is DPITexture, context + " keeps native SVG resolution scaling")
	if not texture is DPITexture:
		return
	var vector := texture as DPITexture
	check(vector.get_source().contains("<svg") and vector.base_scale >= 2.0, context + " retains vector source and supersampling")
	var raster := vector.get_image()
	check(raster != null and raster.get_width() >= 128 and raster.get_height() >= 128, context + " has a full-resolution base raster")
	if raster != null:
		check(raster.get_width() >= displayed_pixels.x and raster.get_height() >= displayed_pixels.y, context + " never magnifies a smaller raster at this window size")

func check_marker_layout(stop: Button, context: String) -> void:
	var paper: Polygon2D = stop.get_node("Badge/Paper")
	var bounds := Rect2(paper.polygon[0], Vector2.ZERO)
	for point: Vector2 in paper.polygon:
		bounds = bounds.expand(point)
	var icon: TextureRect = stop.get_node("Badge/StateIcon")
	var paper_center := paper.get_global_transform() * bounds.get_center()
	check(icon.get_global_rect().get_center().is_equal_approx(paper_center), context + " pictogram stays at the hexagon's geometric center")
	var train: Control = stop.get_node("Badge/TrainMarker")
	var train_icon: TextureRect = train.get_node("Icon")
	check(train_icon.get_global_rect().get_center().is_equal_approx(train.get_global_rect().get_center()), context + " train pictogram stays centered in its independent badge")
	check_vector(icon.texture, icon.size * icon.get_screen_transform().get_scale(), context + " state")
	check_vector(train_icon.texture, train_icon.size * train_icon.get_screen_transform().get_scale(), context + " train")

func check_action_layout(action: Button) -> void:
	var context := String(action.name)
	check(action.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and action.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER, context + " centers its native button icon on both axes")
	var normal: StyleBox = action.get_theme_stylebox("normal")
	check(normal is StyleBoxFlat, context + " retains its round paper background")
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style: StyleBox = action.get_theme_stylebox(state)
		check(style is StyleBoxFlat, context + " / " + state + " has an explicit round style")
		if not style is StyleBoxFlat or not normal is StyleBoxFlat:
			continue
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			check(is_equal_approx(style.get_content_margin(side), normal.get_content_margin(side)), context + " / " + state + " preserves content margins")
		check(is_equal_approx(style.get_content_margin(SIDE_LEFT), style.get_content_margin(SIDE_RIGHT)) and is_equal_approx(style.get_content_margin(SIDE_TOP), style.get_content_margin(SIDE_BOTTOM)), context + " / " + state + " cannot shift the pictogram")
		var flat := style as StyleBoxFlat
		var normal_flat := normal as StyleBoxFlat
		for corner: Corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_LEFT, CORNER_BOTTOM_RIGHT]:
			check(flat.get_corner_radius(corner) == normal_flat.get_corner_radius(corner), context + " / " + state + " preserves the round silhouette")

func check_projected_anchor(stop: Button, diorama: SubViewportContainer, index: int, context: String) -> void:
	# The authored marker is centered horizontally and starts 22 UI pixels below
	# its station anchor. Invert the actual canvas transform, then reconstruct the
	# world point from a camera ray; do not compare two copies of stage_position().
	var anchor: Vector3 = diorama.anchors[index].global_position
	var marker_anchor := Vector2(stop.get_global_rect().get_center().x, stop.global_position.y - 22.0)
	var viewport_point := diorama.get_global_transform_with_canvas().affine_inverse() * marker_anchor
	var plane := Plane(Vector3.UP, anchor.y)
	var hit: Variant = plane.intersects_ray(diorama.camera.project_ray_origin(viewport_point), diorama.camera.project_ray_normal(viewport_point))
	check(hit != null and hit.distance_to(anchor) < 0.02, context + " marker recovers the actual 3D station anchor")

func check_marker_input(stop: Button, context: String) -> void:
	# A locked station lets the full native press/release path run without leaving
	# the map. Keep the camera still while exercising the marker's visual lift.
	move_mouse(Vector2(180, 160))
	stop.set_selected(false, false)
	await settle()
	var hit_rect := stop.get_global_rect()
	var badge: Control = stop.get_node("Badge")
	var rest_y := badge.position.y
	move_mouse(stop.get_node("Badge/StateIcon").get_global_rect().get_center())
	await settle()
	check(badge.position.y < rest_y and stop.get_global_rect().is_equal_approx(hit_rect), context + " hover lifts only the artwork, preserving its hit area")
	check(root.gui_get_hovered_control() == stop, context + " hovering the visible icon reaches the native station button")
	stop.set_selected(true)
	await settle()
	check(stop.get_global_rect().is_equal_approx(hit_rect), context + " selected lift preserves its hit area")
	check_marker_layout(stop, context + " raised")
	var icon_center: Vector2 = stop.get_node("Badge/StateIcon").get_global_rect().get_center()
	mouse(icon_center, MOUSE_BUTTON_LEFT, true)
	check(stop.is_pressed(), context + " visible icon center accepts native press")
	mouse(icon_center, MOUSE_BUTTON_LEFT, false)
	check(not stop.is_pressed(), context + " visible icon center releases normally")

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		capture_directory = args[0]
		DirAccess.make_dir_recursive_absolute(capture_directory)
	var session := root.get_node("Session")
	var saved_progress: int = session.campaign_completed_count
	var saved_active: int = session.campaign_active_stage
	var preferences: Dictionary = session.settings.snapshot()
	var content_aspect := root.content_scale_aspect
	var had_selection: bool = session.has_meta("campaign_selected_stage")
	var previous_selection: int = session.get_meta("campaign_selected_stage", 0)
	session.campaign_completed_count = 3
	session.set_meta("campaign_selected_stage", 0)
	change_scene_to_file("res://scenes/campaign/campaign_map.tscn")
	await scene_changed
	while current_scene.diorama.intro_running:
		await process_frame
	await settle()
	var atlas: Control = current_scene
	var diorama: SubViewportContainer = atlas.diorama
	check(atlas.stops.size() == 6, "six projected station buttons remain playable")
	check(atlas.selected_index == 0 and atlas.stops[0].visible, "returning to an inspected station keeps selection and camera together")
	for index: int in atlas.stops.size():
		var stop: Button = atlas.stops[index]
		check(not stop.has_node("State"), "station state no longer uses a permanent text label")
		check(stop.get_node("Caption").visible == (index == 0), "only the selected station keeps its name visible at rest")
		check(stop.tooltip_text.split("\n").size() == 1 and not stop.tooltip_text.contains(stop.stage.title), "station hint keeps one necessary action without duplicating the visible name")
		var expected_icon := "station_complete.svg" if index < 3 else ("station_battle.svg" if index == 3 else "station_locked.svg")
		check(stop.get_node("Badge/StateIcon").texture.resource_path.ends_with(expected_icon), "station state has an unambiguous pictogram")
		check_marker_layout(stop, "station %d" % (index + 1))
		check(stop.get_node("Badge/TrainMarker").visible == (index == 3), "train location uses an independent visual badge")
	session.campaign_completed_count = 6
	session.campaign_progress_changed.emit()
	check(atlas.stops[5].get_node("Badge/TrainMarker").visible and atlas.stops[5].get_node("Badge/StateIcon").texture.resource_path.ends_with("station_complete.svg"), "final victory shows completion and train location together")
	session.campaign_completed_count = 3
	session.campaign_progress_changed.emit()
	for control_name: String in ["Back", "Settings", "ReturnTrain"]:
		var action: Button = atlas.get_node("%" + control_name)
		check(action.text.is_empty() and action.icon != null, control_name + " uses an icon instead of permanent text")
		check(not action.tooltip_text.is_empty(), control_name + " keeps a concise discoverable hint")
		check_action_layout(action)
	for removed: String in ["Header", "Footer", "Details", "StationShortcuts", "CameraControls", "ExploreHint", "IntroHint"]:
		check(atlas.find_child(removed, true, false) == null, "fullscreen map removes " + removed)
	check(diorama.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "railway retains perspective scenery")
	var parked_at: Vector3 = diorama.train.global_position
	check(parked_at.distance_to(diorama.parking_anchors[3].global_position) < 0.05, "train remains at the saved progress station")
	for resolution: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1920, 820), Vector2i(1440, 1080), Vector2i(2560, 1440)]:
		root.size = resolution
		await settle()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().get_size() == resolution, "rendering covers the full window without letterboxing at " + str(resolution))
		check(diorama.get_global_rect().is_equal_approx(atlas.get_global_rect()), "map fills viewport at " + str(resolution))
		check(atlas.get_node("%MapInput").get_global_rect().is_equal_approx(atlas.get_global_rect()), "map input covers the entire screen")
		check(Vector2(diorama.get_node("World").size).is_equal_approx(diorama.size), "3D viewport follows the actual aspect ratio")
		for control_name: String in ["Back", "Settings", "ReturnTrain"]:
			var action: Button = atlas.get_node("%" + control_name)
			check(atlas.get_global_rect().encloses(action.get_global_rect()), "floating " + control_name + " stays inside the screen")
			var drawn_size := Vector2.ONE * action.get_theme_constant("icon_max_width") * action.get_screen_transform().get_scale()
			check_vector(action.icon, drawn_size, control_name + " at " + str(resolution))
			move_mouse(action.get_global_rect().get_center())
			mouse(action.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)
			await process_frame
			# Native momentary buttons report DRAW_PRESSED even while hovered;
			# DRAW_HOVER_PRESSED is reserved for the toggled button state.
			check(action.get_draw_mode() == BaseButton.DRAW_PRESSED and action.is_hovered() and action.is_pressed(), control_name + " holds its round pressed style under the pointer during native input")
			if resolution.x in [1600, 2560]:
				await capture("campaign-%s-pressed-%d" % [control_name.to_lower(), resolution.x])
			# Cancel the click outside the button so testing Back/Settings cannot
			# navigate away or open a modal before the resolution checks finish.
			move_mouse(Vector2(180, 160))
			mouse(Vector2(180, 160), MOUSE_BUTTON_LEFT, false)
			check(current_scene == atlas and not session.settings.is_open(), control_name + " canceled press stays on the map")
		for index: int in 6:
			key((KEY_1 + index) as Key)
			var contained := true
			for frame: int in 18:
				await process_frame
				contained = contained and view_stays_inside(diorama)
			# A fixed frame count can finish before the 0.65-second camera tween
			# on a fast GPU. Check containment through its actual completion before
			# asking whether the destination marker is on screen.
			while diorama._view_tween.is_running():
				await process_frame
				contained = contained and view_stays_inside(diorama)
			await process_frame
			check(contained, "station %d tween stays inside map at %s" % [index + 1, resolution])
			check(atlas.selected_index == index, "number key selects station %d" % (index + 1))
			check(atlas.stops[index].visible, "focused station is reachable on screen")
			check(atlas.stops[index].completed == (index < 3), "completed badge follows progress")
			check(atlas.stops[index].unlocked == (index <= 3), "station availability follows progress")
			check(atlas.stops.filter(func(stop: Button): return stop.selected).size() == 1, "exactly one station is selected")
			check(is_equal_approx(diorama.camera.position.z, diorama.maximum_distance()), "default view uses the maximum covered vertical extent")
			check_projected_anchor(atlas.stops[index], diorama, index, "station %d at %s" % [index + 1, resolution])
			check_marker_layout(atlas.stops[index], "station %d at %s" % [index + 1, resolution])
			if resolution.x == 1600 and index in [0, 3, 5]:
				await capture("campaign-station-%d" % (index + 1))
		await settle()
		await check_marker_input(atlas.stops[5], "locked station at " + str(resolution))
		check(current_scene == atlas and atlas.selected_index == 5, "clicking the raised locked pictogram keeps the map and correct station selected")
		for steps: float in [-100.0, 100.0]:
			diorama.zoom_view(steps)
			for delta: Vector2 in [Vector2(-100000, -100000), Vector2(100000, -100000), Vector2(100000, 100000), Vector2(-100000, 100000)]:
				diorama.pan_view(delta)
				check(view_stays_inside(diorama), "extreme zoom/drag cannot expose map edges at " + str(resolution))
		check(is_equal_approx(diorama.camera.position.z, diorama.maximum_distance()), "zooming out stops at map height")
		check(diorama.train.global_position.distance_to(parked_at) < 0.02, "browsing never moves the progress train")
		diorama.focus_station(0, false)
		await settle()
		await capture("campaign-fullscreen-%d" % resolution.x)
	root.size = Vector2i(1600, 900)
	await settle()
	click(atlas.get_node("%ReturnTrain"))
	await settle()
	check(atlas.selected_index == 3 and atlas.stops[3].visible, "train icon returns to the current station without starting battle")
	check(diorama.train.global_position.distance_to(parked_at) < 0.02, "train navigation icon only moves the view")
	var hover := InputEventMouseMotion.new()
	hover.position = atlas.stops[2].get_global_rect().get_center()
	hover.global_position = hover.position
	root.push_input(hover, true)
	await settle()
	check(atlas.stops[2].get_node("Caption").visible, "hover reveals the nearby station name without changing selection")
	check(atlas.selected_index == 3, "hover preserves the selected destination")
	await capture("campaign-hover-hint")
	hover = InputEventMouseMotion.new()
	hover.position = Vector2(180, 160)
	hover.global_position = hover.position
	root.push_input(hover, true)
	await settle()
	check(not atlas.stops[2].get_node("Caption").visible, "leaving the station hides its optional name again")
	await capture("campaign-visual-language")
	key(KEY_3)
	await settle()
	var middle := Vector2(180, 160)
	var distance_before: float = diorama.camera.position.z
	mouse(middle, MOUSE_BUTTON_WHEEL_UP, true)
	mouse(middle, MOUSE_BUTTON_WHEEL_UP, false)
	check(diorama.camera.position.z < distance_before, "wheel input zooms the landscape")
	var target_before: Vector3 = diorama.camera_rig.position
	mouse(middle, MOUSE_BUTTON_LEFT, true)
	var drag := InputEventMouseMotion.new()
	drag.position = middle + Vector2(100, 20)
	drag.global_position = drag.position
	drag.relative = Vector2(100, 20)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(drag, true)
	mouse(drag.position, MOUSE_BUTTON_LEFT, false)
	check(diorama.camera_rig.position.distance_to(target_before) > 1.0, "drag input browses the map")
	check(view_stays_inside(diorama), "mouse browsing stays within terrain")
	key(KEY_KP_6)
	await settle()
	click(atlas.stops[5])
	key(KEY_ENTER)
	await settle()
	check(current_scene == atlas, "locked station cannot launch by click or Enter")
	key(KEY_LEFT)
	await settle()
	check(atlas.selected_index == 4, "left arrow selects the previous station")
	key(KEY_RIGHT)
	await settle()
	check(atlas.selected_index == 5, "right arrow selects the next station")
	key(KEY_P)
	await settle()
	check(session.settings.is_open(), "P opens settings without a top bar")
	check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_DISABLED, "settings pauses map rendering")
	key(KEY_1)
	check(atlas.selected_index == 5, "settings blocks station hotkeys")
	click(session.settings.menu.get_node("%Close"))
	await settle()
	check(diorama.get_node("World").render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE, "closing settings resumes map rendering")
	click(atlas.get_node("%Settings"))
	await settle()
	check(session.settings.is_open(), "gear icon opens settings")
	click(session.settings.menu.get_node("%Close"))
	await settle()
	key(KEY_1)
	await settle()
	click(atlas.stops[0])
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == session.COMMANDER_SCENE and session.campaign_active_stage == 0, "clicking an unlocked station opens its commander selection")
	session.back_to_campaign()
	await scene_changed
	await settle()
	key(KEY_2)
	await settle()
	key(KEY_ENTER)
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == session.COMMANDER_SCENE and session.campaign_active_stage == 1, "Enter launches the keyboard-selected station")
	session.back_to_campaign()
	await scene_changed
	await settle()
	click(current_scene.get_node("%Back"))
	await scene_changed
	await settle()
	check(current_scene.scene_file_path == "res://scenes/lobby.tscn", "back icon returns to the lobby")
	check(root.content_scale_aspect == content_aspect, "leaving the railway restores other menus' scaling")
	check(current_scene.get_node("%Campaign").has_focus(), "lobby restores campaign entry focus")
	check(session.settings.snapshot() == preferences, "browsing preserves preferences")
	check(session.campaign_completed_count == 3, "browsing and commander selection preserve progress")
	session.campaign_completed_count = saved_progress
	session.campaign_active_stage = saved_active
	if had_selection:
		session.set_meta("campaign_selected_stage", previous_selection)
	else:
		session.remove_meta("campaign_selected_stage")
	print("CAMPAIGN_MAP checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
