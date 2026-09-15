extends SceneTree
## Generated scripts are written only into the isolated diagnostic project by
## tools/movement_corridor_probe.py::corridor_differential_sources. Both reuse
## the frozen source's real prefix builder; the reference keeps its original scan.
var reference_script
var candidate_script
var checks: int = 0
var failures: Array[String] = []
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		if failures.size() <= 12: printerr("FAIL ", label)

func make_pair(kind: int) -> Array:
	var reference = reference_script.new()
	var candidate = candidate_script.new()
	for x: int in range(-32, 33):
		for z: int in range(-32, 33):
			var blocked: bool = false
			match kind:
				1: blocked = x in [-1, 0, 1] and z in [-1, 0, 1]
				2: blocked = x == 0 and z != 7
				3: blocked = (x * 7 + z * 13) % 23 == 0 and absi(x) < 28 and absi(z) < 28
			if not blocked:
				reference._walkable_cells[Vector2i(x, z)] = true
				candidate._walkable_cells[Vector2i(x, z)] = true
	reference._rebuild_corridor_prefix()
	candidate._rebuild_corridor_prefix()
	return [reference, candidate]

func compare(pair: Array, from: Vector3, to: Vector3, radius: float, label: String) -> void:
	var expected: bool = pair[0].has_clear_corridor(from, to, radius)
	var actual: bool = pair[1].has_clear_corridor(from, to, radius)
	check(actual == expected, "%s from=%s to=%s radius=%.9f expected=%s actual=%s" % [label, from, to, radius, expected, actual])

func close_pair(pair: Array) -> void:
	pair[0].free()
	pair[1].free()

