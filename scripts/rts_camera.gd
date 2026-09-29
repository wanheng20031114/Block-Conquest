extends Node3D

@export var pan_speed: float = 25.0
@export var minimum_zoom: float = 16.0
@export var maximum_zoom: float = 62.0
@export var keyboard_pan: bool = true
@onready var camera: Camera3D = $Camera3D
@onready var settings: GameSettings = get_node("/root/Session/Settings")
var destination: Vector3
var zoom_target: float = 37.0
var dragging: bool = false
var edge_scroll: bool = true
# The scenery border also covers the lower river surface and antialiasing.
# At the authored 52-degree tilt, water at y=-1.18 projects 0.93m farther out.
const BOUNDARY_MARGIN := 2.0
var _view_bounds: Rect2

func _ready() -> void:
	destination = position
	zoom_target = camera.size

func configure_bounds(bounds: Rect2) -> void:
	assert(camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	_view_bounds = bounds.grow(-BOUNDARY_MARGIN)
	get_viewport().size_changed.connect(_constrain_view)
	_constrain_view()

func _process(delta: float) -> void:
	if get_tree().paused or settings.is_open() or get_parent()._local_menu or get_parent().hud.help_visible():
		return
	var direction := Vector3.ZERO
	if keyboard_pan:
		direction.x = Input.get_axis("war_pan_left", "war_pan_right")
		direction.z = Input.get_axis("war_pan_up", "war_pan_down")
	if edge_scroll and settings.edge_scroll_enabled and not dragging and DisplayServer.window_is_focused():
		# Native window pixels include letterbox margins; viewport coordinates do not.
		var local_mouse := Vector2(DisplayServer.mouse_get_position() - DisplayServer.window_get_position())
		var window_size := Vector2(DisplayServer.window_get_size())
		var edge := edge_direction(local_mouse, window_size)
		direction += Vector3(edge.x, 0.0, edge.y)
	if direction.length_squared() > 0.0:
		var right := camera.global_basis.x
		var down := Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
		destination += (right * direction.x + down * direction.z).normalized() * pan_speed * settings.camera_speed * (zoom_target / 37.0) * delta
	position = position.lerp(destination, 1.0 - exp(-12.0 * delta))
	camera.size = lerpf(camera.size, zoom_target, 1.0 - exp(-13.0 * delta))
	# Constrain the rendered frame too: pan and zoom ease at different rates.
	_constrain_view()

func clamp_destination() -> void:
	_constrain_view()

func _constrain_view() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return # Minimized windows have no visible footprint to constrain.
	var first := _ground_at(Vector2.ZERO) - global_position
	var footprint := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for screen: Vector2 in [Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var point := _ground_at(screen) - global_position
		footprint = footprint.expand(Vector2(point.x, point.z))
	# In an orthogonal projection the footprint scales linearly with size.
	# Its centre can be offset from the rig by the authored camera transform.
	var old_zoom := camera.size
	var fit_zoom := old_zoom * minf(_view_bounds.size.x / footprint.size.x, _view_bounds.size.y / footprint.size.y)
	var upper_zoom := minf(maximum_zoom, fit_zoom)
	var lower_zoom := minf(minimum_zoom, upper_zoom)
	zoom_target = clampf(zoom_target, lower_zoom, upper_zoom)
	camera.size = clampf(camera.size, lower_zoom, upper_zoom)
	var centre := footprint.get_center()
	var half_extent := footprint.size * 0.5 / old_zoom
	destination = _clamp_focus(destination, centre, half_extent * zoom_target)
	position = _clamp_focus(position, centre, half_extent * camera.size)

func _clamp_focus(point: Vector3, centre: Vector2, half_extent: Vector2) -> Vector3:
	# Keep the existing playable focus area; woodland only frames the battle.
	point = get_parent().clamp_to_map(point)
	var lower := _view_bounds.position + half_extent - centre
	# At maximum zoom a range can collapse; suppress floating-point inversion.
	var upper := (_view_bounds.end - half_extent - centre).max(lower)
	return Vector3(clampf(point.x, lower.x, upper.x), 0.0, clampf(point.z, lower.y, upper.y))

func _ground_at(screen: Vector2) -> Vector3:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func edge_direction(mouse: Vector2, window_size: Vector2) -> Vector2:
	# The focused window keeps scrolling when the pointer crosses its border.
	# Global desktop coordinates above remain available outside the client area.
	var edge_width := clampf(window_size.y / 75.0, 10.0, 20.0)
	return Vector2(float(mouse.x >= window_size.x - edge_width) - float(mouse.x <= edge_width), float(mouse.y >= window_size.y - edge_width) - float(mouse.y <= edge_width))

func focus_at(world: Vector3, instant: bool = false) -> void:
	destination = Vector3(world.x, 0.0, world.z)
	clamp_destination()
	if instant:
		position = destination
		_constrain_view()

func zoom_by(amount: float) -> void:
	zoom_target += amount * settings.zoom_speed
	_constrain_view()

func drag_by(relative: Vector2) -> void:
	var centre := get_viewport().get_visible_rect().size * 0.5
	var origin := _ground_at(centre)
	# Orthographic pixel vectors remain valid even for a fast drag far outside
	# the window, where projecting the full relative offset could miss the plane.
	var right := _ground_at(centre + Vector2.RIGHT) - origin
	var down := _ground_at(centre + Vector2.DOWN) - origin
	destination -= (right * relative.x + down * relative.y) * settings.camera_speed
	clamp_destination()

func world_at(screen: Vector2) -> Vector3:
	var ground := Plane(Vector3.UP, 0.0)
	var point = ground.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null:
		return Vector3.ZERO
	return get_parent().clamp_to_map(point)
