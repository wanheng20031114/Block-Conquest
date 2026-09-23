extends RefCounted
## One paid action per turn: defend, develop, expand, then commit surplus troops.

const TURN_INTERVAL := 3.0
const ATTACK_INTERVAL := 15.0
const EXPANSION_INTERVAL := 6.0
const FRONT_DISTANCE := 30.0

var _next_attack_at := 0.0
var _next_expansion_at := 0.0
var _distances: Dictionary = {}
var _reserves: Dictionary = {}

func take_turn(game: Node3D) -> void:
	if game.finished or game._local_menu:
		return
	_distances.clear()
	_reserves.clear()
	var homes := 0
	var constructing := 0
	var unsafe := false
	for building: WarBuilding in game.buildings:
		if building.faction != game.ENEMY:
			continue
		homes += int(building.kind == 0 or building.conversion_target == 0)
		constructing += int(building.is_constructing)
		var reserve := _base_reserve(game, building)
		reserve += game.marches.incoming_for(building.building_id, game.PLAYER) * game.attack_multiplier(game.PLAYER) / game.defense_multiplier(building)
		_reserves[building.building_id] = reserve
		if reserve > building.population + game.marches.incoming_for(building.building_id, game.ENEMY):
			unsafe = unsafe or game.marches.incoming_for(building.building_id, game.PLAYER) > 0
	if _reinforce(game):
		return
	# An unresolved invasion takes precedence over spending or opening another front.
	if unsafe:
		return
	var development := _development(game, homes, constructing)
	var expansion := _conquest(game, true) if game.elapsed >= _next_expansion_at else {}
	# A developed economy can take a good military opportunity between investments.
	# Wait for committed forces before considering a fresh offensive.
	if game.elapsed >= _next_attack_at and game.marches.total_for(game.ENEMY) <= game.total_for(game.ENEMY) * 0.35:
		var attack := _conquest(game, false)
		var economy_score: float = maxf(development.get("score", -INF), expansion.get("score", -INF))
		var ahead: bool = homes >= 3 and game.total_for(game.ENEMY) >= game.total_for(game.PLAYER) * 1.25
		if not attack.is_empty() and (economy_score == -INF or (ahead and attack.score > economy_score)):
			game.issue_order(attack.source, attack.target, attack.percent, game.ENEMY)
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
		game.issue_order(expansion.source, expansion.target, expansion.percent, game.ENEMY)
		_next_expansion_at = game.elapsed + EXPANSION_INTERVAL
		return
	_consolidate(game)

func _base_reserve(game: Node3D, building: WarBuilding) -> float:
	return (14.0 if _enemy_distance(game, building) < FRONT_DISTANCE else 8.0) + (building.level - 1) * 2.0

func _distance(game: Node3D, source: WarBuilding, target: WarBuilding) -> float:
	var key := Vector2i(source.building_id, target.building_id)
	if not _distances.has(key):
		var route: PackedVector3Array = game.map.get_building_route(source, target)
		var length := 0.0
		for index: int in range(1, route.size()):
			length += route[index - 1].distance_to(route[index])
		_distances[key] = length if route.size() >= 2 else INF
	return _distances[key]

func _enemy_distance(game: Node3D, source: WarBuilding) -> float:
	var distance := INF
	for target: WarBuilding in game.buildings:
		if target.faction == game.PLAYER:
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
		if target.faction != game.ENEMY or game.marches.incoming_for(target.building_id, game.PLAYER) == 0:
			continue
		var missing: float = _reserves[target.building_id] - target.population - game.marches.incoming_for(target.building_id, game.ENEMY)
		if missing <= 0.0:
			continue
		for source: WarBuilding in game.buildings:
			if source == target or source.faction != game.ENEMY:
				continue
			var percent := _dispatch_percent(source, _reserves[source.building_id], missing)
			if percent == 0 or floori(source.population * percent / 100.0) < 5:
				continue
			var score := minf(missing, floorf(source.population * percent / 100.0)) - _distance(game, source, target) * 0.3
			if best.is_empty() or score > best.score:
				best = {"source": source, "target": target, "percent": percent, "score": score}
	if best.is_empty():
		return false
	return game.issue_order(best.source, best.target, best.percent, game.ENEMY) > 0

func _development(game: Node3D, homes: int, constructing: int) -> Dictionary:
	var best := {}
	# Keep at least half the economy free to build an army while work is underway.
	if constructing >= maxi(1, homes / 2):
		return best
	for building: WarBuilding in game.buildings:
		if building.faction != game.ENEMY or building.is_constructing or game.marches.incoming_for(building.building_id, game.PLAYER) > 0:
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
		elif homes >= 2 and game.total_for(game.ENEMY) >= 100:
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
		if source.faction != game.ENEMY:
			continue
		var reserve: float = _reserves[source.building_id]
		for target: WarBuilding in game.buildings:
			if target.faction != (-1 if neutral else game.PLAYER) or game.marches.incoming_for(target.building_id, game.ENEMY) > 0:
				continue
			# Contested neutral land can change hands before we arrive; do not race blindly.
			if neutral and game.marches.incoming_for(target.building_id, game.PLAYER) > 0:
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
				var arrival: float = game.marches.estimate_arrival_time(source.building_id, distance, count)
				var defenders := target.population
				if not neutral:
					# Reinforcements, growth and fortifications all belong to the defender.
					defenders += game.marches.incoming_for(target.building_id, game.PLAYER)
					defenders += minf(maxf(0.0, target.capacity - target.population), target.production_rate * arrival)
				required = defenders * game.defense_multiplier(target) / game.attack_multiplier(game.ENEMY)
				required = required * (1.0 if neutral else 1.35) + (6.0 if neutral else 10.0)
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
	var route: PackedVector3Array = game.map.get_building_route(source, target)
	for tower: WarBuilding in game.buildings:
		if tower.faction != game.PLAYER or tower.kind != 1:
			continue
		var exposed_length := 0.0
		var radius: float = game.tower_range(tower)
		for index: int in range(1, route.size()):
			if tower.global_position.distance_to(route[index - 1].lerp(route[index], 0.5)) <= radius:
				exposed_length += route[index - 1].distance_to(route[index])
		if exposed_length > 0.0:
			var duration := (exposed_length + ceilf(float(count) / WarMarches.COLUMNS) * WarMarches.ROW_SPACING) / WarMarches.SPEED
			losses += ceilf(duration / game.tower_interval(tower)) * tower.level
	return losses

func _consolidate(game: Node3D) -> void:
	var front: WarBuilding
	var nearest := INF
	for building: WarBuilding in game.buildings:
		if building.faction != game.ENEMY:
			continue
		var distance := _enemy_distance(game, building)
		# Geography and a stable ID determine the front, never fluctuating population.
		if distance < nearest or (is_equal_approx(distance, nearest) and (front == null or building.building_id < front.building_id)):
			front = building
			nearest = distance
	if front == null or game.marches.incoming_for(front.building_id, game.ENEMY) >= 30:
		return
	var best := {}
	for source: WarBuilding in game.buildings:
		if source.faction != game.ENEMY or source == front:
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
		game.issue_order(best.source, front, best.percent, game.ENEMY)