func _run() -> void:
	# These resources only exist in the explicitly prepared isolated project.
	# Runtime loads keep the unprepared production editor free of missing-preload
	# errors; running this test without its generated fixtures is a setup failure.
	reference_script = load("res://tests/generated/movement_corridor_reference.gd")
	candidate_script = load("res://tests/generated/movement_corridor_candidate.gd")
	if reference_script == null or candidate_script == null:
		printerr("MOVEMENT_CORRIDOR_PROBE setup failure: generate the frozen-source fixtures first")
		quit(2)
		return
	rng.seed = 915400
	var radii: Array[float] = [0.0, 0.001, 0.2, 0.399, 0.4, 0.5, 0.78, 0.999, 1.0, 1.3, 2.0]
	for kind: int in 4:
		var pair: Array = make_pair(kind)
		for sample: int in 2400:
			var from := Vector3(rng.randf_range(-34.0, 34.0), 0, rng.randf_range(-34.0, 34.0))
			var to := Vector3(rng.randf_range(-34.0, 34.0), 0, rng.randf_range(-34.0, 34.0))
			var radius: float = radii[sample % radii.size()]
			compare(pair, from, to, radius, "random map=%d sample=%d" % [kind, sample])
			compare(pair, to, from, radius, "reverse map=%d sample=%d" % [kind, sample])
		# Deliberately sample cell boundaries and body-expanded contacts. The
		# +/- perturbations include less than, equal to and above float32 ULPs.
		for radius: float in radii:
			for offset: float in [-0.0011, -0.001, -0.0001, -0.000001, 0.0, 0.000001, 0.0001, 0.001, 0.0011]:
				for edge: float in [-32.0, -2.0, -1.0, 0.0, 1.0, 2.0, 32.0]:
					var aligned: float = edge + radius + 0.001 + offset
					for slope: float in [-1.0, -0.0000005, 0.0, 0.0000005, 1.0]:
						var from := Vector3(aligned, 0, -25.0)
						var to := Vector3(aligned + slope, 0, 25.0)
						compare(pair, from, to, radius, "vertical boundary map=%d" % kind)
						compare(pair, Vector3(from.z, 0, from.x), Vector3(to.z, 0, to.x), radius, "horizontal boundary map=%d" % kind)
		for radius: float in radii:
			compare(pair, Vector3(-20, 0, -20), Vector3(20, 0, 20), radius, "diagonal")
			compare(pair, Vector3(-20, 0, 20), Vector3(20, 0, -20), radius, "reverse diagonal")
			compare(pair, Vector3.ZERO, Vector3.ZERO, radius, "zero length")
		compare(pair, Vector3.INF, Vector3.ZERO, 0.4, "nonfinite from")
		compare(pair, Vector3.ZERO, Vector3(NAN, 0, 1), 0.4, "nonfinite to")
		for radius: float in [-0.1, INF, NAN]:
			compare(pair, Vector3.ZERO, Vector3.ONE, radius, "invalid radius")
		close_pair(pair)
	_short_axis_clear_fixture()
	_certificates_and_topology()
	var result := {"checks": checks, "failures": failures.size(), "seed": 915400, "candidate": "short_axis_scan"}
	print("MOVEMENT_CORRIDOR_PROBE ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _short_axis_clear_fixture() -> void:
	var pair: Array = make_pair(0)
	# The wide bounding rectangle includes this obstacle, but the narrow body
	# sweep passes to its left. X has five columns; Z spans about fifty rows.
	for item in pair:
		item._walkable_cells.erase(Vector2i(4, -20))
		item._revision += 1
		item._rebuild_corridor_prefix()
	var from := Vector3(0.2, 0, -25)
	var to := Vector3(4.2, 0, 25)
	check(pair[0].has_clear_corridor(from, to, 0.0), "reference exercises a clear diagonal with a blocked outer rectangle")
	check(pair[1].has_clear_corridor(from, to, 0.0), "short-axis scan preserves the clear diagonal")
	compare(pair, to, from, 0.0, "short-axis clear reverse")
	close_pair(pair)

func _certificates_and_topology() -> void:
	var open: Array = make_pair(0)
	var blocked: Array = make_pair(1)
	var reference_certificate = reference_script.Clearance.new()
	var candidate_certificate = candidate_script.Clearance.new()
	var certificates: Array = [reference_certificate, candidate_certificate]
	for item: int in 2:
		check(open[item].has_clear_corridor(Vector3(-4, 0, 0), Vector3(4, 0, 0), 0.4, certificates[item]), "open map certifies")
		check(not blocked[item].has_clear_corridor(Vector3(-4, 0, 0), Vector3(4, 0, 0), 0.4, certificates[item]), "different map rejects reused certificate")
		check(open[item].has_clear_corridor(Vector3(-4, 0, 0), Vector3(4, 0, 0), 0.4, certificates[item]), "open map recertifies")
		for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]:
			open[item]._walkable_cells.erase(cell)
		open[item]._revision += 1
		open[item]._rebuild_corridor_prefix()
		check(not open[item].has_clear_corridor(Vector3(-4, 0, 0), Vector3(4, 0, 0), 0.4, certificates[item]), "new topology invalidates same-tick certificate")
		check(open[item].has_clear_corridor(Vector3(-2.1, 0, -4), Vector3(-2.1, 0, 4), 0.4, certificates[item]), "small radius passes beside obstacle")
		check(not open[item].has_clear_corridor(Vector3(-2.1, 0, -4), Vector3(-2.1, 0, 4), 1.3, certificates[item]), "larger radius cannot inherit old proof")
		for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]:
			open[item]._walkable_cells[cell] = true
		open[item]._revision += 1
		open[item]._rebuild_corridor_prefix()
		check(open[item].has_clear_corridor(Vector3(-4, 0, 0), Vector3(4, 0, 0), 0.4, certificates[item]), "demolition restores a clear route")
	for sample: int in 300:
		var from := Vector3(-4.0 + sample * 0.001, 0, 0.1)
		var to := Vector3(4.0 - sample * 0.001, 0, 0.2)
		var expected: bool = open[0].has_clear_corridor(from, to, 0.4, reference_certificate)
		var actual: bool = open[1].has_clear_corridor(from, to, 0.4, candidate_certificate)
		check(actual == expected, "moving endpoints preserve cached proof")
	check(open[0].corridor_cache_hits > 100 and open[1].corridor_cache_hits > 100, "both differential versions actually hit positive certificates")
	close_pair(open)
	close_pair(blocked)
