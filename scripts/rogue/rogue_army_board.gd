class_name RogueArmyBoard
extends Control
## An isolated authored 3D table with native picking and atomic formation gestures.
signal selection_changed(uids: Array)
signal unit_activated(uid: int)
signal layouts_requested(changes: Array)

const MARKER := preload("res://scenes/rogue/army_unit_marker.tscn")
const DRAG_THRESHOLD := 6.0
var selected_uids: Array[int] = []
var encounter: String = "outpost"
var _models: Dictionary = {}
var _markers: Dictionary = {}
var _layouts: Dictionary = {}
var _radii: Dictionary = {}
var _gesture := ""
var _press_screen := Vector2.ZERO
var _press_ground := Vector3.ZERO
var _start_layouts: Dictionary = {}
var _box_additive: Array[int] = []
var _candidate := false
var _candidate_kind := ""
var _candidate_model: UnitVisual
var _formation_zoom := 27.0

@onready var _viewport: SubViewport = %ArmyViewport
@onready var _camera: Camera3D = %ArmyCamera
@onready var _surface: TextureRect = %ArmySurface

func _ready() -> void:
	_surface.texture = _viewport.get_texture()
	_surface.gui_input.connect(_on_surface_input)
	_surface.resized.connect(_on_surface_resized)
	visibility_changed.connect(_refresh_activity)
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	_refresh_activity()
	_on_surface_resized.call_deferred()

func show_formation(roster: Array, map_kind: String, uids: Array) -> void:
	_candidate = false
	encounter = map_kind
	selected_uids.assign(uids)
	%ArmyBase.visible = encounter == "siege"
	%ArmyFootprint.visible = encounter == "siege"
	%ArmyGround.scale = Vector3.ONE
	$ArmyViewport/World/Table.show()
	_camera.position = Vector3(0, 31, 22)
	_camera.size = _formation_zoom
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	if is_instance_valid(_candidate_model): _candidate_model.hide()
	var live_uids: Array[int] = []
	for unit: Dictionary in roster:
		if not bool(unit.deployed): continue
		var uid := int(unit.uid)
		live_uids.append(uid)
		if not _models.has(uid):
			_models[uid] = _create_model(str(unit.kind))
			var marker: Node3D = MARKER.instantiate()
			%ArmyMarkers.add_child(marker)
			marker.get_node("PickArea").set_meta("uid", uid)
			var shape: CylinderShape3D = marker.get_node("PickArea/CollisionShape3D").shape
			shape.radius = maxf(.65, BalanceCatalog.unit(str(unit.kind)).radius)
			_markers[uid] = marker
		var model: UnitVisual = _models[uid]
		model.show()
		_markers[uid].show()
		var layout: Array = unit.layouts[encounter]
		_layouts[uid] = layout.duplicate()
		_radii[uid] = BalanceCatalog.unit(str(unit.kind)).radius
		model.position = Vector3(float(layout[0]), 0, float(layout[1]))
		model.rotation.y = float(layout[2])
	for uid: int in _models.keys():
		if uid not in live_uids:
			_models[uid].queue_free()
			_markers[uid].queue_free()
			_models.erase(uid)
			_markers.erase(uid)
			_layouts.erase(uid)
			_radii.erase(uid)
	_update_markers()
	_refresh_activity()

func show_candidate(kind: String) -> void:
	cancel_gesture()
	_candidate = true
	%ArmyBase.hide()
	%ArmyFootprint.hide()
	%ArmyGround.scale = Vector3(.4, 1, .4)
	$ArmyViewport/World/Table.hide()
	for model: UnitVisual in _models.values(): model.hide()
	for marker: Node3D in _markers.values(): marker.hide()
	if kind.is_empty():
		if is_instance_valid(_candidate_model): _candidate_model.hide()
		_candidate_kind = ""
		_refresh_activity()
		return
	if _candidate_kind != kind or not is_instance_valid(_candidate_model):
		if is_instance_valid(_candidate_model): _candidate_model.queue_free()
		_candidate_model = _create_model(kind)
		_candidate_kind = kind
	_candidate_model.show()
	_candidate_model.position = Vector3.ZERO
	_candidate_model.rotation.y = PI + .35
	var frame: float = 7.0 if kind in ["war_elephant", "heavy_cannon", "catapult"] else (5.8 if kind in ["spearman", "knight", "light_cavalry"] else 4.6)
	_camera.position = Vector3(7, 5.5, 9)
	_camera.size = frame
	_camera.look_at(Vector3(0, 1, 0), Vector3.UP)
	_refresh_activity()

func _create_model(kind: String) -> UnitVisual:
	var scene: PackedScene = load("res://assets/models/units/%s.tscn" % kind)
	var model: UnitVisual = scene.instantiate()
	%ArmyModels.add_child(model)
	model.set_team(0)
	model.locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.attack.stop()
	model.locomotion.play("idle")
	model.locomotion.seek(.35, true)
	model.process_mode = Node.PROCESS_MODE_DISABLED
	return model

func _update_markers() -> void:
	for uid: int in _markers:
		var marker: Node3D = _markers[uid]
		var model: Node3D = _models[uid]
		marker.position = model.position
		marker.rotation.y = model.rotation.y
		marker.get_node("Selection").visible = uid in selected_uids
		var radius: float = maxf(.8, float(_radii[uid]) + .25)
		marker.get_node("Selection").scale = Vector3(radius, 1, radius)

func _viewport_position(point: Vector2) -> Vector2:
	return point / _surface.size * Vector2(_viewport.size)

func _ground_point(screen_position: Vector2) -> Vector3:
	var position := _viewport_position(screen_position)
	return Plane(Vector3.UP, 0).intersects_ray(_camera.project_ray_origin(position), _camera.project_ray_normal(position))

