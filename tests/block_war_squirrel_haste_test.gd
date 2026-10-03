extends SceneTree
## Squirrel W leaves three seconds of the same speed bonus on exposed marchers.
const MARCHES := preload("res://scenes/block_war/marches.tscn")
var marches: WarMarches
var checks := 0
var failures: Array[String] = []
var source_serial := 100

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL SQUIRREL_HASTE ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s / %s" % [label, actual, expected])

func reset() -> void:
	marches.clear()
	marches.environment_speed.fill(1.0)

func soldier(faction: int = 0, start: Vector3 = Vector3.ZERO) -> WarMarches.MarchUnit:
	source_serial += 1
	marches.send(source_serial, 20, faction, 1, PackedVector3Array([start, start + Vector3(100, 0, 0)]))
	return marches._units[-1]

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	marches = MARCHES.instantiate()
	root.add_child(marches)
	_exit_and_ownership()
	_field_expiry_and_refresh()
	_reentry_and_arrival()
	_hidden_and_floating()
	_stacked_speed()
	_partition_and_prediction()
	marches.free()
	print("SQUIRREL_HASTE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _exit_and_ownership() -> void:
	reset()
	for faction: int in 6: soldier(faction)
	# At 3.52 m/s, the own soldier leaves this circle after exactly one second.
	marches.create_haste_zone(0, Vector3.ZERO, 3.52, 8.0, 1.6)
	for unit: WarMarches.MarchUnit in marches._units:
		near(unit.haste_remaining, 3.0 if unit.order.faction == 0 else 0.0, "cast affects only this commander's exposed soldiers %d" % unit.order.faction)
		near(unit.haste_bonus, 0.6 if unit.order.faction == 0 else 0.0, "cast stores a single sixty-percent bonus %d" % unit.order.faction)
	marches.tick(1.0)
	var own := marches._units[0]
	near(own.distance, 3.52, "one second reaches the exact circle edge")
	near(own.haste_remaining, 3.0, "leaving the circle starts a full three-second tail")
	marches.tick(2.5)
	near(own.distance, 12.32, "the soldier retains all sixty percent after leaving")
	near(own.haste_remaining, 0.5, "tail counts down instead of following the ground field timer")
	near(marches.speed_multiplier(own), 1.6, "speed display includes the out-of-range buff")
	marches.tick(1.0)
	near(own.distance, 15.18, "mid-frame expiry includes four boosted seconds and half an ordinary second")
	near(own.haste_remaining, 0.0, "tail expires after three seconds outside")
	near(own.haste_bonus, 0.0, "expired bonus is cleared with its timer")
	near(marches.speed_multiplier(own), 1.0, "ordinary speed returns at expiry")
	for index: int in range(1, 6):
		near(marches._units[index].distance, 9.9, "allies and enemies receive no accidental haste %d" % index)

func _field_expiry_and_refresh() -> void:
	reset()
	var unit := soldier()
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 0.5, 1.6)
	marches.tick(1.0)
	check(marches.haste_zones.is_empty(), "the ground field ends independently of the soldier buff")
	near(unit.distance, 3.52, "a field ending within the frame leaves continuous acceleration")
	near(unit.haste_remaining, 2.5, "field expiry starts the same three-second tail as circle exit")
	marches.tick(3.0)
	near(unit.distance, 13.42, "half-second field plus three-second tail then half-second ordinary travel")
	near(unit.haste_remaining, 0.0, "field removal never leaves a permanent bonus")
	reset()
	unit = soldier()
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 10.0, 1.6)
	marches.tick(4.0)
	near(unit.haste_remaining, 3.0, "continuous contact refreshes to three seconds rather than accumulating")
	near(unit.haste_bonus, 0.6, "continuous contact does not stack the bonus")
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 2.0, 1.6)
	marches.tick(3.0)
	near(unit.distance, 24.64, "a replacement field never doubles acceleration")
	near(unit.haste_remaining, 2.0, "replacement refresh has one shared expiry")

func _reentry_and_arrival() -> void:
	reset()
	var unit := soldier()
	marches.create_haste_zone(0, Vector3.ZERO, 3.52, 8.0, 1.6)
	marches.tick(1.5)
	near(unit.haste_remaining, 2.5, "half a second outside consumes half a second of tail")
	var before := unit.position
	marches.redirect(unit, marches.return_order(unit.order))
	check(unit.position.is_equal_approx(before), "recall keeps the real soldier position")
	near(unit.haste_remaining, 2.5, "recall retains rather than restarts the tail")
	marches.tick(0.75)
	near(unit.position.x, 2.64, "returning soldier reenters the original circle")
	near(unit.haste_remaining, 3.0, "reentry refreshes the tail to three seconds")
	near(unit.haste_bonus, 0.6, "reentry still applies only one bonus")
	marches.tick(1.0)
	check(marches._units.is_empty(), "returning to the building finishes the affected march")
	var next := soldier(0, Vector3(20, 0, 0))
	near(next.haste_remaining, 0.0, "a new dispatch does not inherit the previous soldier's tail")
	near(next.haste_bonus, 0.0, "a new dispatch has no stale acceleration")

