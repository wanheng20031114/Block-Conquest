extends RefCounted
## One paid action per turn: defend, develop, expand, then commit surplus troops.

const TURN_INTERVAL := 3.0
const ATTACK_INTERVAL := 15.0
const EXPANSION_INTERVAL := 6.0
const FRONT_DISTANCE := 30.0

var faction := 1
var _next_attack_at := 0.0
var _next_expansion_at := 0.0
var _reserves: Dictionary = {}
var _tower_exposure: Dictionary[Vector4i, float] = {}
var _incoming_teams: Dictionary[int, Vector2i] = {}
var _departure_delays: Dictionary[Vector2i, float] = {}

func _init(controlled_faction: int = 1) -> void:
	faction = controlled_faction

func take_turn(game: Node3D) -> void:
	if game.finished or game._local_menu:
		return
	_reserves.clear()
	_departure_delays.clear()
	# No simulation runs within one decision. Count each soldier once instead
	# of rescanning all armies for every candidate source/target combination.
	var incoming: Dictionary[Vector2i, int] = game.marches.snapshot_incoming()
	_incoming_teams.clear()
	for key: Vector2i in incoming:
		var totals: Vector2i = _incoming_teams.get(key.x, Vector2i.ZERO)
		totals[key.y % 2] += incoming[key]
		_incoming_teams[key.x] = totals
	var homes := 0
	var constructing := 0
	var unsafe := false
	for building: WarBuilding in game.buildings:
		if not game.FACTIONS.allied(building.faction, faction):
			continue
		if building.faction == faction:
			homes += int(building.kind == 0 or building.conversion_target == 0)
			constructing += int(building.is_constructing)
		var reserve := _base_reserve(game, building)
		reserve += game.incoming_damage_for(building, incoming)
		_reserves[building.building_id] = reserve
		if reserve > building.population + _incoming_for(building.building_id, faction):
			unsafe = unsafe or _incoming_for(building.building_id, 1 - faction % 2) > 0
	if _reinforce(game):
		return
	# An unresolved invasion takes precedence over spending or opening another front.
	if unsafe:
		return
	var development := _development(game, homes, constructing)
	var expansion := _conquest(game, true) if game.elapsed >= _next_expansion_at else {}
	# A developed economy can take a good military opportunity between investments.
	# Wait for committed forces before considering a fresh offensive.
	if game.elapsed >= _next_attack_at and game.marches.team_total_for(faction) <= game.team_total_for(faction) * 0.35:
		var attack := _conquest(game, false)
		var economy_score: float = maxf(development.get("score", -INF), expansion.get("score", -INF))
		var ahead: bool = homes >= 3 and game.team_total_for(faction) >= game.team_total_for(1 - faction % 2) * 1.25
		if not attack.is_empty() and (economy_score == -INF or (ahead and attack.score > economy_score)):
			game.issue_order(attack.source, attack.target, attack.percent, faction)
			_next_attack_at = game.elapsed + ATTACK_INTERVAL
			return
	if not development.is_empty() and (expansion.is_empty() or development.score >= expansion.score):
		var building: WarBuilding = development.building
		building.population -= development.cost
		building.begin_construction(development.kind)
		building.refresh_visual()
		game.audio.play_world(&"war_rebuild", building.global_position)
		game.update_hud()
		return
	if not expansion.is_empty():
		game.issue_order(expansion.source, expansion.target, expansion.percent, faction)
		_next_expansion_at = game.elapsed + EXPANSION_INTERVAL
		return
	_consolidate(game)

func _base_reserve(game: Node3D, building: WarBuilding) -> float:
	return (14.0 if _enemy_distance(game, building) < FRONT_DISTANCE else 8.0) + (building.level - 1) * 2.0

func _incoming_for(building_id: int, team: int) -> int:
	var totals: Vector2i = _incoming_teams.get(building_id, Vector2i.ZERO)
	return totals[team % 2]

