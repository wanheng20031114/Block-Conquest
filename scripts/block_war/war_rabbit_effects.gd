extends Node3D
signal tunnel_opened(at: Vector3)

const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR
const RUSH_BURST_DURATION := 0.4
const RUSH_EMISSION_INTERVAL := 0.07
const RUSH_COLOR := Color("ff5148")
var rush_bursts: Dictionary[int, Dictionary] = {}
var emission := 0.0
var serial := 0
var soldier_offset := 0
var running := true

func _ready() -> void:
	$RushBursts.multimesh.instance_count = WarMarches.FACTION_COLORS.size()
	$RushBursts.multimesh.visible_instance_count = 0
	for tunnel: Node3D in $Tunnels.get_children():
		tunnel.tunnel_opened.connect(_on_tunnel_opened)

func start_tunnel(faction: int, entrance: Vector3, exit: Vector3, direction: Vector3, count: int, dig_duration: float) -> void:
	$Tunnels.get_child(faction).start(faction, entrance, exit, direction, count, dig_duration)

func _on_tunnel_opened(at: Vector3) -> void:
	tunnel_opened.emit(at)

func start_recall(faction: int, center: Vector3, radius: float) -> void:
	$Rallies.get_child(faction).start(center, radius, faction)

func start_rush(faction: int, center: Vector3, radius: float) -> void:
	rush_bursts[faction] = {"at": center, "radius": radius, "remaining": RUSH_BURST_DURATION}
	_draw_rush_bursts()
	for index: int in 18:
		var angle := float(index) * TAU / 18.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		var at := center + radial * radius * 0.48 + Vector3.UP * 0.16
		$RushStreaks.emit_particle(Transform3D(Basis.looking_at(radial), at), radial * 5.0, RUSH_COLOR.srgb_to_linear(), Color(), FLAGS)

func return_dust(at: Vector3, direction: Vector3) -> void:
	for i: int in 3:
		$FootDust.emit_particle(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.12), -direction.normalized() * 0.3 + Vector3.UP * 0.28, Color("d3c5a6"), Color(), FLAGS)

func tick(delta: float) -> void:
	if not running:
		return
	for faction: int in rush_bursts.keys():
		rush_bursts[faction].remaining -= delta
		if rush_bursts[faction].remaining <= 0.0:
			rush_bursts.erase(faction)
	_draw_rush_bursts()
	for effect: Node3D in $Tunnels.get_children():
		effect.tick(delta)
	for effect: Node3D in $Rallies.get_children():
		effect.tick(delta)

func _draw_rush_bursts() -> void:
	var mesh: MultiMesh = $RushBursts.multimesh
	var count := 0
	var bounds := AABB()
	for faction: int in rush_bursts:
		var burst: Dictionary = rush_bursts[faction]
		mesh.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * burst.radius), burst.at + Vector3.UP * 0.085))
		mesh.set_instance_custom_data(count, Color(RUSH_COLOR.srgb_to_linear(), 1.0 - burst.remaining / RUSH_BURST_DURATION))
		var burst_bounds := AABB(burst.at - Vector3(burst.radius, 0, burst.radius), Vector3(burst.radius * 2, 1, burst.radius * 2))
		bounds = burst_bounds if count == 0 else bounds.merge(burst_bounds)
		count += 1
	mesh.visible_instance_count = count
	if count > 0:
		mesh.custom_aabb = bounds

func update_rush(delta: float, marches: WarMarches) -> void:
	if not running:
		return
	emission += delta
	if emission < RUSH_EMISSION_INTERVAL:
		return
	emission = fmod(emission, RUSH_EMISSION_INTERVAL)
	var runners: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.is_exposed() and unit.rush_remaining > 0.0:
			runners.append(unit)
	if runners.is_empty():
		return
	var bounds := AABB(runners[0].position, Vector3.ZERO)
	for unit: WarMarches.MarchUnit in runners:
		bounds = bounds.expand(unit.position)
	for faction: int in rush_bursts:
		bounds = bounds.expand(rush_bursts[faction].at)
	$RushStreaks.visibility_aabb = bounds.grow(4.0)
	for i: int in mini(48, runners.size()):
		var unit := runners[(soldier_offset + i) % runners.size()]
		serial += 1
		var sideways := Vector3(-unit.heading.z, 0, unit.heading.x)
		var offset := 0.20 if serial % 2 == 0 else -0.20
		var at := unit.position - unit.heading * 0.52 + sideways * offset + Vector3.UP * 0.27
		$RushStreaks.emit_particle(Transform3D(Basis.looking_at(unit.heading), at), -unit.heading * 1.1, RUSH_COLOR.srgb_to_linear(), Color(), FLAGS)
	soldier_offset = (soldier_offset + 48) % runners.size()

func set_running(value: bool) -> void:
	running = value
	for particles: GPUParticles3D in [$FootDust, $RushStreaks]:
		particles.speed_scale = 1.0 if value else 0.0
	for effect: Node3D in $Tunnels.get_children():
		effect.set_running(value)
	for effect: Node3D in $Rallies.get_children():
		effect.set_running(value)

func reset() -> void:
	rush_bursts.clear()
	emission = 0.0
	serial = 0
	soldier_offset = 0
	$RushBursts.multimesh.visible_instance_count = 0
	for effect: Node3D in $Tunnels.get_children():
		effect.reset()
	for effect: Node3D in $Rallies.get_children():
		effect.reset()
	for particles: GPUParticles3D in [$FootDust, $RushStreaks]:
		particles.restart()
		particles.emitting = false