func _hidden_and_floating() -> void:
	reset()
	var floating := soldier()
	floating.levitation_remaining = 3.0
	var queued := soldier()
	queued.distance = -2.2
	queued.pending_departure = true
	var tunnel := soldier()
	tunnel.spawn_delay = 2.0
	tunnel.pending_departure = true
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 1.0, 1.6)
	near(floating.haste_remaining, 3.0, "an exposed floating soldier can receive haste")
	near(queued.haste_remaining, 0.0, "hidden garrison queue does not receive haste")
	near(tunnel.haste_remaining, 0.0, "hidden tunnel does not receive haste")
	var forecast := marches.haste_after_wait(floating, 3.0)
	near(forecast[0], 1.0, "stationary forecast ages haste from the field's expiry")
	near(forecast[1], 0.6, "stationary forecast retains the original bonus")
	near(floating.haste_remaining, 3.0, "stationary forecast cannot consume the real buff")
	marches.tick(3.0)
	near(floating.distance, 0.0, "haste cannot move a levitating soldier")
	near(floating.haste_remaining, 1.0, "haste expires normally while levitating")
	near(queued.distance, 4.4, "queue waits one second before two ordinary seconds of marching")
	near(queued.haste_remaining, 0.0, "emergence at field expiry grants no retroactive bonus")
	near(tunnel.distance, 2.2, "tunnel starts ordinary motion only after emerging")
	near(tunnel.haste_remaining, 0.0, "an expired field cannot buff the emerging tunnel soldier")
	marches.tick(2.0)
	near(floating.distance, 5.72, "landing gets one remaining boosted second then ordinary speed")
	reset()
	var emerging := soldier()
	emerging.distance = -1.1
	emerging.pending_departure = true
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 1.0, 1.6)
	marches.tick(2.0)
	near(emerging.distance, 5.28, "half-second doorway delay receives no haste before actual emergence")
	near(emerging.haste_remaining, 2.0, "emergence before expiry acquires the normal tail")

func _stacked_speed() -> void:
	reset()
	var unit := soldier()
	marches.environment_speed[0] = 1.5
	unit.rush_remaining = 2.0
	unit.order.pig_charge = true
	marches.create_haste_zone(0, Vector3.ZERO, 100.0, 0.5, 1.6)
	marches.create_slow_zone(1, Vector3.ZERO, 100.0, 0.5)
	near(marches.speed_multiplier(unit), 3.45, "morale multiplies the additive rush, charge, haste and slow bonuses once")
	marches.tick(2.0)
	near(unit.distance, 15.18, "first two seconds use the full additive skill group")
	near(marches.speed_multiplier(unit), 1.95, "rabbit expiry leaves pig charge and cancelling haste/slow")
	marches.tick(1.5)
	near(unit.distance, 21.615, "haste's remaining tail lasts until three and a half seconds")
	near(unit.haste_remaining, 0.0, "haste expires before the longer bear slow")
	near(marches.speed_multiplier(unit), 1.05, "bear tail applies once after haste expires")
	marches.tick(2.5)
	near(unit.distance, 28.38, "slow expiry within the frame restores permanent charge and morale speed")
	near(marches.speed_multiplier(unit), 1.95, "the original environment and charge bonuses survive temporary effects")

func _partition_and_prediction() -> void:
	var expected: Array[PackedFloat64Array] = []
	for fine: bool in [false, true]:
		reset()
		var route := PackedVector3Array([Vector3(-8, 0, -2), Vector3(-2, 0, -2), Vector3(0, 0, 0), Vector3(8, 0, 1), Vector3(100, 0, 1)])
		marches.send(1, 2, 0, 12, route)
		marches.create_haste_zone(0, Vector3.ZERO, 4.5, 4.0, 1.6)
		marches.create_slow_zone(1, Vector3(6, 0, 1), 3.5, 5.0)
		marches.environment_speed[0] = 1.4
		for index: int in marches._units.size():
			var unit := marches._units[index]
			unit.rush_remaining = 3.0
			unit.order.pig_charge = true
			unit.levitation_remaining = 0.17 if index % 3 == 0 else 0.0
			unit.spawn_delay = 0.31 if index % 4 == 0 else 0.0
			unit.slow_remaining = 0.4 if index % 5 == 0 else 0.0
			if not fine:
				var before := PackedFloat64Array([unit.distance, unit.slow_remaining, unit.haste_remaining, unit.haste_bonus, unit.rush_remaining, unit.spawn_delay, unit.levitation_remaining])
				var forecast := marches.movement_with_slow(unit, 8.0)
				near(marches.movement_distance(unit, 8.0), forecast[0], "distance-only queries share the pure integration %d" % index)
				check(before == PackedFloat64Array([unit.distance, unit.slow_remaining, unit.haste_remaining, unit.haste_bonus, unit.rush_remaining, unit.spawn_delay, unit.levitation_remaining]), "prediction cannot consume or refresh the actual soldier %d" % index)
				expected.append(PackedFloat64Array([unit.distance + forecast[0], forecast[1], forecast[2], forecast[3]]))
		if fine:
			for frame: int in 800: marches.tick(0.01)
		else:
			marches.tick(8.0)
		check(marches._units.size() == 12, "all twelve curved-lane marchers remain in this movement fixture")
		for index: int in marches._units.size():
			var unit := marches._units[index]
			near(unit.distance, expected[index][0], "long/short frames agree with predicted distance %s/%d" % [fine, index])
			near(unit.slow_remaining, expected[index][1], "slow tail is independent of frame partitions %s/%d" % [fine, index])
			near(unit.haste_remaining, expected[index][2], "haste tail is independent of frame partitions %s/%d" % [fine, index])
			near(unit.haste_bonus, expected[index][3], "haste magnitude is independent of frame partitions %s/%d" % [fine, index])
