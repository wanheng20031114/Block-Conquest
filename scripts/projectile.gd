class_name BattleProjectile
extends Node3D
## Reusable presentation; standalone scenes use the same Flight kernel as the pool.

var flight: ProjectileFlight
var pooled: bool = false
const SMOKE_TAIL_SECONDS: float = 0.24
var _tail_elapsed: float = 0.0
var _source: Node3D:
	get: return flight._source if flight != null else null
var _kind: String:
	get: return flight._kind if flight != null else ""
var _start: Vector3:
	get: return flight._start if flight != null else Vector3.ZERO
var _end: Vector3:
	get: return flight._end if flight != null else Vector3.ZERO
var _duration: float:
	get: return flight._duration if flight != null else 0.0
var _active: bool:
	get: return flight != null and flight._active

@onready var _arrow: Node3D = $Arrow
@onready var _stone: MeshInstance3D = $Stone
@onready var _cannonball: MeshInstance3D = $Cannonball
@onready var _trail: CPUParticles3D = $Trail
@onready var _smoke: MeshInstance3D = $MusketSmoke

func initialize_visual(from: Vector3, to: Vector3, kind: String, duration: float, arc: float, target: Node3D = null) -> void:
	var launched := ProjectileFlight.new()
	launched.initialize_visual(get_tree().current_scene, from, to, kind, duration, arc, target)
	bind_flight(launched)

func initialize(source: Node3D, target: Node3D, payload: DamagePayload, kind: String) -> void:
	var launched := ProjectileFlight.new()
	launched.initialize(get_tree().current_scene, source, target, payload, kind)
	bind_flight(launched)

func bind_flight(launched: ProjectileFlight) -> void:
	flight = launched
	flight.visual = self
	_tail_elapsed = 0.0
	_smoke.hide()
	_arrow.visible = flight._kind in ["arrow", "bolt"]
	_arrow.scale = Vector3(1, 1, .55) if flight._kind == "bolt" else Vector3.ONE
	_stone.visible = flight._kind == "stone"
	_stone.rotation = Vector3.ZERO
	_cannonball.visible = flight._kind in ["cannon", "bullet"]
	_cannonball.scale = Vector3.ONE * .2 if flight._kind == "bullet" else Vector3.ONE
	_trail.hide()
	_trail.emitting = false
	global_position = flight.position
	_face_direction(flight._end - flight._start + Vector3.UP * (4.0 * flight._arc_height))
	if flight._kind == "cannon":
		# Restart clears particles from the previous borrower before showing the trail.
		_trail.restart()
		_trail.emitting = true
		_trail.show()
	visible = flight._game.can_see_position(flight._game.local_owner_id, global_position)
	reset_physics_interpolation()

func present_flight(delta: float) -> void:
	var direction: Vector3 = flight.position - global_position
	global_position = flight.position
	visible = flight._game.can_see_position(flight._game.local_owner_id, global_position)
	_face_direction(direction)
	if flight._kind == "stone":
		_stone.rotate_x(delta * 5.0)
		_stone.rotate_z(delta * 3.0)
	elif flight._kind == "bullet":
		_cannonball.visible = flight._active
		_present_smoke(0.0)

func present_tail(delta: float) -> bool:
	# Keep only the presentation briefly after impact. The Flight is inactive:
	# neither damage nor target tracking is repeated during this cosmetic tail.
	if flight._kind != "bullet":
		return false
	_tail_elapsed += delta
	if _tail_elapsed >= SMOKE_TAIL_SECONDS:
		return false
	visible = flight._game.can_see_position(flight._game.local_owner_id, flight.position)
	_present_smoke(_tail_elapsed / SMOKE_TAIL_SECONDS)
	return true

func _present_smoke(age: float) -> void:
	var direction: Vector3 = flight.position - flight._start
	var length: float = direction.length()
	# A long trail must not reveal its hidden origin through a visible endpoint.
	_smoke.visible = length > 0.01 and visible and flight._game.can_see_position(flight._game.local_owner_id, flight._start)
	if not _smoke.visible:
		return
	var along: Vector3 = direction / length
	var up: Vector3 = Vector3.RIGHT if absf(along.dot(Vector3.UP)) > 0.99 else Vector3.UP
	var across: Vector3 = along.cross(up).normalized()
	var width: float = 0.065
	_smoke.global_transform = Transform3D(Basis(across * width, along * length, across.cross(along) * width), flight._start.lerp(flight.position, 0.5))
	_smoke.set_instance_shader_parameter(&"trace_length", length)
	_smoke.set_instance_shader_parameter(&"smoke_age", age)

func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() <= 0.0001:
		return
	var up := Vector3.RIGHT if absf(direction.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(global_position + direction, up)

func reset_visual() -> void:
	_trail.emitting = false
	_trail.hide()
	_smoke.hide()
	_tail_elapsed = 0.0
	hide()
	flight = null

func _physics_process(delta: float) -> void:
	if pooled:
		return
	if flight == null:
		queue_free()
		return
	if not flight._active:
		# Preserve the final interpolation tick and standalone fixture lifetime.
		if not present_tail(delta): queue_free()
		return
	flight.advance(delta)
	present_flight(delta)

func _impact() -> void:
	flight.impact()
