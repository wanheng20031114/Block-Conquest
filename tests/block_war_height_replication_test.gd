extends "res://tests/block_war_replication_test.gd"
## Real authored uplands through the serialized Host/replica snapshot and event stream.

const CASES: Array[Dictionary] = [
	{"id": "terraces", "seats": 2, "summit": 10, "height": 4.5, "ramp": Rect2(-26, -6, 14, 12), "ramp_height": 4.5, "plateau": Rect2(-12, -12, 24, 24), "fire": Vector3(8, 4.5, 8)},
	{"id": "switchback", "seats": 4, "summit": 14, "height": 8.0, "ramp": Rect2(-34, -33, 16, 12), "ramp_height": 4.5, "plateau": Rect2(-8, -6, 16, 12), "fire": Vector3(6, 8, 3.5)},
	{"id": "crown", "seats": 6, "summit": 10, "height": 5.0, "ramp": Rect2(-52, -32, 16, 12), "ramp_height": 5.0, "plateau": Rect2(-36, -36, 72, 16), "fire": Vector3(0, 5, -28)},
]
const EPSILON := 0.002
var scenario: Dictionary
var field_center := Vector3.ZERO

func configuration() -> Dictionary:
	var value := {"map_id": scenario.id, "host_player_id": 100, "match_id": "height-replication-" + str(scenario.id), "code": "HEIGHT", "revision": 1, "phase": "match", "slots": []}
	for faction: int in int(scenario.seats):
		var human := faction < 2
		value.slots.append({"slot_id": faction, "faction_id": faction, "team_id": faction % 2, "kind": "human" if human else "bot", "commander": "squirrel" if faction == 0 else "frog", "player_id": 100 + faction if human else -1, "name": "Height %d" % faction, "ready": true, "connected": true, "controller": "human" if human else "bot", "control_epoch": 1, "surrendered": false})
	return value

func make_wire(player: int) -> FakeOnline:
	var wire := FakeOnline.new()
	wire.room = configuration()
	wire.match_config = configuration()
	wire.player_id = player
	wire.local_faction = player - 100
	wire.is_host = player == 100
	root.add_child(wire)
	return wire

