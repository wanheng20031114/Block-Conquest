extends Node3D
## Eight soldiers fall directly into the authored roof, without a ground march.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const SOLDIER := preload("res://assets/models/block_war/militia.res")
const DROP_HEIGHT := 5.8
const COLUMN_SPACING := Vector2(0.54, 0.68)
var airlift_id := -1
var faction := 0
var age := 0.0
var active := false
var first_batch := 0
var landed_batches := 0
var _synced := false
var _running := true
var _building: WarBuilding
var _geometry_signature := Vector2i(-1, -1)
var _entry_points: PackedVector3Array = []
var _roof_height := 0.0

func _ready() -> void:
	for path: String in ["Soldiers", "Wind"]:
		get_node(path).multimesh.instance_count = RULES.PIG_AIRLIFT_BATCH_SIZE

static func entry_points_for(building: WarBuilding) -> PackedVector3Array:
	# One copy of each native face array serves all eight downward rays. Query
	# only the active structure: the flag, population badge and foundation do
	# not define its roof. Coordinates are relative to the building position.
	var points: PackedVector3Array = []
	for index: int in RULES.PIG_AIRLIFT_BATCH_SIZE:
		points.append(Vector3((float(index % 4) - 1.5) * COLUMN_SPACING.x, 0,
			(float(index / 4) - 0.5) * COLUMN_SPACING.y))
	var structure: Node3D = building.get_node("Visual/" + ["House", "Tower", "Smithy", "EnergyTower"][building.kind])
	for part: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
		if not part.is_visible_in_tree(): continue
		var faces := part.mesh.get_faces()
		var bounds := part.get_aabb()
		for index: int in points.size():
			var point := building.global_position + points[index]
			var ray_top := part.to_local(Vector3(point.x, building.global_position.y + 32.0, point.z))
			var ray_bottom := part.to_local(Vector3(point.x, building.global_position.y - 0.5, point.z))
			if bounds.intersects_segment(ray_top, ray_bottom) == null: continue
			for face: int in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(ray_top, ray_bottom,
					faces[face], faces[face + 1], faces[face + 2])
				if hit != null:
					points[index].y = maxf(points[index].y, part.to_global(hit).y - building.global_position.y)
	return points

func _refresh_roof() -> void:
	var signature := Vector2i(_building.kind, _building.level)
	if signature == _geometry_signature: return
	_geometry_signature = signature
	_entry_points = entry_points_for(_building)
	_roof_height = 0.0
	for point: Vector3 in _entry_points:
		assert(point.y > 0.0, "Every compact airlift column must meet the authored building.")
		_roof_height = maxf(_roof_height, point.y)

func begin(state: Dictionary, building: WarBuilding) -> void:
	airlift_id = state.id
	faction = state.faction
	age = state.age
	first_batch = int(state.landed) / RULES.PIG_AIRLIFT_BATCH_SIZE
	landed_batches = first_batch
	_building = building
	_geometry_signature = Vector2i(-1, -1)
	position = building.global_position
	_refresh_roof()
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	_synced = true
	pose()

func synchronize(state: Dictionary) -> void:
	faction = int(state.faction)
	age = float(state.age)
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	_synced = true
	landed_batches = maxi(landed_batches, int(state.landed) / RULES.PIG_AIRLIFT_BATCH_SIZE)
	_refresh_roof()
	pose()

func tick(delta: float) -> void:
	if not active or not _running: return
	# Consume synchronized simulation time once; interpolate between snapshots.
	if _synced:
		_synced = false
	else:
		age += delta
	active = age < RULES.PIG_AIRLIFT_LIFETIME
	landed_batches = maxi(landed_batches, mini(RULES.PIG_AIRLIFT_COUNT / RULES.PIG_AIRLIFT_BATCH_SIZE,
		floori((age + 0.000001) / RULES.PIG_AIRLIFT_BATCH_INTERVAL)))
	_refresh_roof()
	pose()

func pose() -> void:
	visible = active
	var bodies: MultiMesh = $Soldiers.multimesh
	var wind: MultiMesh = $Wind.multimesh
	var count := 0
	var wind_count := 0
	var color := WarMarches.FACTION_COLORS[faction].srgb_to_linear()
	var model_top := SOLDIER.get_aabb().end.y * WarMarches.MODEL_SCALE
	var batch := floori((age + 0.000001) / RULES.PIG_AIRLIFT_BATCH_INTERVAL)
	if batch >= first_batch and batch < RULES.PIG_AIRLIFT_COUNT / RULES.PIG_AIRLIFT_BATCH_SIZE:
		var phase := maxf(0.0, age - float(batch) * RULES.PIG_AIRLIFT_BATCH_INTERVAL)
		var fall := phase / RULES.PIG_AIRLIFT_BATCH_INTERVAL
		var reveal := smoothstep(0.0, 0.045, phase)
		for point: Vector3 in _entry_points:
			# Preserve X/Z throughout: feet and then the body pass behind the roof.
			# At the actual batch boundary even the spear is below that surface.
			var height := lerpf(_roof_height + DROP_HEIGHT, point.y - model_top - 0.12, fall * fall)
			var at := Vector3(point.x, height, point.z)
			bodies.set_instance_transform(count, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * WarMarches.MODEL_SCALE * reveal), at))
			bodies.set_instance_custom_data(count, Color(color, fall))
			count += 1
			if fall > 0.08 and fall < 0.92:
				wind.set_instance_transform(wind_count, Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.5 + fall, 1)), at + Vector3.UP * 1.55))
				wind.set_instance_custom_data(wind_count, Color(color.lerp(Color.WHITE, 0.65), reveal * (0.35 + fall * 0.35) * (1.0 - smoothstep(0.65, 0.92, fall))))
				wind_count += 1
	bodies.visible_instance_count = count
	wind.visible_instance_count = wind_count

func set_running(value: bool) -> void:
	_running = value

func reset() -> void:
	airlift_id = -1
	active = false
	_synced = false
	first_batch = 0
	landed_batches = 0
	_building = null
	_geometry_signature = Vector2i(-1, -1)
	for path: String in ["Soldiers", "Wind"]:
		get_node(path).multimesh.visible_instance_count = 0
	hide()