func _distance(game: Node3D, source: WarBuilding, target: WarBuilding) -> float:
	return game.map.get_building_distance(source, target)

func _enemy_distance(game: Node3D, source: WarBuilding) -> float:
	var distance := INF
	for target: WarBuilding in game.buildings:
		if game.FACTIONS.hostile(target.faction, faction):
			distance = minf(distance, _distance(game, source, target))
	return distance

func _dispatch_percent(source: WarBuilding, reserve: float, needed: float) -> int:
	# Use the player's four dispatch choices, but never empty a garrison.
	var partial := 0
	for percent: int in [25, 50, 75]:
		var count := floori(source.population * percent / 100.0)
		if source.population - count >= reserve:
			partial = percent
			if count >= needed:
				return percent
	return partial

func _reinforce(game: Node3D) -> bool:
	var best := {}
	for target: WarBuilding in game.buildings:
		if not game.FACTIONS.allied(target.faction, faction) or _incoming_for(target.building_id, 1 - faction % 2) == 0:
			continue
		var missing: float = _reserves[target.building_id] - target.population - _incoming_for(target.building_id, faction)
		if missing <= 0.0:
			continue
		for source: WarBuilding in game.buildings:
			if source == target or source.faction != faction:
				continue
			var percent := _dispatch_percent(source, _reserves[source.building_id], missing)
			if percent == 0 or floori(source.population * percent / 100.0) < 5:
				continue
			var score := minf(missing, floorf(source.population * percent / 100.0)) - _distance(game, source, target) * 0.3
			if best.is_empty() or score > best.score:
				best = {"source": source, "target": target, "percent": percent, "score": score}
	if best.is_empty():
		return false
	return game.issue_order(best.source, best.target, best.percent, faction) > 0

func _development(game: Node3D, homes: int, constructing: int) -> Dictionary:
	var best := {}
	# Keep at least half the economy free to build an army while work is underway.
	if constructing >= maxi(1, homes / 2):
		return best
	for building: WarBuilding in game.buildings:
		if building.faction != faction or building.is_constructing or _incoming_for(building.building_id, 1 - faction % 2) > 0:
			continue
		var cost := building.upgrade_cost
		var kind := -1
		var score := 0.0
		var reserve: float = _reserves[building.building_id]
		if homes == 0:
			# Recover production after losing the last residence, using a real conversion.
			kind = 0
			cost = game.CONVERSION_COST
			score = 90.0
			if _enemy_distance(game, building) >= FRONT_DISTANCE:
				reserve = 0.0
		elif building.level >= building.max_level:
			continue
		elif building.kind == 0:
			if building.population < building.capacity * 0.7:
				continue
			score = [38.0, 24.0, 15.0][building.level - 1] + 6.0 * minf(1.0, building.population / building.capacity)
		elif homes >= 2 and game.total_for(faction) >= 100:
			if building.kind == 2:
				score = 22.0 + homes * 2.0 - cost * 0.1
			elif _enemy_distance(game, building) < FRONT_DISTANCE:
				score = 18.0 - cost * 0.1
		if score <= 0.0 or building.population < cost + reserve:
			continue
		if best.is_empty() or score > best.score:
			best = {"building": building, "cost": cost, "kind": kind, "score": score}
	return best

