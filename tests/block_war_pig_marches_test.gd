extends SceneTree
## Pig order persistence, exact doorway accounting and true terrain-free flight.

const MARCHES := preload("res://scenes/block_war/marches.tscn")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var checks := 0
var failures: Array[String] = []
var marches: WarMarches
var reservations := 0
var departures := 0
var arrivals: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func near(value: float, expected: float, message: String, tolerance: float = 0.0001) -> void:
	check(absf(value - expected) <= tolerance, "%s (%.6f / %.6f)" % [message, value, expected])

func reset() -> void:
	marches.clear()
	marches.map_definition = WarMapDefinition.new()
	marches.environment_speed.fill(1.0)
	reservations = 0
	departures = 0
	arrivals.clear()

func _run() -> void:
	marches = MARCHES.instantiate()
	root.add_child(marches)
	marches.departure_queue_changed.connect(func(_source: int, _faction: int, amount: int): reservations += amount)
	marches.unit_departed.connect(func(_source: int, _faction: int): departures += 1)
	marches.unit_arrived.connect(func(target: int, faction: int, strength: float, attack: float, energy_origin: bool): arrivals.append({"target": target, "faction": faction, "strength": strength, "attack": attack, "energy": energy_origin}))
	_charge_and_doorway()
	_dense_queue()
	_flight_and_recall()
	_ground_fire()
	marches.queue_free()
	await process_frame
	print("BLOCK_WAR_PIG_MARCHES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _charge_and_doorway() -> void:
	reset()
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	marches.environment_speed[0] = 1.5
	marches.queue_departure(0, 1, 0, 1, route, true, true)
	var unit := marches._units[0]
	check(departures == 1 and reservations == 0, "An immediately exposed one-person order pays exactly once")
	near(marches.speed_multiplier(unit), 1.8, "Charge +20% multiplies the existing morale speed")
	near(marches.movement_distance(unit, 1.0), 3.1 * 1.5 * 1.2, "Charge changes actual movement, not just its displayed multiplier")
	near(marches.projected_attack_bonus(unit), 0.1, "Pig charge provides ten percentage points of attack throughout a long march")
	unit.rush_remaining = 30.0
	near(marches.speed_multiplier(unit), 3.3, "Charge and rabbit rush add within the skill multiplier")
	near(marches.projected_attack_bonus(unit), 0.1 + RULES.RABBIT_RUSH_ATTACK_BONUS, "Rabbit attack and pig attack stack without overwriting each other")
	unit.weakened = true
	near(marches.projected_attack_bonus(unit), 0.1 + RULES.RABBIT_RUSH_ATTACK_BONUS - RULES.FROG_WEAKNESS, "Weakness still subtracts from the stacked attack bonus")
	unit.rush_remaining = 0.0
	unit.weakened = false
	marches.tick(40.0)
	check(arrivals.size() == 1 and arrivals[0].energy and arrivals[0].strength == 1.0, "Arrival preserves real population and energy-origin provenance")
	near(arrivals[0].attack, 0.1, "The destination receives the permanent per-march pig attack")
	reset()
	marches.queue_departure(0, 1, 0, 60, route)
	var preceding := marches._units[-1]
	marches.queue_departure(0, 2, 0, 1, route, false, true)
	unit = marches._units[-1]
	check(unit.distance < preceding.distance and unit.pending_departure, "A later enchanted order joins behind the existing building queue")
	var delay := -unit.distance / marches.base_speed(0)
	near(marches.movement_distance(unit, delay * 0.5), -unit.distance * 0.5, "Charge does not accelerate reserved soldiers still inside their building")
	near(marches.movement_distance(unit, delay + 1.0), -unit.distance + marches.SPEED * 1.2, "A long tick splits ordinary waiting from boosted movement at the actual exit")
	near(marches.speed_multiplier(unit), 1.0, "Pending charge soldiers report the unboosted queue speed")
	var expected := marches.movement_distance(unit, delay + 1.0)
	var before := unit.distance
	for index: int in 200:
		marches.tick((delay + 1.0) / 200.0)
	near(unit.distance - before, expected, "Doorway charge movement is independent of frame partition", 0.0005)
	check(reservations == 0 and departures == 61, "Queued normal and charge orders debit every reserved soldier exactly once")
	reset()
	marches.queue_departure(0, 1, 0, 1, route, false, true)
	unit = marches._units[0]
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 0.5, 1.6)
	marches.create_slow_zone(1, Vector3.ZERO, 100.0, 0.25)
	near(marches.movement_distance(unit, 1.0), marches.SPEED * (1.2 + 0.6 * 0.5 - 0.6 * 0.25), "Charge retains exact haste and slow expiry integration")

func _dense_queue() -> void:
	reset()
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	marches.queue_departure(0, 1, 0, 60, route, false, false, false, true)
	check(reservations == 60 and departures == 0, "Six even files start as real reservations inside the doorway")
	for column: int in 5:
		near(marches._units[column + 1].lane - marches._units[column].lane, 0.44, "Dense formations retain six files with 0.44m lane spacing")
	for row: int in range(1, 10):
		near(marches._units[(row - 1) * 6].distance - marches._units[row * 6].distance, 0.50, "Dense queued rows are separated by 0.50m")
	marches.tick(3.0)
	check(reservations == 0 and departures == 60 and marches.total_for(0) == 60, "Dense departure speeds up the complete queue without losing or duplicating population")
	var minimum := INF
	for first: int in marches._units.size():
		for second: int in range(first + 1, marches._units.size()):
			minimum = minf(minimum, marches._units[first].position.distance_to(marches._units[second].position))
	check(minimum >= 0.439, "Expanded dense files remain distinct rather than sharing positions")
	reset()
	marches.queue_departure(0, 1, 0, 12, route, false, false, false, true)
	var last_dense := marches._units[-1].distance
	marches.queue_departure(0, 2, 0, 6, route)
	var first_normal := marches._units[12].distance
	check(last_dense - first_normal >= marches.ROW_SPACING, "Switching from dense to normal orders keeps a safe shared-queue gap")
	marches.trim_departures(0, 0, 5)
	check(reservations == 5 and marches.total_for(0) == 5, "Garrison casualties trim dense reservations with ordinary conservation rules")
	for unit: WarMarches.MarchUnit in marches._units:
		check(unit.order.target_id == 1 and unit.order.dense, "Queue trimming still preserves the oldest dense order")

