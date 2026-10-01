extends Node3D
## Authored visual pools. Timers and damage remain entirely in the match state.

const EMIT := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_ROTATION_SCALE | GPUParticles3D.EMIT_FLAG_VELOCITY
var running := true
var map_definition := WarMapDefinition.new()
var trail_clock := 0.0
var trail_offset := 0
var _buildings: Array = []

func _ready() -> void:
	for slot: Node3D in $Airlifts.get_children():
		slot.reset()

func configure_surface(definition: WarMapDefinition) -> void:
	map_definition = definition
	for slot: Node3D in $Preparations.get_children():
		slot.configure_surface(definition)
	for slot: Node3D in $Drops.get_children():
		slot.configure_surface(definition)
	for slot: Node3D in $Airlifts.get_children():
		slot.configure_surface(definition)

func update_ready(buildings: Array, ready: Dictionary) -> void:
	_buildings = buildings
	# The two preparations can coexist; airlifts are separate immediate actions.
	var count := 0
	for building: WarBuilding in buildings:
		if not ready.has(building.building_id):
			continue
		$Preparations.get_child(count).update_building(building, ready[building.building_id])
		count += 1
	for index: int in range(count, $Preparations.get_child_count()):
		$Preparations.get_child(index).reset()

func start_drop(id: int, faction: int, center: Vector3, age: float = 0.0) -> void:
	var slot: Node3D = _drop_slot(id)
	if slot.drop_id == id:
		slot.age = age
		slot.active = age < slot.VISIBLE_TIME
		slot.pose()
		_emit_landing(slot)
	else:
		slot.begin(id, faction, center, age, _roof_at(center))

func _roof_at(center: Vector3) -> float:
	# A visible pig touches the roof when the cast lands directly on a building.
	# Ground rings and authoritative damage remain centered at ground level.
	var height := 0.0
	for building: WarBuilding in _buildings:
		if Vector2(building.global_position.x, building.global_position.z).distance_squared_to(Vector2(center.x, center.z)) > 2.4 * 2.4:
			continue
		for mesh: MeshInstance3D in building.get_node("Visual").find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree():
				continue
			var bounds := mesh.get_aabb()
			for corner: int in 8:
				height = maxf(height, mesh.to_global(bounds.get_endpoint(corner)).y - center.y)
	return height

func sync_drops(states: Array) -> void:
	var ids: Array[int] = []
	for state: Dictionary in states:
		ids.append(int(state.id))
		start_drop(int(state.id), int(state.faction), state.at, float(state.age))
	for slot: Node3D in $Drops.get_children():
		if slot.drop_id not in ids:
			slot.reset()

func sync_airlifts(states: Array, by_id: Dictionary) -> void:
	var ids: Array[int] = []
	for state: Dictionary in states:
		ids.append(int(state.id))
	# A replacement snapshot may contain six new casts. Release obsolete slots
	# before allocating, even when every old cast was still locally active.
	for slot: Node3D in $Airlifts.get_children():
		if slot.airlift_id not in ids:
			slot.reset()
	for state: Dictionary in states:
		var slot := _airlift_slot(int(state.id))
		if slot.airlift_id == int(state.id):
			slot.synchronize(state)
		else:
			slot.begin(state, by_id[int(state.target)])

func _airlift_slot(id: int) -> Node3D:
	for slot: Node3D in $Airlifts.get_children():
		if slot.airlift_id == id: return slot
	for slot: Node3D in $Airlifts.get_children():
		if not slot.active: return slot
	assert(false, "Six authored airlift slots cover all six player cooldowns.")
	return null

func _drop_slot(id: int) -> Node3D:
	for slot: Node3D in $Drops.get_children():
		if slot.drop_id == id:
			return slot
	for slot: Node3D in $Drops.get_children():
		if not slot.active:
			return slot
	# Cosmetic-only pool saturation cannot discard the authoritative impact.
	var oldest: Node3D = $Drops.get_child(0)
	for slot: Node3D in $Drops.get_children():
		if slot.drop_id < oldest.drop_id:
			oldest = slot
	return oldest

