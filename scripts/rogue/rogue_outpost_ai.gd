class_name RogueOutpostAI
extends SkirmishBot
## Scenario adapter for the ordinary PvE commander. Visibility/memory, target
## priority, formation commands, command throttling and support orders are reused.
## Only economy, recruitment pacing and the authored guard/scout roles differ.

var definition: RogueBattleDefinition
var squads: Array[Dictionary] = []
var producers: Array[Dictionary] = []
var _reserve: Dictionary = {}
var _building_health: Dictionary = {}
var _unit_health: Dictionary = {}
var _alerts: Array[Dictionary] = []

func _init(game: Node, encounter: RogueBattleDefinition) -> void:
	super(game, 1)
	definition = encounter
	assert(not definition.barracks_recruit_cycle.is_empty() and definition.barracks_recruit_interval > 0.0)
	assert(not definition.search_waypoints.is_empty())
	_refresh_own_army()
	var posts: Dictionary = {}
	for building: BattleBuilding in _buildings:
		_building_health[building.entity_id] = building.hp
		if building.building_type == "barracks":
			building.rally_point = building.global_position + Vector3(-6, 0, 0)
			producers.append({"building": building, "next_at": definition.barracks_first_recruit_seconds + producers.size() * definition.barracks_recruit_stagger_seconds,
				"cycle": producers.size()})
	for unit: BattleUnit in _army:
		_unit_health[unit.entity_id] = unit.hp
		var role: String = str(unit.get_meta("rogue_role", "guard"))
		var anchor: BattleBuilding = _nearest_post(unit.global_position)
		var lane: int = 0 if unit.position.z < 0 else 1
		var key: String = "scout%d" % lane if role == "scout" else "post%d" % anchor.entity_id
		if not posts.has(key):
			posts[key] = _new_squad(role, unit.global_position, lane)
			posts[key]["anchor"] = anchor
		posts[key].units.append(unit)

func _new_squad(role: String, home: Vector3, lane: int = 0) -> Dictionary:
	var squad := {"role": role, "units": [], "home": home, "created_at": _clock,
		"search_index": lane, "last_order": "", "last_order_at": -10.0, "state": "guard"}
	squads.append(squad)
	return squad

func _nearest_post(at: Vector3) -> BattleBuilding:
	var nearest: BattleBuilding = _buildings[0]
	for building: BattleBuilding in _buildings:
		if at.distance_squared_to(building.global_position) < at.distance_squared_to(nearest.global_position):
			nearest = building
	return nearest

func tick(delta: float) -> void:
	if _game.intro_active or _game.finished or _game.get_tree().paused or not _game._match_ready:
		return
	super.tick(delta)
	_tick_recruitment()

func _tick_recruitment() -> void:
	for producer: Dictionary in producers:
		# Rubble may finish its animation and free the building between decisions.
		# Check the Variant before assigning it to a typed object reference.
		if not is_instance_valid(producer.building):
			continue
		var building: BattleBuilding = producer.building
		if not building.is_constructed:
			continue
		var capped: bool = _game.living_enemies() >= definition.enemy_cap
		building.order_name = "守军已达上限" if capped else "训练援军 · %d秒" % ceili(maxf(0.0, float(producer.next_at) - _clock))
		if _clock < float(producer.next_at):
			continue
		if capped:
			producer.next_at = _clock + definition.barracks_recruit_interval
			continue
		var kind: String = definition.barracks_recruit_cycle[int(producer.cycle) % definition.barracks_recruit_cycle.size()]
		# Use the same navigable, unoccupied exit search as paid PvE production.
		var at: Vector3 = _game.find_recruit_position(kind, building)
		if not at.is_finite():
			producer.next_at = _clock + 1.0
			continue
		var unit: BattleUnit = _game.spawn_unit(kind, _owner, at)
		_game.enemy_reinforcements += 1
		producer.cycle += 1
		producer.next_at = _clock + definition.barracks_recruit_interval
		unit.set_meta("rogue_producer", building.entity_id)
		unit.set_meta("rogue_role", "reserve")
		_unit_health[unit.entity_id] = unit.hp
		if _reserve.is_empty() or _reserve.role != "reserve":
			_reserve = _new_squad("reserve", definition.raid_muster_point)
		_reserve.units.append(unit)
		unit.issue_move(definition.raid_muster_point, true)
		_game.spawn_effect(at, "spawn", Color("84bfd9"))

