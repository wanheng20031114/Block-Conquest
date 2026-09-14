class_name RogueArmyBoard
extends Control
## An isolated, authored 3D table. Input changes layouts, never combat units.
signal unit_selected(uid: int)
signal layout_requested(uid: int, layout: Array)

const LIMIT := 12.0
var selected_uid: int = -1
var encounter: String = "outpost"
var _models: Dictionary = {}
var _layouts: Dictionary = {}
var _radii: Dictionary = {}
var _dragging := false
var _drag_offset := Vector3.ZERO
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

func show_formation(roster: Array, map_kind: String, uid: int) -> void:
	_candidate = false
	encounter = map_kind
	selected_uid = uid
	%ArmyBase.visible = encounter == "siege"
	%ArmyFootprint.visible = encounter == "siege"
	%ArmyGround.scale = Vector3.ONE
	$ArmyViewport/World/Table.show()
	_camera.position = Vector3(0, 31, 22)
	_camera.size = _formation_zoom
	_camera.look_at(Vector3.ZERO, Vector3.UP)
	if is_instance_valid(_candidate_model):
		_candidate_model.hide()
	var live_uids: Array[int] = []
	for unit: Dictionary in roster:
		if not bool(unit["deployed"]):
			continue
		var unit_uid := int(unit["uid"])
		live_uids.append(unit_uid)
		if not _models.has(unit_uid):
			_models[unit_uid] = _create_model(str(unit["kind"]))
		var model: UnitVisual = _models[unit_uid]
		model.show()
		var layout: Array = unit["layouts"][encounter]
		_layouts[unit_uid] = layout.duplicate()
		_radii[unit_uid] = BalanceCatalog.unit(str(unit["kind"])).radius
		model.position = Vector3(float(layout[0]), 0, float(layout[1]))
		model.rotation.y = float(layout[2])
	for existing: int in _models.keys():
		if not live_uids.has(existing):
			_models[existing].queue_free()
			_models.erase(existing)
			_layouts.erase(existing)
			_radii.erase(existing)
	_update_marker()
	_refresh_activity()

func show_candidate(kind: String) -> void:
	_candidate = true
	_dragging = false
	%ArmyBase.hide()
	%ArmyFootprint.hide()
	%ArmyMarker.hide()
	%ArmyGround.scale = Vector3(.4, 1, .4)
	$ArmyViewport/World/Table.hide()
	for model: UnitVisual in _models.values():
		model.hide()
	if kind.is_empty():
		if is_instance_valid(_candidate_model):
			_candidate_model.hide()
		_candidate_kind = ""
		_refresh_activity()
		return
	if _candidate_kind != kind or not is_instance_valid(_candidate_model):
		if is_instance_valid(_candidate_model):
			_candidate_model.queue_free()
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

func _update_marker() -> void:
	%ArmyMarker.visible = not _candidate and _models.has(selected_uid)
	if not %ArmyMarker.visible:
		return
	var model: Node3D = _models[selected_uid]
	%ArmyMarker.position = model.position + Vector3(0, .08, 0)
	%ArmyMarker.rotation.y = model.rotation.y
	var radius: float = maxf(.8, float(_radii[selected_uid]) + .25)
	%ArmyRing.scale = Vector3(radius, 1, radius)

func _ground_point(screen_position: Vector2) -> Vector3:
	var viewport_position := screen_position / _surface.size * Vector2(_viewport.size)
	var origin: Vector3 = _camera.project_ray_origin(viewport_position)
	var ray: Vector3 = _camera.project_ray_normal(viewport_position)
	var point: Vector3 = Plane(Vector3.UP, 0).intersects_ray(origin, ray)
	return Vector3(clampf(point.x, -LIMIT, LIMIT), 0, clampf(point.z, -LIMIT, LIMIT))

func _closest_unit(point: Vector3) -> int:
	var closest := -1
	var distance := INF
	for uid: int in _models:
		var candidate_distance: float = point.distance_to(_models[uid].position)
		if candidate_distance < maxf(1.25, float(_radii[uid]) + .5) and candidate_distance < distance:
			distance = candidate_distance
			closest = uid
	return closest

func _on_surface_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var factor := .88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.12
		_camera.size = clampf(_camera.size * factor, 3.0 if _candidate else 13.0, 12.0 if _candidate else 36.0)
		if not _candidate:
			_formation_zoom = _camera.size
		_redraw_once()
		return
	if _candidate:
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and is_instance_valid(_candidate_model):
			_candidate_model.rotation.y += event.relative.x * .015
			_redraw_once()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var picked := _closest_unit(_ground_point(event.position))
				if picked >= 0:
					selected_uid = picked
					_dragging = true
					_drag_offset = _models[picked].position - _ground_point(event.position)
					unit_selected.emit(picked)
					_update_marker()
			elif _dragging:
				_dragging = false
				_commit_position(_ground_point(event.position) + _drag_offset)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _models.has(selected_uid):
			_commit_position(_ground_point(event.position))
	elif event is InputEventMouseMotion and _dragging and _models.has(selected_uid):
		_models[selected_uid].position = _ground_point(event.position) + _drag_offset
		_update_marker()
	_redraw_once()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _candidate:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
		_dragging = false
		_commit_position(_models[selected_uid].position)

func _commit_position(point: Vector3) -> void:
	if not _models.has(selected_uid):
		return
	var yaw: float = float(_layouts[selected_uid][2])
	layout_requested.emit(selected_uid, [snappedf(point.x, .25), snappedf(point.z, .25), yaw])

func _redraw_once() -> void:
	if is_visible_in_tree():
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _on_surface_resized() -> void:
	_viewport.size = Vector2i(maxi(2, int(_surface.size.x)), maxi(2, int(_surface.size.y)))
	_redraw_once()

func _refresh_activity() -> void:
	if not is_node_ready():
		return
	if not is_visible_in_tree():
		_dragging = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