func tick(delta: float) -> void:
	if not running:
		return
	for slot: Node3D in $Preparations.get_children():
		slot.tick(delta)
	for slot: Node3D in $Drops.get_children():
		slot.tick(delta)
		_emit_landing(slot)
	for slot: Node3D in $Airlifts.get_children():
		slot.tick(delta)

func _emit_landing(slot: Node3D) -> void:
	if slot.active and not slot.dust_emitted and slot.age >= slot.IMPACT_TIME:
		slot.dust_emitted = true
		$Dust.visibility_aabb = $Dust.visibility_aabb.merge(AABB(slot.position - Vector3(5, 0, 5), Vector3(10, 7, 10)))
		for index: int in 28:
			var angle := index * 2.399963
			var radial := Vector3(cos(angle), 0, sin(angle))
			var at := WarSurfaceEffects.offset_point(map_definition, slot.position, radial * (0.7 + float(index % 3) * 0.28) + Vector3.UP * (slot.roof_height + 0.18))
			$Dust.emit_particle(Transform3D(Basis.IDENTITY, at), radial * (3.0 + float(index % 3) * 0.45) + Vector3.UP * 0.65, Color(), Color(), EMIT)
		for index: int in 16:
			var angle := index * 2.399963
			var radial := Vector3(cos(angle), 0, sin(angle))
			var at := WarSurfaceEffects.offset_point(map_definition, slot.position, radial * 1.2 + Vector3.UP * (slot.roof_height + 0.2))
			var basis := Basis.from_euler(Vector3(angle, angle * 0.3, angle * 0.7))
			$Debris.emit_particle(Transform3D(basis, at), radial * (2.0 + float(index % 4) * 0.55) + Vector3.UP * (2.2 + float(index % 3) * 0.7), Color(), Color(), EMIT)

func set_running(value: bool) -> void:
	running = value
	for slot: Node3D in $Airlifts.get_children():
		slot.set_running(value)
	for emitter: GPUParticles3D in [$Dust, $Debris, $ChargeTrails, $FlightTrails]:
		emitter.speed_scale = 1.0 if value else 0.0

func update_units(delta: float, marches: WarMarches) -> void:
	if not running:
		return
	trail_clock += delta
	if trail_clock < 0.075:
		return
	trail_clock = fmod(trail_clock, 0.075)
	var soldiers: Array[WarMarches.MarchUnit] = []
	for unit: WarMarches.MarchUnit in marches._units:
		if unit.is_exposed() and not unit.cloaked and unit.levitation_remaining <= 0.0 and unit.intercepted_by < 0 and (unit.order.pig_charge or unit.order.airborne):
			soldiers.append(unit)
	if soldiers.is_empty():
		return
	var bounds := AABB(soldiers[0].position, Vector3.ZERO)
	for unit: WarMarches.MarchUnit in soldiers:
		bounds = bounds.expand(unit.position)
	$ChargeTrails.visibility_aabb = bounds.grow(3.0)
	$FlightTrails.visibility_aabb = bounds.grow(3.0)
	for index: int in mini(64, soldiers.size()):
		var unit := soldiers[(trail_offset + index) % soldiers.size()]
		var basis := Basis.looking_at(unit.heading)
		var at := unit.position + unit.presentation_offset + Vector3.UP * 0.25 - unit.heading * 0.42
		if unit.order.pig_charge:
			$ChargeTrails.emit_particle(Transform3D(basis, at), -unit.heading * 0.8 + Vector3.UP * 0.12, Color(), Color(), EMIT)
		if unit.order.airborne:
			for side: float in [-1.0, 1.0]:
				var wing := at + basis.x * side * 0.26
				$FlightTrails.emit_particle(Transform3D(basis, wing), -unit.heading * 0.5 + Vector3.UP * 0.14, Color(), Color(), EMIT)
	trail_offset = (trail_offset + 64) % soldiers.size()

func reset() -> void:
	_buildings = []
	for slot: Node3D in $Preparations.get_children():
		slot.reset()
	for slot: Node3D in $Drops.get_children():
		slot.reset()
	for slot: Node3D in $Airlifts.get_children():
		slot.reset()
	trail_clock = 0.0
	trail_offset = 0
	for emitter: GPUParticles3D in [$Dust, $Debris, $ChargeTrails, $FlightTrails]:
		emitter.restart()
		emitter.emitting = false