func _decide() -> void:
	_refresh_own_army()
	_observe()
	_alerts = _alerts.filter(func(alert: Dictionary): return float(alert.until) > _clock)
	for building: BattleBuilding in _buildings:
		if building.hp < float(_building_health.get(building.entity_id, building.hp)):
			_alerts.append({"at": building.global_position, "until": _clock + definition.support_alert_seconds})
		_building_health[building.entity_id] = building.hp
	for unit: BattleUnit in _army:
		if unit.hp < float(_unit_health.get(unit.entity_id, unit.hp)):
			_alerts.append({"at": unit.global_position, "until": _clock + definition.support_alert_seconds})
		_unit_health[unit.entity_id] = unit.hp
	var alarms: Array[Vector3] = []
	for alert: Dictionary in _alerts: alarms.append(alert.at)
	var entire_army: Array[Node3D] = _army.duplicate()
	for squad: Dictionary in squads:
		squad.units = squad.units.filter(func(unit): return is_instance_valid(unit) and unit.alive)
		if squad.units.is_empty():
			continue
		_command_squad(squad, alarms)
	_army = entire_army
	_command_supporters()

func _command_squad(squad: Dictionary, alarms: Array[Vector3]) -> void:
	var center := Vector3.ZERO
	for unit: BattleUnit in squad.units:
		center += unit.global_position
	center /= squad.units.size()
	var role: String = squad.role
	if role == "guard" and (not is_instance_valid(squad.anchor) or not squad.anchor.alive):
		squad.role = "raider"
		role = "raider"
	if role == "guard":
		var assisting: bool = alarms.any(func(at: Vector3): return at.distance_to(squad.home) <= definition.support_response_radius)
		var reach: float = definition.support_response_radius if assisting else definition.guard_response_radius
		var intruder: Node3D = _attack_target(squad.home, reach)
		if intruder != null and center.distance_to(squad.home) <= definition.guard_chase_radius:
			_order_squad(squad, "assist" if assisting else "defend", "attack", intruder.global_position, intruder.entity_id)
		elif assisting and intruder == null:
			# Artillery can fire from beyond shared vision. Investigate a known
			# approach after damage, rather than learning the unseen shooter's
			# coordinates or waiting motionless beside the besieged structure.
			var approach: Vector3 = _search_goal(squad, center)
			var scout_to: Vector3 = Vector3(squad.home).move_toward(approach, definition.guard_chase_radius)
			_order_squad(squad, "investigate", "move", scout_to)
		elif center.distance_to(squad.home) > 4.0:
			_order_squad(squad, "return", "move", squad.home)
		return
	# Newborns muster at a real rally point; local threats can interrupt muster.
	var enemy: Node3D = _attack_target(center, definition.support_response_radius if role == "reserve" else INF)
	if enemy != null:
		_order_squad(squad, "attack", "attack", enemy.global_position, enemy.entity_id)
		return
	if role == "reserve":
		var gathered: bool = squad.units.size() >= definition.raid_muster_size and squad.units.all(func(unit: BattleUnit): return unit.global_position.distance_to(definition.raid_muster_point) <= definition.raid_muster_radius)
		if not gathered and _clock - float(squad.created_at) < definition.raid_muster_timeout:
			_order_squad(squad, "muster", "move", definition.raid_muster_point)
			return
		squad.role = "raider"
	if _clock < definition.scout_start_seconds:
		return
	_order_squad(squad, "search", "move", _search_goal(squad, center))

func _search_goal(squad: Dictionary, center: Vector3) -> Vector3:
	# Reuse only last-observed positions from SkirmishBot's expiring memory.
	# Unseen live enemy positions never choose a search destination.
	var last_seen: Vector3 = Vector3.INF
	var distance: float = INF
	for record: Dictionary in _memory.values():
		var candidate: float = center.distance_squared_to(record.position)
		if candidate < distance:
			distance = candidate
			last_seen = record.position
	if last_seen.is_finite() and center.distance_to(last_seen) > 4.0:
		return last_seen
	var route: PackedVector3Array = definition.search_waypoints
	var index: int = int(squad.search_index) % route.size()
	if center.distance_to(route[index]) < 4.0:
		index = (index + 1) % route.size()
		squad.search_index = index
	return route[index]

func _order_squad(squad: Dictionary, state: String, kind: String, at: Vector3, target_id: int = 0) -> void:
	_army.assign(squad.units)
	army_state = StringName(state)
	squad.state = state
	# Keep the stock command deduplication independent for each guard/scout group.
	_last_army_order = squad.last_order
	_last_army_order_at = float(squad.last_order_at)
	_order_army(kind, at, target_id, kind == "move" and state != "return")
	squad.last_order = _last_army_order
	squad.last_order_at = _last_army_order_at
