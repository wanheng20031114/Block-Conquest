extends SceneTree
## Bear W carries an exact five-second tail through movement and status changes.
const MARCHES := preload("res://scenes/block_war/marches.tscn")
var marches: WarMarches
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL BEAR_SLOW ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s / %s" % [label, actual, expected])

func soldier(faction: int = 1) -> WarMarches.MarchUnit:
	marches.send(10 + faction, 20, faction, 1, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]))
	return marches._units[-1]

func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func(): quit(3))
	marches = MARCHES.instantiate()
	root.add_child(marches)
	_exit_and_allies()
	_expiry_and_overlap()
	_reentry_and_recall()
	_hidden_and_floating()
	_partition_and_prediction()
	marches.free()
	print("BEAR_SLOW checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _exit_and_allies() -> void:
	for faction: int in 6: soldier(faction)
	marches.create_slow_zone(0, Vector3.ZERO, WarMarches.SPEED * 0.4, 4.0)
	for unit: WarMarches.MarchUnit in marches._units:
		near(unit.slow_remaining, 5.0 if unit.order.faction % 2 == 1 else 0.0, "cast affects only enemies %d" % unit.order.faction)
	marches.tick(1.0)
	for unit: WarMarches.MarchUnit in marches._units:
		var enemy := unit.order.faction % 2 == 1
		near(unit.distance, WarMarches.SPEED * (0.4 if enemy else 1.0), "exact circle exit %d" % unit.order.faction)
		near(unit.slow_remaining, 5.0 if enemy else 0.0, "exit starts a complete tail %d" % unit.order.faction)
	marches.tick(4.5)
	check(marches.slow_zones.is_empty(), "ground field expires independently of affected soldiers")
	for unit: WarMarches.MarchUnit in marches._units:
		var enemy := unit.order.faction % 2 == 1
		near(unit.slow_remaining, 0.5 if enemy else 0.0, "tail remains after zone removal %d" % unit.order.faction)
		near(marches.speed_multiplier(unit), 0.4 if enemy else 1.0, "out-of-range speed %d" % unit.order.faction)
	marches.tick(1.0)
	for unit: WarMarches.MarchUnit in marches._units:
		near(unit.distance, WarMarches.SPEED * (6.0 * 0.4 + 0.5 if unit.order.faction % 2 == 1 else 6.5), "mid-frame expiry restores ordinary speed %d" % unit.order.faction)
		near(unit.slow_remaining, 0.0, "tail fully expired %d" % unit.order.faction)
		near(marches.speed_multiplier(unit), 1.0, "full speed restored %d" % unit.order.faction)

func _expiry_and_overlap() -> void:
	marches.clear()
	var unit := soldier()
	marches.create_slow_zone(0, Vector3.ZERO, 100.0, 4.0)
	marches.create_slow_zone(2, Vector3.ZERO, 100.0, 2.0)
	marches.create_slow_zone(4, Vector3.ZERO, 100.0, 3.0)
	marches.tick(4.0)
	near(unit.distance, WarMarches.SPEED * 4.0 * 0.4, "three overlapping zones slow only once")
	near(unit.slow_remaining, 5.0, "last zone expiry leaves five seconds, not a sum")
	marches.tick(6.0)
	near(unit.distance, WarMarches.SPEED * (9.0 * 0.4 + 1.0), "four seconds of field plus five of tail then ordinary motion")
	near(unit.slow_remaining, 0.0, "overlapping zones never accumulate extra tail")

func _reentry_and_recall() -> void:
	marches.clear()
	var unit := soldier()
	marches.create_slow_zone(0, Vector3.ZERO, WarMarches.SPEED * 0.4, 4.0)
	marches.tick(1.5)
	near(unit.slow_remaining, 4.5, "departing unit has consumed half a second of tail")
	var before := unit.position
	marches.redirect(unit, marches.return_order(unit.order))
	check(unit.position.is_equal_approx(before), "recall retains the actual soldier position")
	near(unit.slow_remaining, 4.5, "recall cannot cleanse the slow")
	marches.tick(0.75)
	near(unit.slow_remaining, 5.0, "returning through the same circle refreshes, rather than adds, the tail")
	near(unit.position.x, WarMarches.SPEED * 0.4 * 0.75, "reentry keeps formation-route motion")
	marches.tick(1.0)
	check(marches._units.is_empty(), "entering the building ends this march")
	marches.clear()
	var next := soldier()
	near(next.slow_remaining, 0.0, "a newly dispatched soldier does not inherit the previous march's debuff")

func _hidden_and_floating() -> void:
	marches.clear()
	var floating := soldier()
	var queued := soldier(3)
	queued.distance = -WarMarches.SPEED
	queued.pending_departure = true
	var tunnel := soldier(5)
	tunnel.spawn_delay = 2.0
	tunnel.pending_departure = true
	floating.levitation_remaining = 3.0
	marches.create_slow_zone(0, Vector3.ZERO, 100.0, 1.0)
	near(floating.slow_remaining, 5.0, "exposed floating soldier is affected immediately")
	near(queued.slow_remaining, 0.0, "hidden garrison queue is protected")
	near(tunnel.slow_remaining, 0.0, "hidden tunnel is protected")
	marches.tick(3.0)
	near(floating.distance, 0.0, "levitation still prevents all movement")
	near(floating.slow_remaining, 3.0, "slow ages from field expiry while levitating")
	near(queued.distance, WarMarches.SPEED * 2.0, "queue leaves only after this field expires")
	near(queued.slow_remaining, 0.0, "queue does not acquire an expired field")
	near(tunnel.slow_remaining, 0.0, "tunnel does not acquire an expired field")
	marches.tick(1.0)
	near(floating.distance, WarMarches.SPEED * 0.4, "landing retains the unexpired slow")
	near(floating.slow_remaining, 2.0, "landing cannot restart the tail")
	marches.clear()
	var emerging := soldier()
	emerging.distance = -WarMarches.SPEED * 0.5
	emerging.pending_departure = true
	marches.create_slow_zone(0, Vector3.ZERO, 100.0, 1.0)
	marches.tick(2.0)
	near(emerging.distance, WarMarches.SPEED * 1.5 * 0.4, "emergence starts slowing only after the half-second queue")
	near(emerging.slow_remaining, 4.0, "new contact receives the tail from field expiry")

func _partition_and_prediction() -> void:
	var expected: Array[PackedFloat64Array] = []
	for fine: bool in [false, true]:
		marches.clear()
		var route := PackedVector3Array([Vector3(-8, 0, -2), Vector3(-2, 0, -2), Vector3(0, 0, 0), Vector3(8, 0, 1), Vector3(70, 0, 1)])
		marches.send(1, 2, 1, 12, route)
		marches.create_slow_zone(0, Vector3.ZERO, 4.5, 4.0)
		marches.create_slow_zone(2, Vector3(6, 0, 1), 3.5, 3.5)
		marches.create_haste_zone(1, Vector3.ZERO, 6.0, 3.0, 1.6)
		for index: int in marches._units.size():
			var unit := marches._units[index]
			unit.rush_remaining = 6.0
			unit.order.pig_charge = true
			unit.levitation_remaining = 0.17 if index % 3 == 0 else 0.0
			unit.spawn_delay = 0.31 if index % 4 == 0 else 0.0
			unit.slow_remaining = 0.4 if index % 5 == 0 else 0.0
			if not fine:
				var before := unit.slow_remaining
				var forecast := marches.movement_with_slow(unit, 10.0)
				near(marches.movement_distance(unit, 10.0), forecast[0], "distance queries use the same pure integration %d" % index)
				near(unit.slow_remaining, before, "forecast cannot consume or refresh a real soldier's status %d" % index)
				expected.append(PackedFloat64Array([unit.distance + forecast[0], forecast[1]]))
		if fine:
			for frame: int in 1000: marches.tick(0.01)
		else:
			marches.tick(10.0)
		for index: int in marches._units.size():
			near(marches._units[index].distance, expected[index][0], "long/short frames agree with prediction %s/%d" % [fine, index])
			near(marches._units[index].slow_remaining, expected[index][1], "tail is independent of frame partitions %s/%d" % [fine, index])
