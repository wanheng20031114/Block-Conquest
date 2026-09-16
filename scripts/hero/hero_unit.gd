class_name HeroUnit
extends BattleUnit
## The same battle entity switches intent providers; its collision never jumps.
signal shot_resolved(hit: Dictionary)
const BODY_LAYER := 1 << 18
const EYE_HEIGHT := 2.23
const JUMP_SECONDS := .65
const JUMP_HEIGHT := .45
var directly_controlled: bool = false
var move_input := Vector3.ZERO
var aim_direction := Vector3.FORWARD
var trigger_held: bool = false
var jump_time: float = JUMP_SECONDS
var jump_offset: float = 0.0
var previous_jump_offset: float = 0.0
var speed_boost_remaining: float = 0.0
var speed_boost_multiplier: float = 1.2
var _ray := PhysicsRayQueryParameters3D.new()
var _rts_visibility_timer: float = 0.0
var _rts_visible_target: Node3D
var _rts_clear: bool = false
@onready var weapon: HeroWeaponRuntime = $WeaponRuntime
@onready var inventory: HeroInventory = $Inventory

func _ready() -> void:
	super._ready()
	weapon.reload_started.connect((_model as HeroVisual).play_reload)
	_ray.collision_mask = 1 | 2 | 4 | 128
	_ray.exclude = [get_rid()]
	_ray.hit_from_inside = true
	(_model as HeroVisual).set_personal_layer(BODY_LAYER)
	health_bar.layers = BODY_LAYER
	work_bar.layers = BODY_LAYER
	selection_ring.layers = BODY_LAYER

func _physics_process(delta: float) -> void:
	if not alive: return
	weapon.advance(delta)
	inventory.advance(delta)
	_rts_visibility_timer -= delta
	speed_boost_remaining = maxf(0.0,speed_boost_remaining-delta)
	speed = _stats.speed * (speed_boost_multiplier if speed_boost_remaining > 0.0 else 1.0)
	previous_jump_offset = jump_offset
	jump_time = minf(JUMP_SECONDS,jump_time+delta)
	jump_offset = JUMP_HEIGHT * pow(sin(PI*jump_time/JUMP_SECONDS),2.0) if jump_time < JUMP_SECONDS else 0.0
	model_pivot.position.y = jump_offset
	if not directly_controlled:
		super._physics_process(delta)
		return
	_tick_recovery(delta)
	_damage_bar_time = maxf(0.0,_damage_bar_time-delta)
	health_bar.visible = selected or hp < max_hp or _damage_bar_time > 0.0
	var old_position := global_position
	velocity = move_input.limit_length(1.0) * speed
	velocity.y = 0.0
	if not velocity.is_zero_approx():
		move_and_slide()
		global_position = _game.clamp_to_map(global_position)
	_observed_velocity = (global_position-old_position)/delta
	_model.set_motion(_observed_velocity.length_squared()>.04)
	# The stationary RVO agent remains a moving obstacle for surrounding troops;
	# its callback cannot move the directly-controlled body a second time.
	NavigationServer3D.agent_set_velocity_forced(navigation_agent.get_rid(),_observed_velocity)
	model_pivot.rotation.y = atan2(-aim_direction.x,-aim_direction.z)
	if trigger_held: fire_direction(aim_direction)

func set_direct_control(value: bool) -> void:
	stop()
	directly_controlled = value
	move_input = Vector3.ZERO
	trigger_held = false
	collision_mask = (1 | 2 | 4 | 128) if value else 3
	_model.set_motion(false)

func _apply_velocity(safe_velocity: Vector3) -> void:
	if not directly_controlled: super._apply_velocity(safe_velocity)

func jump() -> bool:
	if not alive or jump_time < JUMP_SECONDS: return false
	jump_time = 0.0
	return true

func logic_eye() -> Vector3:
	return global_position+Vector3.UP*EYE_HEIGHT

