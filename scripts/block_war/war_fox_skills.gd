extends RefCounted
## Instant authoritative outcomes; authored effects animate the same release.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")

static func bomb_loss(target: WarBuilding) -> int:
	return mini(RULES.FOX_BOMB_CAP, floori(target.population * RULES.FOX_BOMB_FRACTION + 0.000001))

static func panic_count(target: WarBuilding) -> int:
	return floori(target.population * RULES.FOX_PANIC_FRACTION + 0.000001)

static func stolen_stars(game: Node3D, victim: int, faction: int) -> float:
	if not FACTIONS.hostile(victim, faction):
		return 0.0
	return minf(RULES.FOX_STEAL_STARS, minf(game.morale.stars(victim), 5.0 - game.morale.stars(faction)))

static func panic_routes(game: Node3D, target: WarBuilding) -> Array[Dictionary]:
	var routes: Array[Dictionary] = []
	for candidate: WarBuilding in game.buildings:
		if candidate == target or candidate.faction != target.faction or target.faction < 0:
			continue
		var route: PackedVector3Array = game.map.get_building_route(target, candidate)
		if route.size() >= 2:
			routes.append({"target": candidate, "route": route, "length": game.map.get_building_distance(target, candidate)})
	# No radius cutoff: the final building across the map is still a valid refuge.
	routes.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.length < b.length if not is_equal_approx(a.length, b.length) else a.target.building_id < b.target.building_id)
	return routes.slice(0, RULES.FOX_PANIC_DESTINATIONS)

static func valid_target(game: Node3D, index: int, target: WarBuilding, faction: int) -> bool:
	match index:
		0: return not FACTIONS.allied(target.faction, faction) and not game.bear.is_invulnerable(target.building_id) and bomb_loss(target) > 0
		1: return stolen_stars(game, target.faction, faction) > 0.000001
		3: return FACTIONS.hostile(target.faction, faction) and not game.bear.is_invulnerable(target.building_id) and panic_count(target) > 0 and not panic_routes(game, target).is_empty()
	return false

static func conversion_targets(game: Node3D, center: Vector3, faction: int) -> Array[WarMarches.MarchUnit]:
	var targets: Array[WarMarches.MarchUnit] = []
	if not center.is_finite():
		return targets
	for unit: WarMarches.MarchUnit in game.marches._units:
		if not unit.is_exposed() or not FACTIONS.hostile(unit.order.faction, faction):
			continue
		if Vector2(unit.position.x - center.x, unit.position.z - center.z).length_squared() <= RULES.FOX_CONVERT_RADIUS * RULES.FOX_CONVERT_RADIUS:
			targets.append(unit)
	return targets

static func convert(game: Node3D, center: Vector3, faction: int) -> int:
	var targets := conversion_targets(game, center, faction)
	var orders: Dictionary[WarMarches.MarchOrder, WarMarches.MarchOrder] = {}
	for unit: WarMarches.MarchUnit in targets:
		if not orders.has(unit.order):
			orders[unit.order] = game.marches.transfer_order(unit.order, faction)
		unit.order = orders[unit.order]
		# No respawn/teleport: spacing, route, identity and ongoing effects survive.
	game.marches._render()
	return targets.size()

static func cast(game: Node3D, index: int, target: WarBuilding, faction: int) -> void:
	match index:
		0:
			game.bear.apply_damage(game, target, bomb_loss(target), false, true)
		1:
			game.morale.transfer_stars(target.faction, faction, stolen_stars(game, target.faction, faction))
		3:
			var routes := panic_routes(game, target)
			var count := panic_count(target)
			# All queued soldiers still belong to this garrison. Replace its pending
			# orders before debiting the fleeing population exactly once.
			game.marches.trim_departures(target.building_id, target.faction, 0)
			target.population -= count
			var total_weight := 0.0
			for entry: Dictionary in routes:
				total_weight += 1.0 / maxf(1.0, entry.length)
			var cumulative := 0.0
			var assigned := 0
			for i: int in routes.size():
				var entry := routes[i]
				cumulative += (1.0 / maxf(1.0, entry.length)) / total_weight
				var end := count if i == routes.size() - 1 else roundi(count * cumulative)
				game.marches.send(target.building_id, entry.target.building_id, target.faction, end - assigned, entry.route, 1.0, target.kind == 3)
				assigned = end
	game.world_effects.get_node("Fox").release(index, faction, target.global_position, target.building_id)
	var sounds: Array[StringName] = [&"war_fox_bomb", &"war_fox_steal", &"war_fox_convert", &"war_fox_panic"]
	game.audio.play_world(sounds[index], target.global_position)
