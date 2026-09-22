extends SceneTree
## Population conservation, actual formation geometry, queues and tower targeting.

const MARCHES := preload("res://scenes/block_war/marches.tscn")
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
	marches.send(0, 1, 0, 42, straight, 1.25)
	_check(marches.total_for(0) == 42, "Queued and visible population are both conserved")
	_check(marches.incoming_for(1, 0) == 42, "Incoming intelligence includes the door queue")
	marches.tick(1.0)
	var sample: Array = marches.get_units()
	_check(sample.size() > 12 and sample.size() < 42, "Soldiers emerge over several ranks instead of all at once")
	var widest := 0.0
	for unit: Dictionary in sample:
		widest = maxf(widest, absf(unit.position.x))
	_check(widest > 1.1 and widest <= 1.126, "Six-file formation expands to its designed width")
	var minimum_separation := 100.0
	for a: int in sample.size():
		for b: int in range(a + 1, sample.size()):
			if sample[a].distance > 2.4 and sample[b].distance > 2.4:
				minimum_separation = minf(minimum_separation, sample[a].position.distance_to(sample[b].position))
	_check(minimum_separation >= 0.44, "Expanded ranks preserve even spacing")
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
	var hit: Vector3 = marches.damage_near(Vector3(0, 0, -15), 0, 7.0, 3)
	_check(hit != Vector3.INF and marches.total_for(1) == 57, "Tower fire removes the requested hostile soldiers")
	_check(marches.total_for(0) == untouched, "Tower fire leaves friendly soldiers intact")
	marches.tick(30.0)
	_check(_arrived.size() == 117, "Tower casualties never also arrive at a building")
	marches.clear()
	_arrived.clear()
	marches.send(0, 1, 0, 1, straight)
	marches.boost_faction(0, 1.0, 2.0)
	marches.tick(2.0)
	var boosted: Dictionary = marches.get_units()[0]
	_check(is_equal_approx(boosted.distance, marches.SPEED * 3.0), "Haste expires at its exact duration within a long tick")
	marches.clear()
	marches.send(0, 1, 0, 4200, straight)
	_check(marches.total_for(0) == 4200 and marches.get_node("Militia").multimesh.instance_count >= 4200, "Renderer expands above its initial capacity without dropping population")
	marches.tick(200.0)
	_check(_arrived.size() == 4200 and marches.total_for(0) == 0, "Expanded capacity preserves all 4200 independent arrivals")
	marches.clear()
	_arrived.clear()
	# Both ravines are crossed through a six-meter bridge; the route has 1.6m clearance.
	var bridge_route := PackedVector3Array([Vector3(-25, 0, 5), Vector3(-17, 0, 5), Vector3(-17, 0, 14), Vector3(-7, 0, 14), Vector3(-7, 0, 3), Vector3(7, 0, 3), Vector3(7, 0, -14), Vector3(17, 0, -14), Vector3(25, 0, -14)])
	marches.send(0, 1, 0, 84, bridge_route)
	var left_road := false
	var bad_width := false
	for frame: int in 1200:
		marches.tick(1.0 / 60.0)
		for unit: Dictionary in marches.get_units():
			var p: Vector3 = unit.position
			# Include the full model's 0.371m maximum lateral projection.
			if (p.x > -15.37 and p.x < -8.63) and absf(p.z - 14.0) > 2.63:
				left_road = true
			if (p.x > 8.63 and p.x < 15.37) and absf(p.z + 14.0) > 2.63:
				left_road = true
			if absf(unit.lane) > 1.126:
				bad_width = true
	_check(not left_road, "Entire outer files stay on the bridges instead of cutting ravine corners")
	_check(not bad_width, "Formation never exceeds the map's clearance budget")
	marches.clear()
	marches.send(0, 1, 0, 6, straight)
	marches.tick(0.3)
	var exit_width := 0.0
	for unit: Dictionary in marches.get_units():
		exit_width = maxf(exit_width, absf(unit.position.x))
	_check(exit_width < 0.4, "The first rank emerges from a narrow doorway")
	marches.tick(1.0)
	var field_width := 0.0
	for unit: Dictionary in marches.get_units():
		field_width = maxf(field_width, absf(unit.position.x))
	_check(field_width > 1.12, "The exiting rank smoothly fans into six files")
	marches.tick(7.1)
	var entry_width := 0.0
	for unit: Dictionary in marches.get_units():
		entry_width = maxf(entry_width, absf(unit.position.x))
	_check(entry_width < 0.55 and marches.total_for(0) == 6, "The final rank contracts toward the entrance before being absorbed")
	marches.clear()
	var long_route := PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -200)])
	marches.send(0, 1, 0, 700, long_route)
	marches.tick(30.0)
	_check(marches.get_node("Militia").multimesh.visible_instance_count == 700, "700 simultaneously marching soldiers remain individually visible")
	var started := Time.get_ticks_usec()
	for frame: int in 180:
		marches.tick(1.0 / 60.0)
	print("BLOCK_WAR_MARCHES_CPU 700 soldiers, mean tick ms=", float(Time.get_ticks_usec() - started) / 180000.0)
	marches.clear()
	marches.free()
	print("BLOCK_WAR_MARCHES ", _checks, " checks; ", _failures.size(), " failures")
	quit(0 if _failures.is_empty() else 1)
