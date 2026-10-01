extends Node3D
## Eight soldiers per batch, reconstructed from simulation age after snapshots.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY
const SETTLE_TIME := 0.18
var airlift_id := -1
var faction := 0
var age := 0.0
var active := false
var first_batch := 0
var landed_batches := 0
var _synced := false
var _landing_points: PackedVector3Array = []
var map_definition := WarMapDefinition.new()

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	WarSurfaceEffects.configure($Marks.multimesh.mesh.material, definition)

func _ready() -> void:
	for path: String in ["Soldiers", "Wind", "Marks"]:
		get_node(path).multimesh.instance_count = RULES.PIG_AIRLIFT_BATCH_SIZE * 2

func begin(state: Dictionary, building: WarBuilding) -> void:
	airlift_id = state.id
	faction = state.faction
	age = state.age
	first_batch = int(state.landed) / RULES.PIG_AIRLIFT_BATCH_SIZE
	landed_batches = first_batch
	position = building.global_position
	_landing_points.clear()
	# Land beyond the authored perimeter, facing inward. The terrain projection
	# supports towers on terraces and hills without placing feet inside the roof.
	for index: int in RULES.PIG_AIRLIFT_BATCH_SIZE:
		var angle := TAU * (float(index) + 0.5) / RULES.PIG_AIRLIFT_BATCH_SIZE
		var radial := Vector3(cos(angle), 0, sin(angle))
		var point := building.march_perimeter_towards(position + radial) + radial * 0.55
		_landing_points.append(map_definition.surface_point(point) - position)
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	_synced = true
	pose()

func synchronize(state: Dictionary) -> void:
	faction = int(state.faction)
	age = float(state.age)
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	_synced = true
	_emit_landings(int(state.landed) / RULES.PIG_AIRLIFT_BATCH_SIZE)
	pose()

func tick(delta: float) -> void:
	if not active: return
	# Authoritative/predicted state synchronization may already contain this
	# frame's delta. Consume it once, then interpolate only between updates.
	if _synced:
		_synced = false
	else:
		age += delta
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	_emit_landings(mini(RULES.PIG_AIRLIFT_COUNT / RULES.PIG_AIRLIFT_BATCH_SIZE, floori((age + 0.000001) / RULES.PIG_AIRLIFT_BATCH_INTERVAL)))
	pose()

func _emit_landings(completed: int) -> void:
	for batch: int in range(landed_batches, completed):
		var deadline := float(batch + 1) * RULES.PIG_AIRLIFT_BATCH_INTERVAL
		# Rejoining at 1.8 seconds must not replay the four earlier impacts.
		if age - deadline > SETTLE_TIME: continue
		for index: int in _landing_points.size():
			var at := position + _landing_points[index] + Vector3.UP * 0.08
			for side: int in 2:
				var angle := float(index) * 2.399963 + side * PI
				var radial := Vector3(cos(angle), 0, sin(angle))
				$Dust.emit_particle(Transform3D(Basis.IDENTITY, to_local(at)), radial * 0.65 + Vector3.UP * 0.32, Color(), Color(), EMIT)
	landed_batches = maxi(landed_batches, completed)

func pose() -> void:
	visible = active
	var bodies: MultiMesh = $Soldiers.multimesh
	var wind: MultiMesh = $Wind.multimesh
	var marks: MultiMesh = $Marks.multimesh
	var count := 0
	var wind_count := 0
	var color := WarMarches.FACTION_COLORS[faction].srgb_to_linear()
	for batch: int in range(first_batch, RULES.PIG_AIRLIFT_COUNT / RULES.PIG_AIRLIFT_BATCH_SIZE):
		var phase := age - float(batch) * RULES.PIG_AIRLIFT_BATCH_INTERVAL
		if phase < 0.0 or phase >= RULES.PIG_AIRLIFT_BATCH_INTERVAL + SETTLE_TIME: continue
		var fall := clampf(phase / RULES.PIG_AIRLIFT_BATCH_INTERVAL, 0.0, 1.0)
		var settled := maxf(0.0, phase - RULES.PIG_AIRLIFT_BATCH_INTERVAL)
		var vanish := 1.0 - smoothstep(0.06, SETTLE_TIME, settled)
		var reveal := smoothstep(0.0, 0.055, phase)
		var height := (1.0 - fall * fall) * 7.0
		for index: int in _landing_points.size():
			var point := _landing_points[index]
			var inward := Vector3(-point.x, 0, -point.z).normalized()
			var landing := point + inward * smoothstep(0.0, SETTLE_TIME, settled) * 0.42
			var at := landing - inward * (1.0 - fall) * 0.28 + Vector3.UP * (height + 0.035)
			var yaw := atan2(-inward.x, -inward.z)
			var scale_factor := WarMarches.MODEL_SCALE * reveal * vanish
			bodies.set_instance_transform(count, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_factor), at))
			bodies.set_instance_custom_data(count, Color(color, fall + settled / SETTLE_TIME))
			marks.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * (0.27 + fall * 0.14 + settled * 1.2)), position + point + Vector3.UP * 0.095))
			marks.set_instance_custom_data(count, Color(color, reveal * vanish * (0.22 + fall * 0.34)))
			count += 1
			if settled <= 0.0 and fall > 0.08:
				wind.set_instance_transform(wind_count, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.5 + fall * 1.1, 1)), at + Vector3.UP * 1.45))
				wind.set_instance_custom_data(wind_count, Color(color.lerp(Color.WHITE, 0.65), reveal * (0.35 + fall * 0.35)))
				wind_count += 1
	bodies.visible_instance_count = count
	wind.visible_instance_count = wind_count
	marks.visible_instance_count = count

func set_running(value: bool) -> void:
	$Dust.speed_scale = 1.0 if value else 0.0

func reset() -> void:
	airlift_id = -1
	active = false
	_synced = false
	first_batch = 0
	landed_batches = 0
	for path: String in ["Soldiers", "Wind", "Marks"]:
		get_node(path).multimesh.visible_instance_count = 0
	$Dust.restart()
	$Dust.emitting = false
	hide()