func _screen_point(point: Vector3) -> Vector2:
	return _camera.unproject_position(point) / Vector2(_viewport.size) * _surface.size

func _pick_unit(screen_position: Vector2) -> int:
	var position := _viewport_position(screen_position)
	var origin := _camera.project_ray_origin(position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + _camera.project_ray_normal(position) * 120.0, 1)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = _viewport.find_world_3d().direct_space_state.intersect_ray(query)
	return -1 if hit.is_empty() else int(hit.collider.get_meta("uid"))

func _on_surface_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		cancel_gesture()
		var factor := .88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
		_camera.size = clampf(_camera.size * factor, 3.0 if _candidate else 22.0, 12.0 if _candidate else 40.0)
		if not _candidate: _formation_zoom = _camera.size
		_redraw_once()
		_surface.accept_event()
		return
	if _candidate:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and is_instance_valid(_candidate_model):
			_candidate_model.rotation.y += event.relative.x * .015
			_redraw_once()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_pointer(event)
			else: _finish_pointer(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			cancel_gesture()
			var center := _selection_center()
			if not _start_layouts.is_empty(): _commit_translation(_ground_point(event.position) - center)
			_start_layouts.clear()
		_surface.accept_event()
	elif event is InputEventMouseMotion and has_gesture():
		_move_pointer(event.position)
		_surface.accept_event()
	_redraw_once()

func _begin_pointer(event: InputEventMouseButton) -> void:
	cancel_gesture()
	var picked := _pick_unit(event.position)
	if event.double_click and picked >= 0:
		unit_activated.emit(picked)
		return
	_press_screen = event.position
	_press_ground = _ground_point(event.position)
	var additive := event.shift_pressed or event.ctrl_pressed
	if picked >= 0:
		var next: Array[int] = selected_uids.duplicate()
		if additive:
			if picked in next: next.erase(picked)
			else: next.append(picked)
		elif picked not in next:
			next = [picked]
		selected_uids = next
		selection_changed.emit(next)
		if picked in selected_uids:
			_selection_center()
			_gesture = "pending_move"
	else:
		_box_additive.clear()
		if additive: _box_additive.assign(selected_uids)
		_gesture = "pending_box"

func _move_pointer(point: Vector2) -> void:
	if _gesture.begins_with("pending") and point.distance_to(_press_screen) < DRAG_THRESHOLD: return
	if _gesture in ["pending_move", "move"]:
		_gesture = "move"
		var delta := _snapped_delta(_ground_point(point) - _press_ground)
		for uid: int in _start_layouts:
			var layout: Array = _start_layouts[uid]
			_models[uid].position = Vector3(float(layout[0]), 0, float(layout[1])) + delta
		_update_markers()
	elif _gesture in ["pending_box", "box"]:
		_gesture = "box"
		var rectangle := Rect2(_press_screen, point - _press_screen).abs()
		%SelectionBox.position = rectangle.position
		%SelectionBox.size = rectangle.size
		%SelectionBox.show()
		var next: Array[int] = _box_additive.duplicate()
		for uid: int in _models:
			if rectangle.has_point(_screen_point(_models[uid].position)) and uid not in next:
				next.append(uid)
		selected_uids = next
		selection_changed.emit(next)
	_redraw_once()

func _finish_pointer(point: Vector2) -> void:
	var gesture := _gesture
	_gesture = ""
	%SelectionBox.hide()
	if gesture == "move":
		_commit_translation(_ground_point(point) - _press_ground)
	elif gesture == "pending_box":
		selected_uids = _box_additive.duplicate()
		selection_changed.emit(selected_uids)
	_start_layouts.clear()
	_redraw_once()

func _selection_center() -> Vector3:
	_start_layouts.clear()
	var center := Vector3.ZERO
	for uid: int in selected_uids:
		if not _models.has(uid): continue
		_start_layouts[uid] = _layouts[uid].duplicate()
		center += _models[uid].position
	return center / _start_layouts.size() if not _start_layouts.is_empty() else center

func _snapped_delta(delta: Vector3) -> Vector3:
	return Vector3(snappedf(delta.x, .25), 0, snappedf(delta.z, .25))

func _commit_translation(delta: Vector3) -> void:
	var offset := _snapped_delta(delta)
	if offset.is_zero_approx(): return
	var changes: Array = []
	for uid: int in _start_layouts:
		var layout: Array = _start_layouts[uid]
		changes.append({"uid": uid, "layout": [float(layout[0]) + offset.x, float(layout[1]) + offset.z, float(layout[2])]})
	layouts_requested.emit(changes)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _candidate or not has_gesture(): return
	# GUI keeps drags captured. A release outside the surface still commits once.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not _surface.get_global_rect().has_point(event.position):
		_finish_pointer(_surface.get_global_transform().affine_inverse() * event.position)
		get_viewport().set_input_as_handled()

func has_gesture() -> bool:
	return not _gesture.is_empty()

func cancel_gesture() -> void:
	_gesture = ""
	_start_layouts.clear()
	%SelectionBox.hide()
	for uid: int in _models:
		var layout: Array = _layouts[uid]
		_models[uid].position = Vector3(float(layout[0]), 0, float(layout[1]))
		_models[uid].rotation.y = float(layout[2])
	_update_markers()
	_redraw_once()

func _redraw_once() -> void:
	if is_visible_in_tree(): _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _on_surface_resized() -> void:
	cancel_gesture()
	_viewport.size = Vector2i(maxi(2, int(_surface.size.x)), maxi(2, int(_surface.size.y)))
	_redraw_once()

func _refresh_activity() -> void:
	if not is_node_ready(): return
	if not is_visible_in_tree(): cancel_gesture()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
