extends RefCounted
## Pure plans shared by drag previews, paid casts and AI. No troops are created here.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")

static func recall_plan(game: Node3D, target: WarBuilding, faction: int) -> Array[Dictionary]:
	var plans: Array[Dictionary] = []
	if target == null or target.faction != faction:
		return plans
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or unit.order.faction != faction or unit.order.target_id == target.building_id:
			continue
		if unit.position.distance_squared_to(target.global_position) > RULES.RECALL_RADIUS * RULES.RECALL_RADIUS:
			continue
		var route: PackedVector3Array = game.map.get_recall_route(unit.position, target)
		if route.size() < 2:
			continue
		var length := 0.0
		for index: int in range(1, route.size()):
			length += route[index - 1].distance_to(route[index])
		plans.append({"unit": unit, "route": route, "length": length})
	plans.sort_custom(func(a: Dictionary, b: Dictionary): return a.length < b.length)
	return plans.slice(0, RULES.RECALL_LIMIT)

static func burrow_plan(game: Node3D, target: WarBuilding, faction: int, locked_source: int = -1) -> Dictionary:
	if target == null:
		return {}
	var source: WarBuilding
	var shortest := RULES.BURROW_RANGE + 0.0001
	for building: WarBuilding in game.buildings:
		if building == target or building.faction != faction or floori(building.available_population) < RULES.BURROW_RESERVE + RULES.BURROW_MINIMUM:
			continue
		if locked_source >= 0 and building.building_id != locked_source:
			continue
		var distance: float = game.map.get_building_distance(building, target)
		if distance > RULES.BURROW_EXIT_DISTANCE + 0.1 and distance < shortest:
			shortest = distance
			source = building
	if source == null:
		return {}
	var full: PackedVector3Array = game.map.get_building_route(source, target)
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
	if not game.map._is_route_point_clear(tail[0]):
		return {}
	return {"source": source, "target": target, "route": tail, "length": shortest,
		"entrance": full[0], "exit": tail[0], "count": mini(RULES.BURROW_LIMIT, floori(source.available_population) - RULES.BURROW_RESERVE)}

static func cast(game: Node3D, index: int, target: WarBuilding, faction: int, locked_source: int = -1) -> bool:
	match index:
		1:
			target.begin_disruption(RULES.DISABLE_DURATION)
		2:
			var plans := recall_plan(game, target, faction)
			if plans.is_empty():
				return false
			for plan: Dictionary in plans:
				game.world_effects.get_node("Rabbit").return_dust(plan.unit.position, plan.route[1] - plan.route[0])
				game.marches.redirect(plan.unit, target.building_id, plan.route)
			game.world_effects.get_node("Rabbit").start_rally(faction, target.global_position)
		3:
			var plan := burrow_plan(game, target, faction, locked_source)
			if plan.is_empty():
				return false
			# These unreserved soldiers enter the tunnel now; delayed exits are in transit.
			plan.source.population -= plan.count
			plan.source.refresh_visual()
			game.marches.send_tunnel(plan.source.building_id, target.building_id, faction, plan.count, plan.route, RULES.BURROW_BATCH_INTERVAL)
			game.world_effects.get_node("Rabbit").start_tunnel(faction, plan.entrance, plan.exit, plan.route[1] - plan.route[0], plan.count)
			game.audio.play_world(&"war_rabbit_burrow", plan.exit)
		_:
			return false
	return true