func logic_muzzle() -> Vector3:
	# The gun pose is visual; a standing origin prevents jumping or a long model
	# from moving the actual shot through a wall. The near segment is tested too.
	return global_position+Vector3.UP*1.53 + model_pivot.basis*Vector3(.32,0,-1.06)

func query_shot(direction: Vector3) -> Dictionary:
	var eye := logic_eye()+Vector3.UP*jump_offset if directly_controlled else logic_eye()
	var intended := eye+direction.normalized()*weapon.definition.range
	_ray.from = eye
	_ray.to = intended
	var aim_hit := _space_state.intersect_ray(_ray)
	if not aim_hit.is_empty(): intended = aim_hit.position
	var muzzle := logic_muzzle()
	_ray.from = global_position+Vector3.UP*1.53
	_ray.to = muzzle
	var near_hit := _space_state.intersect_ray(_ray)
	if not near_hit.is_empty(): return near_hit
	_ray.from = muzzle
	var toward := intended-muzzle
	# The camera hit lies on the surface. Extend a tiny amount into that surface
	# for the second query, still clamped to weapon range; an exact endpoint can
	# round outside the target and incorrectly turn an aimed shot into a miss.
	var query_length := minf(weapon.definition.range,toward.length()+(.025 if not aim_hit.is_empty() else 0.0))
	_ray.to = muzzle+toward.normalized()*query_length
	var hit := _space_state.intersect_ray(_ray)
	if hit.is_empty(): return {"position":_ray.to,"collider":null}
	return hit

func fire_direction(direction: Vector3) -> bool:
	if not alive or not _game.running or direction.is_zero_approx(): return false
	if not weapon.consume_shot(): return false
	var hit := query_shot(direction)
	var victim: Object = hit.collider
	var landed: bool = (victim is BattleUnit or victim is BattleBuilding) and victim.alive and victim.alliance_id != alliance_id
	if landed: victim.receive_hit(weapon.payload(_stats,owner_id,alliance_id),self)
	_model.strike()
	var visual_origin := get_projectile_origin()
	_game.get_node("ProjectilePool").launch_visual(visual_origin,hit.position,"bullet",.06,0.0,null)
	_game.spawn_effect(visual_origin,"musket_muzzle",Color("fff0b2"))
	if victim != null: _game.spawn_effect(hit.position,"bullet_hit",Color("f0d9a2"))
	hit["enemy_hit"] = landed
	shot_resolved.emit(hit)
	weapon.finish_shot()
	return true

func _start_attack() -> void:
	if not _valid_target(target): return
	var toward := target.global_position-global_position
	var heading := atan2(-toward.x,-toward.z)
	if absf(angle_difference(model_pivot.rotation.y,heading)) <= .12:
		fire_direction(_aim_point(target)-logic_eye())

func _aim_point(entity: Node3D) -> Vector3:
	if entity is BattleBuilding: return entity.get_attack_position(global_position)+Vector3.UP*1.3
	return entity.global_position+Vector3.UP*minf(1.3,entity._stats.collision_height*.55)

func _within_attack_range(entity: Node3D, extra: float = 0.0) -> bool:
	return logic_muzzle().distance_to(_aim_point(entity)) <= weapon.definition.range+extra

func _can_start_strike(entity: Node3D) -> bool:
	if not _within_attack_range(entity): return false
	if entity != _rts_visible_target or _rts_visibility_timer <= 0.0:
		_rts_visible_target = entity
		_rts_visibility_timer = .10
		_rts_clear = query_shot(_aim_point(entity)-logic_eye()).collider == entity
	return _rts_clear

func _chase_velocity(entity: Node3D) -> Vector3:
	if _within_attack_range(entity) and not _rts_clear:
		# Approach the reachable target side instead of stopping forever at a
		# range offset behind an obstruction. Native navigation owns the route.
		if _repath_time <= 0.0:
			_repath_time = .4
			_set_navigation_target(entity.global_position)
		return _path_velocity()
	return super._chase_velocity(entity)

func _die() -> void:
	trigger_held = false
	move_input = Vector3.ZERO
	model_pivot.position.y = 0.0
	super._die()
