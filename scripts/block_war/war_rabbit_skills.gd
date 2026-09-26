extends RefCounted
## Shared plans keep previews, dispatch, simulation and AI in agreement.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")

static func recall_plan(game: Node3D, center: Vector3) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	if not center.is_finite():
		return plans
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or unit.order.target_id == unit.order.source_id:
			continue
		var offset := Vector2(unit.position.x - center.x, unit.position.z - center.z)
		if offset.length_squared() > RULES.RECALL_RADIUS * RULES.RECALL_RADIUS:
			continue
		var source: WarBuilding = game.by_id[unit.order.source_id]
		var destination: WarBuilding = game.by_id[unit.order.target_id]
		var route: PackedVector3Array = game.map.get_return_route(unit.position, source, destination)
		if route.size() < 2:
			continue
		var length := 0.0
		for index: int in range(1, route.size()):
			length += route[index - 1].distance_to(route[index])
		plans.append({"unit": unit, "route": route, "target": source, "length": length})
	return plans

static func burrow_plan(game: Node3D, source: WarBuilding, target: WarBuilding, amount_percent: int = 100) -> Dictionary:
	if source == null or target == null or source == target:
		return {}
	var count := mini(RULES.BURROW_LIMIT, floori(source.available_population * amount_percent / 100.0))
	if count < 1:
		return {}
	var full: PackedVector3Array = game.map.get_building_route(source, target)
	if full.size() < 2:
		return {}
	# Use a saved surface approach for a clear exit, even across distant rivers.
	var tail := PackedVector3Array([full[-1]])
	var remaining := RULES.BURROW_EXIT_DISTANCE
	for index: int in range(full.size() - 2, -1, -1):
		var segment := full[index + 1].distance_to(full[index])
		if segment >= remaining:
			tail.append(full[index + 1].move_toward(full[index], remaining))
			break
		remaining -= segment
		tail.append(full[index])
	tail.reverse()
	var dig_duration := clampf(full[0].distance_to(tail[0]) / RULES.BURROW_DIG_SPEED, 0.25, 1.2)
	return {"source": source, "target": target, "route": tail, "length": game.map.get_building_distance(source, target),
		"entrance": full[0], "exit": tail[0], "count": count, "dig_duration": dig_duration}

static func recall(game: Node3D, center: Vector3, faction: int) -> int:
	var plans := recall_plan(game, center)
	for plan: Dictionary in plans:
		game.world_effects.get_node("Rabbit").return_dust(plan.unit.position, plan.route[1] - plan.route[0])
		game.marches.redirect(plan.unit, plan.target.building_id, plan.route)
	if not plans.is_empty():
		game.world_effects.get_node("Rabbit").start_recall(faction, center, RULES.RECALL_RADIUS)
	return plans.size()

static func cast(_game: Node3D, index: int, target: WarBuilding, _faction: int) -> bool:
	match index:
		1:
			target.begin_disruption(RULES.DISABLE_DURATION)
		3:
			target.begin_burrow(RULES.BURROW_READY_DURATION)
		_:
			return false
	return true