func verify(value: bool, label: String) -> void:
	check(value, str(scenario.id) + ": " + label)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	for fixture: Dictionary in CASES:
		scenario = fixture
		session.block_war_map_id = scenario.id
		host = make_game(100)
		replica = make_game(101)
		_seed_real_battle()
		host_wire = make_wire(100)
		client_wire = make_wire(101)
		authority = Coordinator.new()
		client = Coordinator.new()
		authority.setup(host, host_wire)
		client.setup(replica, client_wire)
		host.network_match = authority
		replica.network_match = client
		flush()
		client.process(0.0)
		verify(not client._snapshot_loading and host_wire.recovered.has(101), "initial serialized snapshot completes and is acknowledged")
		_verify_synchronized("initial snapshot", true)
		_incremental_and_recovery()
		verify(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "all height-bearing messages satisfy primitive and channel contracts")
		await host.prepare_shutdown()
		await replica.prepare_shutdown()
		host.free()
		replica.free()
		host_wire.free()
		client_wire.free()
		authority = null
		client = null
		await process_frame
	session.block_war_map_id = previous_map
	print("BLOCK_WAR_HEIGHT_REPLICATION maps=", CASES.size(), " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _seed_real_battle() -> void:
	var source: WarBuilding = host.by_id[0]
	var summit: WarBuilding = host.by_id[int(scenario.summit)]
	# An allied elevated garrison lets both real road directions remain active.
	summit.faction = 0
	summit.population = 60.0
	summit.refresh_visual()
	source.population = 60.0
	verify(host.issue_order(source, summit, 50) == 30, "normal dispatch queues real soldiers toward the authored summit")
	var ramp_unit: WarMarches.MarchUnit
	for step: int in 600:
		host.simulate(0.1)
		for unit: WarMarches.MarchUnit in host.marches._units:
			if unit.is_exposed() and (scenario.ramp as Rect2).grow(-0.8).has_point(Vector2(unit.position.x, unit.position.z)) and unit.position.y > 0.8:
				ramp_unit = unit
				break
		if ramp_unit != null:
			break
	verify(ramp_unit != null, "normal simulation reaches the real ascending ramp before snapshot capture")
	assert(ramp_unit != null)
	field_center = ramp_unit.position
	for faction: int in 2:
		host.faction_skills[faction].energy = 100.0
	verify(host.execute_network_command(0, {"type": "skill_ground", "skill": 1, "x": field_center.x, "z": field_center.z}).accepted, "XZ-only haste command creates a real field on the ramp")
	verify(host.execute_network_command(1, {"type": "skill_ground", "skill": 1, "x": field_center.x, "z": field_center.z}).accepted, "real frog cast suspends the ascending soldiers")
	var high_fire: Vector3 = scenario.fire
	verify(host.execute_network_command(0, {"type": "skill_ground", "skill": 3, "x": high_fire.x, "z": high_fire.z}).accepted, "XZ-only fire command reconstructs the real high surface")
	var half_size: Vector2 = host.map.definition.half_size
	host.start_fire(Vector3(-half_size.x + 3, 0, half_size.y - 3), 4.5, 0)
	host.simulate(0.25)
	verify(host.fire_states.size() == 2, "initial state contains simultaneous high and low fire effects")
	verify(ramp_unit.levitation_remaining > 0 and ramp_unit.position.y > field_center.y + 1.5, "snapshot includes nonzero levitation relative to a nonzero ramp height")

func _incremental_and_recovery() -> void:
	var before_sequence: int = client._applied
	verify(client.submit({"type": "skill_ground", "skill": 0, "x": field_center.x, "z": field_center.z}).accepted, "remote client submits a real mist command on the slope")
	verify(authority.submit({"type": "dispatch", "source": int(scenario.summit), "target": 0, "percent": 50}).accepted, "Host submits a new downhill dispatch through the coordinator")
	deliver(client_wire, authority)
	boundary()
	flush()
	verify(client._applied > before_sequence and client._mirror.orders.size() == 2, "incremental facts create the second three-dimensional order")
	verify(replica.marches.weak_zones.has(1), "remote ground command is accepted by Host and restored on replica")
	if replica.marches.weak_zones.has(1):
		verify((replica.marches.weak_zones[1].at as Vector3).distance_to(field_center) < EPSILON, "incremental mist center retains the reconstructed ramp elevation")
	# A replicated pause aligns rule clocks, allowing strict host/unit comparisons.
	verify(client.submit({"type": "pause", "paused": true}).accepted, "remote pause requests an exact comparison boundary")
	deliver(client_wire, authority)
	boundary()
	flush()
	verify(host.match_paused and replica.match_paused, "pause facts freeze both replicas at the same boundary")
	_verify_synchronized("incremental pause", true)
	var high_units := 0
	for unit: WarMarches.MarchUnit in replica.marches._units:
		if unit.is_exposed() and unit.order.source_id == int(scenario.summit) and absf(unit.position.y - float(scenario.height)) < EPSILON:
			high_units += 1
	verify(high_units > 0, "the new downhill order exposes real soldiers on the authored high plateau")
	var count_before: int = replica.marches._units.size()
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(101)
	flush()
	verify(not client._recovery_waiting and replica.marches._units.size() == count_before, "recovery snapshot completes without duplicating soldiers")
	_verify_synchronized("recovery snapshot", true)
	verify(authority.submit({"type": "pause", "paused": false}).accepted, "Host resumes the recovered highland battle")
	boundary()
	flush()
	for tick: int in 18:
		boundary(Coordinator.STEP, true)
		if tick % 6 == 5:
			_verify_surface("lossy anchors")
	flush()
	verify(Codec.digest(client._mirror) == Codec.digest(authority._published), "lost optional movement anchors do not corrupt the canonical height-bearing facts")
	verify(client.resync_count == 1, "height recovery and missing optional anchors do not create resync loops")

func _verify_synchronized(stage: String, exact_positions: bool) -> void:
	verify(host.map.definition.map_id == scenario.id and replica.map.definition.map_id == scenario.id, stage + " loads the real map on both peers")
	verify(host.faction_count == int(scenario.seats) and replica.faction_count == int(scenario.seats), stage + " retains the authored seat count")
	verify(Codec.valid(client._mirror, replica), stage + " passes snapshot schema validation")
	verify(Codec.digest(client._mirror) == Codec.digest(authority._published), stage + " preserves the canonical snapshot digest")
	var buildings_match := true
	for building: WarBuilding in host.buildings:
		var mirrored: WarBuilding = replica.by_id[building.building_id]
		buildings_match = buildings_match and mirrored.global_position.distance_to(building.global_position) < EPSILON and mirrored.faction == building.faction and mirrored.kind == building.kind
	verify(buildings_match, stage + " retains real building transforms and replicated ownership")
	verify(absf(replica.by_id[int(scenario.summit)].global_position.y - float(scenario.height)) < EPSILON, stage + " restores the explicitly known summit height")
	verify(host.marches._units.size() == replica.marches._units.size() and not replica.marches._units.is_empty(), stage + " restores a nonempty real army")
	var mirrored_units := {}
	for unit: WarMarches.MarchUnit in replica.marches._units:
		mirrored_units[unit.unit_id] = unit
	var routes_match := true
	var positions_match := true
	var inspected_orders := {}
	var slope_points := 0
	for original: WarMarches.MarchUnit in host.marches._units:
		if not mirrored_units.has(original.unit_id):
			routes_match = false
			positions_match = false
			continue
		var restored: WarMarches.MarchUnit = mirrored_units[original.unit_id]
		positions_match = positions_match and original.position.distance_to(restored.position) < EPSILON
		if inspected_orders.has(original.order.order_id):
			continue
		inspected_orders[original.order.order_id] = true
		var first := original.order.curve
		var second := restored.order.curve
		routes_match = routes_match and first.point_count == second.point_count
		for index: int in mini(first.point_count, second.point_count):
			var point: Vector3 = first.get_point_position(index)
			routes_match = routes_match and point.distance_to(second.get_point_position(index)) < EPSILON
			if point.y > 0.1 and point.y < float(scenario.ramp_height) - 0.1:
				slope_points += 1
	verify(routes_match and slope_points > 0, stage + " preserves every XYZ route point including interior slope samples")
	if exact_positions:
		verify(absf(host.elapsed - replica.elapsed) < 0.00001 and positions_match, stage + " restores unit positions at the exact authoritative clock")
	_verify_surface(stage)
	_verify_effects(stage)

func _verify_surface(stage: String) -> void:
	var ramp_checks := 0
	var grounded := true
	var display_grounded := true
	var ramp: Rect2 = scenario.ramp
	for unit: WarMarches.MarchUnit in replica.marches._units:
		if not unit.is_exposed():
			continue
		var xz := Vector2(unit.position.x, unit.position.z)
		var ground: float = replica.map.definition.surface_height(xz)
		if ramp.has_point(xz):
			# These three west ramps have independently authored, known X gradients.
			var expected: float = (unit.position.x - ramp.position.x) / ramp.size.x * float(scenario.ramp_height)
			grounded = grounded and absf(ground - expected) < EPSILON
			ground = expected
			ramp_checks += 1
		elif (scenario.plateau as Rect2).has_point(xz):
			grounded = grounded and absf(ground - float(scenario.height)) < EPSILON
			ground = float(scenario.height)
		var lift := unit.position.y - ground
		grounded = grounded and (lift >= -EPSILON and lift < 1.8 if unit.levitation_remaining > 0 else absf(lift) < EPSILON)
		var drawn: Vector3 = replica.marches._presentation_position(unit)
		var display_height: float = replica.map.definition.surface_height(Vector2(drawn.x, drawn.z))
		display_grounded = display_grounded and absf(drawn.y - display_height - lift - 0.035) < EPSILON
	verify(ramp_checks > 0 and grounded, stage + " checks nonempty ramp occupants against an independent height formula")
	verify(display_grounded, stage + " keeps client smoothing on the surface while preserving spell lift")

func _verify_effects(stage: String) -> void:
	verify(replica.marches.haste_zones.has(0) and (replica.marches.haste_zones[0].at as Vector3).distance_to(field_center) < EPSILON, stage + " restores the actual elevated haste field")
	verify(replica.fire_states.size() == 2, stage + " restores simultaneous fire state at two elevations")
	var restored_fires := {}
	for fire: RefCounted in replica.fire_states:
		restored_fires[int(fire.effect_id)] = fire
	var fires_match := true
	var visible_fires := 0
	for original: RefCounted in host.fire_states:
		if not restored_fires.has(original.effect_id):
			fires_match = false
			continue
		var restored: RefCounted = restored_fires[original.effect_id]
		fires_match = fires_match and restored.global_position.distance_to(original.global_position) < EPSILON and absf(restored.age - original.age) < EPSILON
		for visual: WarFireWave in replica.world_effects.get_node("FireWaves").get_children():
			if visual.effect_id != original.effect_id:
				continue
			visible_fires += int(visual.visible)
			fires_match = fires_match and visual.global_position.distance_to(original.global_position) < EPSILON
			for layer: String in ["Flames", "Sparks", "Smoke"]:
				var material: ShaderMaterial = visual.get_node(layer).draw_pass_1.material
				fires_match = fires_match and absf(float(material.get_shader_parameter("emitter_surface_height")) - original.global_position.y) < EPSILON
				fires_match = fires_match and int(material.get_shader_parameter("terrain_zone_count")) == replica.map.definition.height_zones.size()
	verify(fires_match and visible_fires == 2, stage + " installs visible native fire nodes with independent surface heights and terrain uniforms")