func _conquest(game: Node3D, neutral: bool) -> Dictionary:
	var best := {}
	for source: WarBuilding in game.buildings:
		if source.faction != faction:
			continue
		var reserve: float = _reserves[source.building_id]
		for target: WarBuilding in game.buildings:
			if (target.faction != -1 if neutral else not game.FACTIONS.hostile(target.faction, faction)):
				continue
			if _incoming_for(target.building_id, faction) > 0:
				continue
			# Contested neutral land can change hands before we arrive; do not race blindly.
			if neutral and _incoming_for(target.building_id, 1 - faction % 2) > 0:
				continue
			var distance := _distance(game, source, target)
			if not is_finite(distance):
				continue
			var percent := 0
			var required := 0.0
			for option: int in [25, 50, 75]:
				var count := floori(source.population * option / 100.0)
				if count < 1 or source.population - count < reserve:
					continue
				var departure := Vector2i(source.building_id, count)
				if not _departure_delays.has(departure):
					_departure_delays[departure] = game.marches.estimate_arrival_time(source.building_id, 0.0, count)
				var arrival := distance / WarMarches.SPEED + _departure_delays[departure]
				var defenders := target.population
				if not neutral:
					# Reinforcements, growth and fortifications all belong to the defender.
					defenders += _incoming_for(target.building_id, target.faction)
					defenders += minf(maxf(0.0, target.capacity - target.population), target.production_rate * arrival)
				required = defenders * game.defense_multiplier(target) / game.attack_multiplier(faction)
				required = required * (1.0 if neutral else 1.35) + (6.0 if neutral else 10.0)
				if count < required:
					continue
				required += _tower_losses(game, source, target, count)
				if count >= required:
					percent = option
					break
			if percent == 0:
				continue
			var value := 50.0 if target.kind == 0 else (32.0 if target.kind == 2 else 24.0)
			var score := value - distance * 0.55 - required * 0.2
			# Attacks remain possible against a strong last opponent after saving up.
			if (not neutral or score > 0.0) and (best.is_empty() or score > best.score):
				best = {"source": source, "target": target, "percent": percent, "score": score}
	return best

func _tower_losses(game: Node3D, source: WarBuilding, target: WarBuilding, count: int) -> float:
	var losses := 0.0
	for tower: WarBuilding in game.buildings:
		if not game.FACTIONS.hostile(tower.faction, faction) or tower.kind != 1:
			continue
		# Fixed terrain means exposure only changes with the tower's level. Reuse
		# geometry across dispatch percentages and later turns; ownership stays live.
		var key := Vector4i(mini(source.building_id, target.building_id), maxi(source.building_id, target.building_id), tower.building_id, tower.level)
		if not _tower_exposure.has(key):
			var route: PackedVector3Array = game.map.get_building_route(source, target)
			var length := 0.0
			var radius: float = game.tower_range(tower)
			for index: int in range(1, route.size()):
				if tower.global_position.distance_to(route[index - 1].lerp(route[index], 0.5)) <= radius:
					length += route[index - 1].distance_to(route[index])
			_tower_exposure[key] = length
		var exposed_length := _tower_exposure[key]
		if exposed_length > 0.0:
			var duration := (exposed_length + ceilf(float(count) / WarMarches.COLUMNS) * WarMarches.ROW_SPACING) / WarMarches.SPEED
			losses += ceilf(duration / game.tower_interval(tower)) * tower.level
	return losses

func _consolidate(game: Node3D) -> void:
	var front: WarBuilding
	var nearest := INF
	for building: WarBuilding in game.buildings:
		if building.faction != faction:
			continue
		var distance := _enemy_distance(game, building)
		# Geography and a stable ID determine the front, never fluctuating population.
		if distance < nearest or (is_equal_approx(distance, nearest) and (front == null or building.building_id < front.building_id)):
			front = building
			nearest = distance
	if front == null or _incoming_for(front.building_id, faction) >= 30:
		return
	var best := {}
	for source: WarBuilding in game.buildings:
		if source.faction != faction or source == front:
			continue
		var reserve: float = _reserves[source.building_id]
		if source.kind == 0:
			if source.population < source.capacity * 0.85:
				continue
			# Rear residences keep their next investment as well as a defensive guard.
			if not source.is_constructing:
				reserve += source.upgrade_cost
		for percent: int in [75, 50, 25]:
			var count := floori(source.population * percent / 100.0)
			if count < 8 or source.population - count < reserve:
				continue
			var score := count - _distance(game, source, front) * 0.3
			if best.is_empty() or score > best.score:
				best = {"source": source, "percent": percent, "score": score}
			break
	if not best.is_empty():
		game.issue_order(best.source, front, best.percent, faction)
