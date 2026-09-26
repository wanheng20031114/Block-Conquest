extends RefCounted
## Deliberate, paid skill decisions from the same visible battlefield as the player.

const DECISION_GAP := 6.0
const FIRE_CELL := 4.0
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
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
	if game.faction_skills[faction].commander == SKILL_RULES.RABBIT:
		_rabbit_turn(game)
		return
	var visible: Array[WarMarches.MarchUnit] = []
	var threats: Dictionary[int, float] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed():
			continue
		visible.append(unit)
		var imminent: bool = game.marches.movement_distance(unit, 7.0) >= unit.order.length - unit.distance
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if game.FACTIONS.hostile(unit.order.faction, faction) and game.FACTIONS.allied(target.faction, faction) and imminent:
			threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * game.combat_multiplier(unit.order.faction, target, game.marches.projected_attack_bonus(unit))
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	if game.can_cast_skill(2, faction):
		for id: int in threats:
			var building: WarBuilding = game.by_id[id]
			if not game._valid_skill_target(2, building, faction):
				continue
			var danger := threats[id]
			if danger < 8.0 or danger < building.population * 0.55:
				continue
			var score := minf(danger * SKILL_RULES.SHIELD_DEFENSE, 45.0) + (28.0 if danger >= building.population else 12.0)
			if score > best.score:
				best = {"index": 2, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(0, faction) and game.faction_skills[faction].energy >= SKILL_RULES.COSTS[0] + SKILL_RULES.COSTS[2]:
		for building: WarBuilding in game.buildings:
			if not game._valid_skill_target(0, building, faction) or building.conversion_target in [1, 2]:
				continue
			# Supply an active front or a drained residence, not an unused giant stockpile.
			if building.available_population > maxf(building.capacity + SKILL_RULES.RECRUIT_RATE * SKILL_RULES.DURATIONS[0], 90.0):
				continue
			var danger: float = threats.get(building.building_id, 0.0)
			if danger > building.population + 20.0:
				continue # Six-second recruitment cannot rescue an immediately lost house.
			var score := 18.0 + maxf(0.0, 30.0 - building.available_population) * 0.25
			score += 5.0 if building.faction == faction else 0.0
			score += 8.0 if danger > building.population * 0.4 else 0.0
			if score > best.score:
				best = {"index": 0, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(1, faction) and game.faction_skills[faction].energy >= SKILL_RULES.COSTS[1] + 20.0:
		var haste := _haste_target(game, visible)
		if not haste.is_empty() and haste.score > best.score:
			best = {"index": 1, "score": haste.score, "target": null, "at": haste.at}
	if game.can_cast_skill(3, faction):
		var fire := _fire_target(game, visible)
		if not fire.is_empty() and fire.score > best.score:
			best = {"index": 3, "score": fire.score, "target": null, "at": fire.at}
	if best.index in [1, 3]:
		game.cast_ground_skill(best.index, best.at, faction)
	elif best.index >= 0:
		game.cast_skill(best.index, best.target, faction)

func _haste_target(game: Node3D, visible: Array[WarMarches.MarchUnit], radius: float = SKILL_RULES.HASTE_RADIUS, minimum: int = 16) -> Dictionary:
	# Look ahead along actual routes. Distant armies do not contribute to a
	# single global score: one local field must cover a useful group of soldiers.
	var cells: Dictionary[Vector2i, Dictionary] = {}
	for unit: WarMarches.MarchUnit in visible:
		if unit.order.faction != faction or unit.order.length - unit.distance < radius * 1.25:
			continue
		var at := unit.order.curve.sample_baked(unit.distance + radius * 0.6)
		var cell := Vector2i(floori(at.x / FIRE_CELL), floori(at.z / FIRE_CELL))
		if not cells.has(cell):
			cells[cell] = {"count": 0, "sum": Vector3.ZERO}
		cells[cell].count += 1
		cells[cell].sum += at
	var candidates := cells.keys()
	candidates.sort_custom(func(a: Vector2i, b: Vector2i): return cells[a].count > cells[b].count)
	var best := {}
	for cell: Vector2i in candidates.slice(0, 24):
		var at: Vector3 = cells[cell].sum / float(cells[cell].count)
		if not game._valid_ground_skill_target(at):
			continue
		var count := 0
		for unit: WarMarches.MarchUnit in visible:
			if unit.order.faction != faction or unit.order.length - unit.distance < radius * 1.25:
				continue
			var ahead := unit.order.curve.sample_baked(unit.distance + radius * 0.6)
			if ahead.distance_to(at) <= radius - 0.7:
				count += 1
		if count >= minimum and (best.is_empty() or float(count) > best.score):
			best = {"at": at, "score": float(count)}
	return best

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
		if unit.spawn_delay >= WarFireWave.BURN_TIME:
			continue
		var end := minf(unit.order.length, unit.distance + game.marches.movement_distance(unit, WarFireWave.BURN_TIME))
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
		var lead: float = game.marches.movement_distance(unit, WarFireWave.EXPANSION_TIME * 0.5)
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

func _rabbit_turn(game: Node3D) -> void:
	var visible: Array[WarMarches.MarchUnit] = []
	var threats: Dictionary[int, float] = {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.is_exposed():
			visible.append(unit)
		var target: WarBuilding = game.by_id[unit.order.target_id]
		if game.FACTIONS.hostile(unit.order.faction, faction) and game.FACTIONS.allied(target.faction, faction) and game.marches.movement_distance(unit, 6.0) >= unit.order.length - unit.distance:
			threats[target.building_id] = threats.get(target.building_id, 0.0) + unit.order.strength * game.combat_multiplier(unit.order.faction, target, game.marches.projected_attack_bonus(unit))
	var best := {"index": -1, "score": 12.0, "target": null, "at": Vector3.ZERO}
	if game.can_cast_skill(0, faction):
		var rush := _rush_target(game, visible)
		if not rush.is_empty() and rush.score > best.score:
			best = {"index": 0, "score": rush.score, "target": null, "at": rush.at}
	if game.can_cast_skill(1, faction):
		for building: WarBuilding in game.buildings:
			if not game._valid_skill_target(1, building, faction):
				continue
			var score := _disable_score(game, building, visible)
			if score > best.score:
				best = {"index": 1, "score": score, "target": building, "at": Vector3.ZERO}
	if game.can_cast_skill(2, faction):
		# A whistle affects both teams. Score the whole local group so saving a
		# building does not accidentally pull back a larger winning allied attack.
		var cells: Dictionary[Vector2i, Dictionary] = {}
		for unit: WarMarches.MarchUnit in visible:
			if unit.order.target_id == unit.order.source_id:
				continue
			var cell := Vector2i(floori(unit.position.x / FIRE_CELL), floori(unit.position.z / FIRE_CELL))
			if not cells.has(cell):
				cells[cell] = {"at": unit.position, "count": 0}
			cells[cell].count += 1
		var candidates := cells.values()
		candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.count > b.count)
		for candidate: Dictionary in candidates.slice(0, 24):
			var at: Vector3 = candidate.at
			if not game._valid_ground_skill_target(at):
				continue
			var score := 0.0
			for unit: WarMarches.MarchUnit in visible:
				if unit.order.target_id == unit.order.source_id or unit.position.distance_squared_to(at) > SKILL_RULES.RECALL_RADIUS * SKILL_RULES.RECALL_RADIUS:
					continue
				var destination: WarBuilding = game.by_id[unit.order.target_id]
				if game.FACTIONS.hostile(unit.order.faction, faction):
					score += 2.0 if game.FACTIONS.allied(destination.faction, faction) else 0.25
				else:
					var home: WarBuilding = game.by_id[unit.order.source_id]
					var danger: float = threats.get(home.building_id, 0.0)
					var defending: bool = danger >= home.population * 0.65 and danger > 0.0 and unit.position.distance_to(home.global_position) < WarMarches.SPEED * 4.0
					score += 2.0 if defending else -2.5
			if score > best.score:
				best = {"index": 2, "score": score, "target": null, "at": at}
	if game.can_cast_skill(3, faction):
		for source: WarBuilding in game.buildings:
			if not game._valid_skill_target(3, source, faction):
				continue
			var percent := 0
			for option: int in [25, 50, 75, 100]:
				var count := mini(SKILL_RULES.BURROW_LIMIT, floori(source.available_population * option / 100.0))
				if count >= 12 and source.available_population - count >= threats.get(source.building_id, 0.0) + 6.0:
					percent = option
			if percent == 0:
				continue
			for building: WarBuilding in game.buildings:
				var plan: Dictionary = game.RABBIT_SKILLS.burrow_plan(game, source, building, percent)
				if plan.is_empty():
					continue
				var burning := false
				for fire: WarFireWave in game.world_effects.get_node("FireWaves").get_children():
					if fire.age < WarFireWave.BURN_TIME and fire.global_position.distance_to(plan.exit) <= game.IMPACT_RADIUS + 0.7:
						burning = true
				if burning:
					continue
				var score := 0.0
				if game.FACTIONS.allied(building.faction, faction):
					var danger: float = threats.get(building.building_id, 0.0)
					if danger >= building.population * 0.75 and danger > 8.0:
						score = 25.0 + minf(plan.count, danger) * 1.5
				else:
					var arrival: float = plan.dig_duration + SKILL_RULES.BURROW_EXIT_DISTANCE / WarMarches.SPEED + floorf(float(plan.count - 1) / WarMarches.COLUMNS) * SKILL_RULES.BURROW_BATCH_INTERVAL
					var growth := minf(maxf(0.0, building.capacity - building.population), building.production_rate * maxf(0.0, arrival - building.disruption_remaining))
					var damage: float = plan.count * game.combat_multiplier(faction, building)
					var committed: int = game.marches.team_incoming_for(building.building_id, faction)
					if committed == 0 and damage > building.population + growth + 2.0 and plan.length >= 9.0:
						score = 28.0 + minf(18.0, damage - building.population - growth)
				if score > best.score:
					best = {"index": 3, "score": score, "target": source, "destination": building, "percent": percent}
	if best.index in [0, 2]:
		game.cast_ground_skill(best.index, best.at, faction)
	elif best.index == 3:
		if game.cast_skill(3, best.target, faction):
			game.issue_order(best.target, best.destination, best.percent, faction)
	elif best.index == 1:
		game.cast_skill(1, best.target, faction)

func _rush_target(game: Node3D, visible: Array[WarMarches.MarchUnit]) -> Dictionary:
	# Aim at the present squad, not a future ground field. Small opening waves
	# are valuable when they can strike a neutral garrison during the six seconds.
	var cells: Dictionary[Vector2i, Dictionary] = {}
	var cell_size := SKILL_RULES.RABBIT_RUSH_RADIUS
	for unit: WarMarches.MarchUnit in visible:
		if unit.order.faction != faction or unit.rush_remaining > 0.0:
			continue
		var cell := Vector2i(floori(unit.position.x / cell_size), floori(unit.position.z / cell_size))
		if not cells.has(cell):
			cells[cell] = {"sum": Vector3.ZERO, "count": 0}
		cells[cell].sum += unit.position
		cells[cell].count += 1
	var candidates := cells.values()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return a.count > b.count)
	var best := {}
	for candidate: Dictionary in candidates.slice(0, 24):
		var at: Vector3 = candidate.sum / candidate.count
		var score := 0.0
		var count := 0
		for unit: WarMarches.MarchUnit in visible:
			if unit.order.faction != faction or unit.rush_remaining > 0.0 or unit.position.distance_squared_to(at) > cell_size * cell_size:
				continue
			var target: WarBuilding = game.by_id[unit.order.target_id]
			var remaining := unit.order.length - unit.distance
			if remaining < 0.5:
				continue
			count += 1
			var reaches: bool = remaining < WarMarches.SPEED * SKILL_RULES.RABBIT_RUSH_MULTIPLIER * SKILL_RULES.RABBIT_DURATIONS[0]
			if not game.FACTIONS.allied(target.faction, faction) and reaches:
				score += 3.0
			else:
				score += minf(1.3, remaining / 10.0)
		if count >= 5 and (best.is_empty() or score > best.score):
			best = {"at": at, "score": score}
	return best

func _disable_score(game: Node3D, building: WarBuilding, visible: Array[WarMarches.MarchUnit]) -> float:
	if building.kind == 0:
		var prevented := minf(building.production_rate * 6.0, maxf(0.0, building.capacity - building.population))
		for state: RefCounted in game.faction_skills:
			if state.recruit_target_id == building.building_id:
				prevented += SKILL_RULES.RECRUIT_RATE * minf(6.0, state.durations[0])
		return prevented * 1.6
	if building.kind == 2:
		var engaged := 0.0
		for unit: WarMarches.MarchUnit in visible:
			if unit.order.faction != building.faction:
				continue
			var target: WarBuilding = game.by_id[unit.order.target_id]
			if game.FACTIONS.allied(target.faction, faction) and game.marches.movement_distance(unit, 6.0) >= unit.order.length - unit.distance:
				engaged += unit.order.strength
		return engaged * 0.1 * 2.0
	var exposed := 0
	for unit: WarMarches.MarchUnit in visible:
		if not game.FACTIONS.allied(unit.order.faction, faction):
			continue
		var future := unit.order.curve.sample_baked(minf(unit.order.length, unit.distance + game.marches.movement_distance(unit, 4.0)))
		if Geometry3D.get_closest_point_to_segment(building.global_position, unit.position, future).distance_to(building.global_position) <= game.tower_range(building):
			exposed += 1
	return minf(exposed, building.level * ceili(6.0 / game.tower_interval(building))) * 2.0 + (8.0 if exposed >= 12 else 0.0)
