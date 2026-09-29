extends SceneTree
## Exact movement equivalence; generated variants change only a zero-time guard.
const MARCHES := preload("res://scenes/block_war/marches.tscn")
var checks := 0
var failures: Array[String] = []
var rounds := 5
var frames := 120
var soldiers := 4096

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ZERO_STEP ", label)

func make_marches(label: String) -> WarMarches:
	var value: WarMarches = MARCHES.instantiate()
	value.set_script(load("res://.local/zero-step-fields/%s.gd" % label))
	root.add_child(value)
	value.send(0, 1, 0, soldiers, PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0)]))
	for i: int in soldiers:
		value._units[i].distance = 0.05 + float(i) * 350.0 / soldiers
	return value

func configure(marches: WarMarches, label: String) -> void:
	marches.haste_zones.clear()
	marches.slow_zones.clear()
	if label not in ["no_fields", "slow_only"]:
		marches.haste_zones[0] = {"at": Vector3(130, 0, 0), "radius": 120.0, "remaining": 0.4, "multiplier": 1.5}
	if label not in ["no_fields", "haste_only"]:
		marches.slow_zones[1] = {"at": Vector3(230, 0, 0), "radius": 190.0, "remaining": 0.35}
	for unit: WarMarches.MarchUnit in marches._units:
		unit.rush_remaining = 0.2 if label == "full_rush" else (0.012 if label == "partial_rush" else 0.0)
		unit.spawn_delay = 0.0
		unit.levitation_remaining = 0.0
		unit.order.haste_intervals.clear()
		unit.order.slow_intervals.clear()

func scan(marches: WarMarches) -> float:
	var distance := 0.0
	for unit: WarMarches.MarchUnit in marches._units:
		distance += marches.movement_distance(unit, 1.0 / 30.0)
	return distance

func statistics(samples: Array[float]) -> Dictionary:
	var ordered := samples.duplicate()
	ordered.sort()
	var total := 0.0
	for value: float in ordered: total += value
	return {"mean_ms": total / ordered.size(), "p95_ms": ordered[ceili(ordered.size() * 0.95) - 1],
		"p99_ms": ordered[ceili(ordered.size() * 0.99) - 1]}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: rounds = int(args[0])
	if args.size() > 1: frames = int(args[1])
	if args.size() > 2: soldiers = int(args[2])
	var reference := make_marches("reference")
	var candidate := make_marches("candidate")
	for scenario: String in ["no_fields", "haste_only", "slow_only", "no_rush", "full_rush", "partial_rush"]:
		configure(reference, scenario)
		configure(candidate, scenario)
		for i: int in soldiers:
			for step: float in [0.0, 0.00000001, 0.00000009, 0.00000011, 0.012, 0.015, 1.0 / 30.0, 0.2, 0.35, 0.4, 0.5]:
				check(reference.movement_distance(reference._units[i], step) == candidate.movement_distance(candidate._units[i], step), "%s soldier %d step %s exact movement" % [scenario, i, step])
		for round_index: int in rounds:
			var sums := {}
			for label: String in (["reference", "candidate"] if round_index % 2 == 0 else ["candidate", "reference"]):
				var marches: WarMarches = reference if label == "reference" else candidate
				for _warmup: int in 10: scan(marches)
				var samples: Array[float] = []
				var distance := 0.0
				for _frame: int in frames:
					var start := Time.get_ticks_usec()
					distance = scan(marches)
					samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
				sums[label] = distance
				print("ZERO_STEP_FIELDS ", JSON.stringify({"case": scenario, "round": round_index, "variant": label,
					"soldiers": soldiers, "frames": frames, "distance_sum": distance, "statistics": statistics(samples), "samples_ms": samples}))
			check(sums.reference == sums.candidate and sums.candidate > 0.0, "%s round %d identical nonempty work" % [scenario, round_index])
	# Omitted memoization on a zero interval must not affect the following live
	# interval, including concealed units, queue exits and overlapping expiries.
	configure(reference, "no_rush")
	configure(candidate, "no_rush")
	for i: int in mini(soldiers, 192):
		var a := reference._units[i]
		var b := candidate._units[i]
		a.spawn_delay = float(i % 7) * 0.017
		b.spawn_delay = a.spawn_delay
		a.levitation_remaining = float(i % 5) * 0.02
		b.levitation_remaining = a.levitation_remaining
		a.distance = -0.01 if i % 3 == 0 else float(i) * 1.71
		b.distance = a.distance
		a.rush_remaining = float(i % 4) * 0.019
		b.rush_remaining = a.rush_remaining
		for step: float in [0.0, 0.001, 0.03333333333333, 0.19, 0.4, 0.7]:
			check(reference.movement_distance(a, step) == candidate.movement_distance(b, step), "concealed/queued/expiry soldier %d exact movement" % i)
	reference.free()
	candidate.free()
	print("ZERO_STEP_CHECKS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