func _flight_and_recall() -> void:
	reset()
	marches.map_definition = preload("res://data/block_war/maps/terraces.tres")
	var from := marches.map_definition.surface_point(Vector3(-25, 0, 0))
	var to := marches.map_definition.surface_point(Vector3(25, 0, 0))
	var route := marches.make_flight_route(from, to)
	check(route[0].is_equal_approx(from) and route[-1].is_equal_approx(to), "Flight endpoints preserve the exact building exits")
	for point: Vector3 in route:
		near(point.z, 0.0, "Flight follows the direct horizontal line across elevated terrain")
		check(point.y >= marches.map_definition.surface_height(Vector2(point.x, point.z)) - 0.001, "Flight stays above terrain throughout takeoff, cruise and landing")
	marches.queue_departure(0, 1, 0, 6, route, true, true, true, true)
	marches.tick(0.1)
	var unit := marches._units[0]
	check(unit.heading.is_equal_approx(Vector3.RIGHT), "A vertically ascending soldier faces its horizontal destination")
	unit.distance = unit.order.length * 0.5
	marches._update_pose(unit)
	near(unit.position.y, marches.map_definition.terrain.max_height + 2.5, "Formation pose keeps the real cruise altitude instead of snapping to terrain", 0.001)
	unit.presentation_offset = Vector3(0.2, 0.1, -0.2)
	check(marches._presentation_position(unit).is_equal_approx(unit.position + unit.presentation_offset + Vector3(0, 0.035, 0)), "Client interpolation preserves airborne altitude across terrain changes")
	unit.presentation_offset = Vector3.ZERO
	check(marches.tower_can_target(unit), "Flight does not inherit frog levitation immunity to towers")
	var before := unit.position
	var outbound := unit.order
	var returning := marches.return_order(outbound)
	var preview := marches.return_preview(unit, returning)
	check(preview[0].is_equal_approx(before) and preview[-1].is_equal_approx(from), "Recall preview starts at the true flying pose and ends at its original building")
	check(preview[1].y > marches.map_definition.surface_height(Vector2(preview[1].x, preview[1].z)), "Recall preview follows the airborne return path")
	marches.redirect(unit, returning)
	check(unit.position.is_equal_approx(before), "Airborne recall keeps the same soldier at the exact same world position")
	check(returning.pig_charge and returning.airborne and returning.dense and returning.energy_origin, "Recall retains all pig modifiers and order provenance")
	var converted := marches.transfer_order(returning, 1)
	check(converted.pig_charge and converted.airborne and converted.dense and converted.returning and converted.energy_origin, "Recruitment or surrender transfer preserves all flight and charge properties")
	check(converted.faction == 1 and converted.order_id != returning.order_id and converted.curve == returning.curve, "Transferred flight gets a new snapshot identity while keeping its route")
	var short_route := marches.make_flight_route(from, from + Vector3(0.2, 0, 0))
	var last_x := from.x
	for point: Vector3 in short_route:
		check(point.is_finite() and point.x >= last_x - 0.000001 and point.x <= from.x + 0.200001, "Very short flights have finite smooth takeoff/landing and never overshoot")
		last_x = point.x

func _ground_fire() -> void:
	reset()
	var from := Vector3.ZERO
	var to := Vector3(30, 0, 0)
	var route := marches.make_flight_route(from, to)
	marches.queue_departure(0, 1, 0, 1, route, false, false, true)
	var unit := marches._units[0]
	unit.distance = unit.order.length * 0.5
	marches._update_pose(unit)
	marches.ignite_at(Vector3(15, 0, 0), 2.0, 1)
	check(unit.alive, "Ground ignition does not burn a soldier cruising directly above its core")
	var fire := {"center": Vector3(15, 0, 0), "from_radius": 3.0, "to_radius": 3.0, "active_fraction": 1.0, "faction": 1}
	marches.tick(0.5, [fire])
	check(unit.alive, "Ground fire expansion also leaves cruising soldiers intact")
	var targets := marches.acquire_targets(unit.position, 1, 5.0, 1, false, true)
	check(targets.size() == 1 and marches.hit_target(unit, Vector3.DOWN, true), "A real tower projectile can target and kill a flying soldier")
	reset()
	marches.queue_departure(0, 1, 0, 1, route, false, false, true)
	marches.tick(30.0, [fire])
	check(arrivals.size() == 1 and departures == 1, "One long frame flying over ground fire still reaches the destination exactly once")
	reset()
	marches.queue_departure(0, 1, 0, 1, route, false, false, true)
	fire.center = to
	marches.tick(30.0, [fire])
	check(arrivals.is_empty() and not marches.has_marchers() and departures == 1, "A flight that lands inside active ground fire dies on landing rather than arriving")
	reset()
	marches.queue_departure(0, 1, 0, 1, route, false, false, true)
	marches.ignite_at(from, 2.0, 1)
	check(not marches.has_marchers() and departures == 1, "Flight is still vulnerable before it has lifted out of ground fire")
