extends SceneTree
## Population conservation, actual formation geometry, queues and tower targeting.

const MARCHES := preload("res://scenes/block_war/marches.tscn")
const MAP_RULES := preload("res://scripts/block_war/war_map.gd")
var _checks := 0
var _failures: Array[String] = []
var _arrived: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		printerr("FAIL ", description)

func _on_arrived(target_id: int, faction: int, strength: float) -> void:
	_arrived.append({"target_id": target_id, "faction": faction, "strength": strength})

func _run() -> void:
	var marches = MARCHES.instantiate()
	root.add_child(marches)
	marches.unit_arrived.connect(_on_arrived)
	var straight := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, -30)])
	marches.send(0, 1, 0, 1, straight)
	marches.tick(1.0)
	_check(marches.get_units()[0].position.is_equal_approx(Vector3(0, 0, -3.1)), "Default marching covers 3.1 metres in one second")
	marches.clear()
	marches.send(0, 1, 0, 42, straight, 1.25)
	_check(marches.total_for(0) == 42, "Queued and visible population are both conserved")
	_check(marches.incoming_for(1, 0) == 42, "Incoming intelligence includes the door queue")
	marches.tick(1.2)
	var sample: Array = marches.get_units()
	_check(sample.size() > 12 and sample.size() < 42, "Soldiers emerge over several ranks instead of all at once")
	var widest := 0.0
	for unit: Dictionary in sample:
		widest = maxf(widest, absf(unit.position.x))
	_check(absf(widest - 1.40) < 0.002, "Six files span 2.80m with symmetric outer centers at +/-1.40m")
	var minimum_separation := 100.0
	var files: Dictionary = {}
	for a: int in sample.size():
		if sample[a].distance > marches.GATE_LENGTH:
			var file_x := snappedf(sample[a].position.x, 0.001)
			if not files.has(file_x):
				files[file_x] = []
			files[file_x].append(sample[a].position.z)
		for b: int in range(a + 1, sample.size()):
			if sample[a].distance > marches.GATE_LENGTH and sample[b].distance > marches.GATE_LENGTH:
				minimum_separation = minf(minimum_separation, sample[a].position.distance_to(sample[b].position))
	var file_centers: Array = files.keys()
	file_centers.sort()
	var columns_even := file_centers.size() == 6
	var ranks_even := true
	var measured_rank_gaps := 0
	for index: int in file_centers.size():
		if index > 0:
			columns_even = columns_even and absf(file_centers[index] - file_centers[index - 1] - 0.56) < 0.002
		var ranks: Array = files[file_centers[index]]
		ranks.sort()
		for row: int in range(1, ranks.size()):
			measured_rank_gaps += 1
			ranks_even = ranks_even and absf(ranks[row] - ranks[row - 1] - 0.90) < 0.002
	_check(columns_even and minimum_separation >= 0.559, "Left and right files maintain the new 0.56m lateral spacing")
	_check(ranks_even and measured_rank_gaps >= 6, "Every file preserves 0.90m between consecutive expanded ranks")
	var multimesh: MultiMesh = marches.get_node("Militia").multimesh
	# Godot's headless Dummy renderer returns identity for MultiMesh readback.
	# Both modes check simulation geometry; a native renderer also checks its buffer.
	var has_renderer := DisplayServer.get_name() != "headless"
	_check(is_equal_approx(marches.MODEL_SCALE, 0.62), "Militia retain the enlarged 0.62 model scale")
	if has_renderer:
		_check(multimesh.get_instance_transform(0).basis.get_scale().is_equal_approx(Vector3.ONE * 0.62), "Native renderer stores the enlarged militia transforms")
	marches.send(0, 2, 0, 24, straight)
	_check(marches.total_for(0) == 66 and marches.incoming_for(2, 0) == 24, "Repeated commands append their full population")
	marches.tick(40.0)
	_check(marches.total_for(0) == 0 and _arrived.size() == 66, "Every soldier produces exactly one arrival")
	var strengthened := 0
	for arrival: Dictionary in _arrived:
		if arrival.target_id == 1 and arrival.strength == 1.25:
			strengthened += 1
	_check(strengthened == 42, "Arrival retains target, faction and strength")
	_arrived.clear()
	marches.clear()
	var reverse := PackedVector3Array([straight[1], straight[0]])
	marches.send(0, 1, 0, 60, straight)
	marches.send(1, 0, 1, 60, reverse)
	for frame: int in 100:
		marches.tick(0.05)
	_check(marches.total_for(0) == 60 and marches.total_for(1) == 60, "Opposing columns cross without roadside combat")
	var untouched: int = marches.total_for(0)
	var targets: Array[WarMarches.MarchUnit] = marches.acquire_targets(Vector3(0, 0, -15), 0, 7.0, 3)
	_check(targets.size() == 3 and marches.total_for(1) == 60, "Tower acquisition reserves real targets without killing them before impact")
	for target: WarMarches.MarchUnit in targets:
		marches.hit_target(target, Vector3.RIGHT)
	_check(marches.total_for(1) == 57, "Actual projectile hits remove the requested hostile soldiers")
	_check(marches.total_for(0) == untouched, "Tower fire leaves friendly soldiers intact")
	marches.tick(30.0)
	_check(_arrived.size() == 117, "Tower casualties never also arrive at a building")
	marches.clear()
	_arrived.clear()
	marches.send(0, 1, 0, 1, straight)
	marches.create_haste_zone(0, Vector3.ZERO, 12.0, 1.0, 2.0)
	marches.tick(2.0)
	var boosted: Dictionary = marches.get_units()[0]
	_check(is_equal_approx(boosted.distance, marches.SPEED * 3.0), "Haste expires at its exact duration within a long tick")
	marches.clear()
	marches.send(0, 1, 0, 4200, straight)
	_check(marches.total_for(0) == 4200 and marches.get_node("Militia").multimesh.instance_count >= 4200, "Renderer expands above its initial capacity without dropping population")
	var drain_time: float = (ceilf(4200.0 / marches.COLUMNS) * marches.ROW_SPACING + 30.0) / marches.SPEED + 1.0
	marches.tick(drain_time)
	_check(_arrived.size() == 4200 and marches.total_for(0) == 0, "Expanded capacity preserves all 4200 independent arrivals")
	marches.clear()
	_arrived.clear()
	# Shore turns sit 2.2m from the ravine edges: the map requires 2.1m for
	# a 1.40m outer lane plus the rotated enlarged militia mesh (about 0.63m).
	# This deliberately includes right-angle approach/departure turns at both bridges.
	var shore_margin := MAP_RULES.FORMATION_CLEARANCE + 0.1
	var bridge_route := PackedVector3Array([Vector3(-25, 0, 5), Vector3(-15 - shore_margin, 0, 5), Vector3(-15 - shore_margin, 0, 14), Vector3(-9 + shore_margin, 0, 14), Vector3(-9 + shore_margin, 0, 3), Vector3(9 - shore_margin, 0, 3), Vector3(9 - shore_margin, 0, -14), Vector3(15 + shore_margin, 0, -14), Vector3(25, 0, -14)])
	marches.send(0, 1, 0, 84, bridge_route)
	var left_road := false
	var bad_width := false
	var bridges_seen := [false, false]
	var mesh_bounds: AABB = multimesh.mesh.get_aabb()
	var footprint: Array[Vector3] = []
	var model_radius := 0.0
	for x: float in [mesh_bounds.position.x, mesh_bounds.end.x]:
		for z: float in [mesh_bounds.position.z, mesh_bounds.end.z]:
			footprint.append(Vector3(x, 0, z))
			model_radius = maxf(model_radius, Vector2(x, z).length() * marches.MODEL_SCALE)
	_check(1.40 + model_radius <= MAP_RULES.FORMATION_CLEARANCE, "Map clearance contains the outer file plus the actual rotated mesh bounds")
	var route_length: float = marches._units[0].order.length
	# Run until the last queued rank has crossed BOTH bridges, not just a fixed
	# 20-second window that stops around the second approach with the slower queue.
	var bridge_frames := ceili((route_length + 14.0 * marches.ROW_SPACING) / marches.SPEED * 60.0) + 2
	for frame: int in bridge_frames:
		marches.tick(1.0 / 60.0)
		for unit: Dictionary in marches.get_units():
			if absf(unit.lane) > 1.401:
				bad_width = true
		# Rotate all four full-model footprint corners; the Dummy backend needs
		# CPU poses, while native runs inspect the actual MultiMesh buffer instead.
		var slot := 0
		for unit in marches._units:
			if unit.distance < 0.0:
				continue
			var yaw := atan2(-unit.heading.x, -unit.heading.z)
			var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * marches.MODEL_SCALE)
			var pose := Transform3D(basis, unit.position)
			if has_renderer:
				pose = multimesh.get_instance_transform(slot)
			slot += 1
			for point: Vector3 in footprint:
				var p := pose * point
				if p.x > -15.0 and p.x < -9.0:
					bridges_seen[0] = true
					left_road = left_road or not preload("res://data/block_war/maps/rift.tres").is_walkable(Vector2(p.x, p.z))
				if p.x > 9.0 and p.x < 15.0:
					bridges_seen[1] = true
					left_road = left_road or not preload("res://data/block_war/maps/rift.tres").is_walkable(Vector2(p.x, p.z))
	_check(not left_road, "Entire outer files stay on the bridges instead of cutting ravine corners")
	_check(not bad_width, "Formation never exceeds the map's clearance budget")
	_check(bridges_seen[0] and bridges_seen[1] and _arrived.size() == 84, "All 84 soldiers traverse both bridges and are independently absorbed")
	marches.clear()
	_arrived.clear()
	marches.send(0, 1, 0, 6, straight)
	var traveled := 0.0
	var previous_width := -1.0
	var exit_monotonic := true
	for distance: float in [0.25, 0.6, 1.2, 1.8, 2.7, 4.0]:
		marches.tick((distance - traveled) / marches.SPEED)
		traveled = distance
		var width := 0.0
		for unit: Dictionary in marches.get_units():
			width = maxf(width, absf(unit.position.x))
		exit_monotonic = exit_monotonic and width >= previous_width - 0.001
		previous_width = width
		if distance == 0.25:
			_check(width < 0.15 and marches.get_units().size() == 6, "All six soldiers first emerge through a narrow 0.30m center funnel")
	_check(exit_monotonic and absf(previous_width - 1.40) < 0.002, "The exiting rank fans monotonically to its complete six-file width")
	var entry_monotonic := true
	for remaining: float in [2.7, 1.8, 1.2, 0.6, 0.25]:
		var distance := 30.0 - remaining
		marches.tick((distance - traveled) / marches.SPEED)
		traveled = distance
		var width := 0.0
		for unit: Dictionary in marches.get_units():
			width = maxf(width, absf(unit.position.x))
		entry_monotonic = entry_monotonic and width <= previous_width + 0.001
		previous_width = width
	_check(entry_monotonic and previous_width < 0.15 and marches.total_for(0) == 6, "The final rank contracts monotonically into the same entrance funnel before absorption")
	marches.tick(0.2)
	_check(_arrived.size() == 6 and marches.total_for(0) == 0, "The contracted rank fully enters the destination without losing or duplicating troops")
	marches.clear()
	var long_route := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -200)])
	marches.send(0, 1, 0, 700, long_route)
	# Include the complete source queue and the exit funnel at the current speed.
	marches.tick((ceilf(700.0 / marches.COLUMNS) * marches.ROW_SPACING + marches.GATE_LENGTH) / marches.SPEED)
	_check(marches.get_node("Militia").multimesh.visible_instance_count == 700, "700 simultaneously marching soldiers remain individually visible")
	var started := Time.get_ticks_usec()
	for frame: int in 180:
		marches.tick(1.0 / 60.0)
	var mean_ms := float(Time.get_ticks_usec() - started) / 180000.0
	_check(mean_ms < 1000.0 / 60.0, "The 700-soldier CPU update fits within one 60Hz frame")
	print("BLOCK_WAR_MARCHES_CPU 700 soldiers, mean tick ms=", mean_ms, " full-mesh clearance=", 1.40 + model_radius)
	marches.clear()
	marches.free()
	print("BLOCK_WAR_MARCHES ", _checks, " checks; ", _failures.size(), " failures")
	quit(0 if _failures.is_empty() else 1)
