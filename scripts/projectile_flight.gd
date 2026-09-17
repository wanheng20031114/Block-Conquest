class_name ProjectileFlight
extends RefCounted
## One reusable authoritative record, independent of visual capacity. Snapshots
## survive source death; target armor is read at impact, in one shared damage path.

static var _shared_blast_query: PhysicsShapeQueryParameters3D
static var _blast_query_capacity: int = 64
var _source: Node3D
var _target: Node3D
var _payload: DamagePayload
var _kind: String = ""
var _start: Vector3
var _end: Vector3
var _elapsed: float = 0.0
var _duration: float = 1.0
var _arc_height: float = 1.0
var _active: bool = false
var retiring: bool = false
var _game: Node3D
var _visual_only: bool = false
var collision_mask: int = 0
var position: Vector3
var visual: Node3D

func initialize_visual(game: Node3D, from: Vector3, to: Vector3, kind: String, duration: float, arc: float, target: Node3D) -> void:
	_game = game
	_visual_only = true
	_start = from
	_end = to
	_kind = kind
	_duration = duration
	_arc_height = arc
	_target = target
	position = from
	_active = true

func initialize(game: Node3D, source: Node3D, target: Node3D, payload: DamagePayload, kind: String, barrel_index: int = 0) -> void:
	_game = game
	_source = source
	_target = target
	_payload = payload
	_kind = kind
	collision_mask = CombatLayers.hostile_entities(payload.alliance_id)
	_start = source.get_projectile_origin() if barrel_index == 0 else source.get_projectile_origin(barrel_index)
	_end = target.global_position + Vector3.UP * (2.0 if target.is_in_group("buildings") else 1.0)
	if source is BattleBuilding and source.artillery == null:
		_start += (_end - _start).normalized() * source.radius * 0.7
	var distance: float = _start.distance_to(_end)
	match kind:
		"arrow":
			_duration = clampf(distance / 22.0, 0.18, 0.9)
			_arc_height = clampf(distance * 0.12, 0.35, 2.0)
		"bolt":
			_duration = clampf(distance / 25.0, 0.15, 0.85)
			_arc_height = 0.13
		"bullet":
			_duration = clampf(distance / 55.0, 0.06, 0.35)
			_arc_height = 0.0
		"stone":
			_duration = clampf(distance / 11.0, 0.75, 2.2)
			_arc_height = clampf(distance * 0.42, 3.5, 9.0)
		"cannon":
			_duration = clampf(distance / 25.0, 0.15, 0.85)
			_arc_height = 0.13
	position = _start
	_active = true

func advance(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	var progress: float = minf(1.0, _elapsed / _duration)
	if _kind in ["arrow", "bolt", "bullet", "cannon"] and is_instance_valid(_target) and _target.alive:
		_end = _target.global_position + Vector3.UP * (2.0 if _target.is_in_group("buildings") else 1.0)
	position = _start.lerp(_end, progress)
	position.y += 4.0 * _arc_height * progress * (1.0 - progress)
	if progress >= 1.0:
		impact()

func impact() -> void:
	if not _active:
		return
	_active = false
	if _visual_only:
		return
	var damage_source: Node3D = _source if is_instance_valid(_source) else null
	if _payload.splash_radius > 0.0:
		if _game.is_authority:
			_apply_blast(damage_source)
		if _kind == "stone":
			_game.spawn_effect(_end - Vector3.UP * 0.7, "stone_hit", Color("efbb76"))
		else:
			_game.spawn_effect(_end, "explosion", Color("ead098"))
		return
	if _kind in ["arrow", "bolt", "bullet", "cannon"]:
		var impact_kind: String = "explosion" if _kind == "cannon" else ("bullet_hit" if _kind == "bullet" else "arrow_hit")
		var impact_at: Vector3 = _end
		if _kind == "bullet" and is_instance_valid(_target):
			# Surface feedback stays visible outside armor; flight timing and damage
			# retain the shared center-target contract. Sample before death callbacks.
			if _target.is_in_group("buildings"):
				impact_at = _target.get_attack_position(_start) + Vector3.UP * 2.0
			else:
				impact_at += (_start - _end).normalized() * _target.radius
		if is_instance_valid(_target) and _target.alive and _target.alliance_id != _payload.alliance_id:
			if _kind in ["arrow", "bolt"] and _target.is_in_group("buildings"):
				impact_kind = _target.get_hit_effect()
			if _game.is_authority:
				_target.receive_hit(_payload, damage_source)
		_game.spawn_effect(impact_at, impact_kind, Color("ead098"))

func _apply_blast(damage_source: Node3D) -> void:
	# A launch-time snapshot keeps different explosives independent, including
	# after their source dies. The query is reused only before damage callbacks.
	var payload := _payload
	var impact_at := _end
	if _shared_blast_query == null:
		_shared_blast_query = PhysicsShapeQueryParameters3D.new()
		_shared_blast_query.shape = SphereShape3D.new()
	_shared_blast_query.shape.radius = payload.splash_radius + 0.25
	_shared_blast_query.collision_mask = collision_mask
	_shared_blast_query.transform.origin = Vector3(impact_at.x, 1.0, impact_at.z)
	var space := _game.get_world_3d().direct_space_state
	var hits := space.intersect_shape(_shared_blast_query, _blast_query_capacity)
	# Normal blasts issue one local query. Grow only when saturated: presentation
	# budgets and query limits must never silently drop authoritative damage.
	while hits.size() == _blast_query_capacity:
		_blast_query_capacity *= 2
		hits = space.intersect_shape(_shared_blast_query, _blast_query_capacity)
	var damaged: Dictionary = {}
	for hit: Dictionary in hits:
		var entity: Node3D = hit.collider
		if not is_instance_valid(entity) or not entity.alive or entity.alliance_id == payload.alliance_id or damaged.has(hit.collider_id):
			continue
		var building: bool = entity.is_in_group("buildings")
		var contact: Vector3 = entity.get_attack_position(impact_at) if building else entity.global_position
		var separation: Vector3 = contact - impact_at
		separation.y = 0.0
		var reach: float = payload.splash_radius + (0.0 if building else entity.radius)
		var distance_squared := separation.length_squared()
		if distance_squared <= reach * reach or is_equal_approx(distance_squared, reach * reach):
			damaged[hit.collider_id] = true
			entity.receive_hit(payload, damage_source)

func reset() -> void:
	# Idle records must not retain entities, world roots, or attack snapshots.
	_source = null
	_target = null
	_payload = null
	_game = null
	visual = null
	_kind = ""
	_start = Vector3.ZERO
	_end = Vector3.ZERO
	position = Vector3.ZERO
	_elapsed = 0.0
	_duration = 1.0
	_arc_height = 1.0
	_active = false
	_visual_only = false
	retiring = false
	collision_mask = 0
