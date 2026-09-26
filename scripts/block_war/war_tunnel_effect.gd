extends Node3D
## One authored entrance, moving digging front and delayed exit per faction.

signal tunnel_opened(at: Vector3)

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var age := 100.0
var dig_duration := 0.5
var exit_duration := 0.5
var entrance := Vector3.ZERO
var exit := Vector3.ZERO
var exit_direction := Vector3.FORWARD
var tint := Color.WHITE
var exit_opened := false
var active := false
var running := true

func start(faction: int, from: Vector3, to: Vector3, direction: Vector3, count: int, digging_seconds: float) -> void:
	reset()
	entrance = from
	exit = to
	exit_direction = direction
	tint = WarMarches.FACTION_COLORS[faction]
	dig_duration = digging_seconds
	exit_duration = floorf(float(count - 1) / WarMarches.COLUMNS) * RULES.BURROW_BATCH_INTERVAL + 0.4
	age = 0.0
	active = true
	var heading := (exit - entrance).normalized()
	$Entrance.start(entrance, heading, dig_duration + exit_duration, tint)
	$Digging.position = entrance
	$Digging.rotation.y = atan2(-heading.x, -heading.z)
	$Digging.show()
	$Digging/Mound.show()
	var span := entrance.distance_to(exit) + 4.0
	for particles: GPUParticles3D in [$Digging/Dust, $Digging/Clods]:
		particles.visibility_aabb = AABB(Vector3(-span, -2, -span), Vector3(span * 2, 8, span * 2))
		particles.restart()
		particles.emitting = true
	tick(0.0)

func tick(delta: float) -> void:
	if not active or not running:
		return
	age += delta
	$Entrance.tick(delta)
	if not exit_opened and age >= dig_duration:
		exit_opened = true
		$Exit.start(exit, exit_direction, exit_duration, tint)
		$Exit.tick(age - dig_duration)
		tunnel_opened.emit(exit)
	elif exit_opened:
		$Exit.tick(delta)
	var digging := age < dig_duration
	var progress := clampf(age / dig_duration, 0.0, 1.0)
	$Digging.position = entrance.lerp(exit, progress)
	$Digging/Mound.position.y = 0.1 + absf(sin(age * 55.0)) * 0.12
	$Digging/Mound.rotation.z = sin(age * 42.0) * 0.12
	$Digging/Mound.visible = digging
	$Digging/Dust.emitting = digging
	$Digging/Clods.emitting = digging
	if age > dig_duration + exit_duration + 0.9:
		active = false
		$Digging.hide()

func reset() -> void:
	active = false
	exit_opened = false
	age = 100.0
	$Entrance.reset()
	$Exit.reset()
	$Digging.hide()
	for particles: GPUParticles3D in [$Digging/Dust, $Digging/Clods]:
		particles.restart()
		particles.emitting = false

func set_running(value: bool) -> void:
	running = value
	$Entrance.set_running(value)
	$Exit.set_running(value)
	for particles: GPUParticles3D in [$Digging/Dust, $Digging/Clods]:
		particles.speed_scale = 1.0 if value else 0.0
