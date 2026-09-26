extends RefCounted
## Deliberate, paid skill decisions from the same visible battlefield as the player.

const DECISION_GAP := 6.0
const FIRE_CELL := 4.0
var faction: int
var next_decision: float

func _init(controlled_faction: int) -> void:
	faction = controlled_faction
	next_decision = 6.0 + 0.45 * (faction - 1)

func take_turn(game: Node3D) -> void:
	if game.finished or game._local_menu or game.elapsed < next_decision:
		return
	# Never chain four casts in one frame, including repeated calls at the same time.
	next_decision = game.elapsed + DECISION_GAP
	var visible: Array[WarMarches.MarchUnit] = []
	var threats: Dictionary[int, float] = {}
	var moving := 0
	var travel := 0.0
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.distance < 0.0:
			continue
		visible.append(unit)
		var speed: float = WarMarches.SPEED * (1.7 if game.faction_skills[unit.order.faction].durations[1] > 0.0 else 1.0)
		var arrival := (unit.order.length - unit.distance) / speed
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if game.FACTIONS.hostile(unit.order.faction, faction) and game.FACTIONS.allied(target.faction, faction) and arrival <= 7.0:
			threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * game.combat_multiplier(unit.order.faction, target)
		if unit.order.faction == faction and arrival >= 3.0:
			moving += 1
			travel += minf(8.0, arrival)
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	if game.can_cast_skill(2, faction):
		for id: int in threats:
			var building: WarBuilding = game.by_id[id]
			if not game._valid_skill_target(2, building, faction):
				continue
			var danger := threats[id]
			if danger < 8.0 or danger < building.population * 0.55:
				continue
			var score := minf(danger * 0.5, 45.0) + (28.0 if danger >= building.population else 12.0)
			if score > best.score:
				best = {"index": 2, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(0, faction) and game.faction_skills[faction].energy >= 65.0:
		for building: WarBuilding in game.buildings:
			if not game._valid_skill_target(0, building, faction) or building.conversion_target in [1, 2]:
				continue
			# Supply an active front or a drained residence, not an unused giant stockpile.
			if building.population > maxf(building.capacity + 30.0, 90.0):
				continue
			var danger: float = threats.get(building.building_id, 0.0)
			if danger > building.population + 20.0:
				continue # Six-second recruitment cannot rescue an immediately lost house.
			var score := 18.0 + maxf(0.0, 30.0 - building.population) * 0.25
			score += 5.0 if building.faction == faction else 0.0
			score += 8.0 if danger > building.population * 0.4 else 0.0
			if score > best.score:
				best = {"index": 0, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(1, faction) and moving >= 16 and game.faction_skills[faction].energy >= 60.0:
		var score := moving * 0.45 + travel * 0.065
		if score > best.score:
			best = {"index": 1, "score": score, "target": null, "at": Vector3.ZERO}
	if game.can_cast_skill(3, faction):
		var fire := _fire_target(game, visible)
		if not fire.is_empty() and fire.score > best.score:
			best = {"index": 3, "score": fire.score, "target": null, "at": fire.at}
	if best.index == 3:
		game.cast_ground_skill(3, best.at, faction)
	elif best.index >= 0:
		game.cast_skill(best.index, best.target, faction)

func _fire_target(game: Node3D, visible: Array[WarMarches.MarchUnit]) -> Dictionary:
	# Bin short-horizon estimates once. Evaluate at most 24 occupied cells and
	# their neighbors, rather than comparing every soldier against every other.
	var cells: Dictionary[Vector2i, Array] = {}
	var hostile_counts: Dictionary[Vector2i, int] = {}
	var friendly_paths: Array[Dictionary] = []
	var friendly_routes: Dictionary[WarMarches.MarchOrder, Vector3] = {}
	# Check the entire burn window, including known allied doorway queues. A
	# short-lived friendly near its destination must not disappear from this test.
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not game.FACTIONS.allied(unit.order.faction, faction):
			continue
		var speed := WarMarches.SPEED * (1.7 if game.faction_skills[unit.order.faction].durations[1] > 0.0 else 1.0)
		var end := minf(unit.order.length, unit.distance + speed * (WarFireWave.WINDUP_TIME + WarFireWave.BURN_TIME))
		if end < 0.0:
			continue
		var start := maxf(0.0, unit.distance)
		var span: Vector3 = friendly_routes.get(unit.order, Vector3(start, end, 0.0))
		friendly_routes[unit.order] = Vector3(minf(span.x, start), maxf(span.y, end), maxf(span.z, absf(unit.lane) + 0.7))
	# Ranks share one curve: test their combined corridor once per order, rather
	# than resampling the same route for hundreds of neighboring soldiers.
	for order: WarMarches.MarchOrder in friendly_routes:
		var span := friendly_routes[order]
		var previous := order.curve.sample_baked(span.x)
		var samples := maxi(1, ceili((span.y - span.x) / 1.5))
		for sample: int in samples:
			var point := order.curve.sample_baked(lerpf(span.x, span.y, float(sample + 1) / samples))
			friendly_paths.append({"from": previous, "to": point, "padding": span.z})
			previous = point
	for unit: WarMarches.MarchUnit in visible:
		if not game.FACTIONS.hostile(unit.order.faction, faction):
			continue
		var speed: float = WarMarches.SPEED * (1.7 if game.faction_skills[unit.order.faction].durations[1] > 0.0 else 1.0)
		var lead := speed * (WarFireWave.WINDUP_TIME + 0.3)
		if unit.distance + lead >= unit.order.length:
			continue
		var at := unit.order.curve.sample_baked(unit.distance + lead)
		var cell := Vector2i(floori(at.x / FIRE_CELL), floori(at.z / FIRE_CELL))
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(at)
		hostile_counts[cell] = hostile_counts.get(cell, 0) + 1
	var candidates := hostile_counts.keys()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return hostile_counts[a] > hostile_counts[b])
	var best := {}
	for cell: Vector2i in candidates.slice(0, 24):
		var at := Vector3((cell.x + 0.5) * FIRE_CELL, 0.0, (cell.y + 0.5) * FIRE_CELL)
		if not game._valid_ground_skill_target(at):
			continue
		var threatened := false
		for fire: WarFireWave in game.world_effects.get_node("FireWaves").get_children():
			if fire.age < WarFireWave.BURN_TIME and fire.global_position.distance_to(at) < game.IMPACT_RADIUS * 1.5:
				threatened = true
		if threatened:
			continue
		var enemies := 0
		var unsafe := false
		for path: Dictionary in friendly_paths:
			var closest := Geometry3D.get_closest_point_to_segment(at, path.from, path.to)
			if closest.distance_to(at) <= game.IMPACT_RADIUS + path.padding:
				unsafe = true
				break
		if unsafe:
			continue
		for x: int in range(-2, 3):
			for y: int in range(-2, 3):
				for point: Vector3 in cells.get(cell + Vector2i(x, y), []):
					enemies += int(point.distance_to(at) <= game.IMPACT_RADIUS - 0.6)
		# Friendly fire remains real. Do not knowingly burn even a small allied escort.
		if enemies < 8:
			continue
		var score := float(enemies) * 2.2
		if best.is_empty() or score > best.score:
			best = {"at": at, "score": score}
	return best
