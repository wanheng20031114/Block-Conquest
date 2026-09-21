extends Node
## Shared commander: lane allocation, firing lines and relief orders.
## Native units still own paths, avoidance, contact, aiming and attack timing.
var decision_in: float = 0.0
var card_in: float = 3.0
var decisions: int = 0
var orders_issued: int = 0
var retreating: bool = false
var flank_orders: int = 0
var _lane_tie := PackedInt32Array([0, 0])
var _armies: Array = [[], []]
var _claims: Dictionary = {}
var _pending: Array[BattleUnit] = []
var _pending_index: int = 0
@onready var game: Node3D = get_parent()

func objectives(owner: int) -> Array:
	for tier: Array in game.fronts[1 - owner]:
		var standing: Array = tier.filter(func(value): return is_instance_valid(value) and value.alive)
		if not standing.is_empty(): return standing
	return []

func objective_for(owner: int, lane: int) -> BattleBuilding:
	var targets := objectives(owner)
	if targets.is_empty(): return null
	return targets[0] if targets.size() == 1 or lane < 0 else targets[1]

func enlist(unit: BattleUnit) -> void:
	# Balance each combat role as well as total strength, instead of entity-id
	# parity (which could send every archer in repeated waves down one lane).
	var loads := [0.0, 0.0]
	var files := [0, 0]
	var ranged := not unit._stats.projectile.is_empty()
	for ally: BattleUnit in game.unit_container.get_children():
		if ally == unit or not ally.alive or ally.owner_id != unit.owner_id or ally is HeroUnit: continue
		var lane_index := 0 if int(ally.get_meta("moba_lane", -1)) < 0 else 1
		var same_role := ranged == (not ally._stats.projectile.is_empty())
		loads[lane_index] += 1.0 + (2.0 if same_role else 0.0)
		if same_role: files[lane_index] += 1
	var index: int = _lane_tie[unit.owner_id] % 2 if is_equal_approx(loads[0], loads[1]) else (0 if loads[0] < loads[1] else 1)
	_lane_tie[unit.owner_id] += 1
	var lane := index * 2 - 1
	unit.set_meta("moba_lane", lane)
	unit.set_meta("moba_file", files[index] % 5 - 2)
	var sign_x := -1.0 if unit.owner_id == 0 else 1.0
	var width: float = float(unit.get_meta("moba_file")) * 1.25
	unit.issue_move(Vector3(sign_x * 70, 0, lane * 11 + width), true)
	unit.queue_move(Vector3(sign_x * 44, 0, lane * 11 + width), true)
	unit.queue_move(Vector3(sign_x * 3, 0, lane * 7 + width), true)
	var objective := objective_for(unit.owner_id, lane)
	if objective != null:
		unit.queue_move(_station(unit, objective), true)
		unit.set_meta("moba_objective", objective.entity_id)
	orders_issued += 1

func advance(delta: float) -> void:
	decision_in -= delta
	card_in -= delta
	if decision_in > 0:
		_issue_pending_orders()
		return
	decision_in = .5
	decisions += 1
	_armies = [[], []]
	_claims.clear()
	_pending.clear()
	_pending_index = 0
	for unit: BattleUnit in game.unit_container.get_children():
		if not unit.alive: continue
		_armies[unit.owner_id].append(unit)
		if unit._valid_target(unit.target):
			_claims[unit.target.entity_id] = int(_claims.get(unit.target.entity_id, 0)) + 1
	for owner: int in 2:
		var forward := 1.0 if owner == 0 else -1.0
		# Front ranks keep contacts; reinforcements fill the remaining frontage.
		_armies[owner].sort_custom(func(a, b): return a.position.x * forward > b.position.x * forward)
	# Interleave teams so a full army does not delay the opposing commander.
	for index: int in maxi(_armies[0].size(), _armies[1].size()):
		for owner: int in 2:
			if index < _armies[owner].size() and not _armies[owner][index] is HeroUnit:
				_pending.append(_armies[owner][index])
	_issue_pending_orders()
	_command_hero(_armies)
	if card_in <= 0:
		card_in = 2.8
		_buy_card(_armies)

func _issue_pending_orders() -> void:
	# Forty units per physics tick covers both 240-unit armies before the next
	# strategic snapshot without issuing hundreds of path requests in one tick.
	var end := mini(_pending_index + 40, _pending.size())
	while _pending_index < end:
		var unit: BattleUnit = _pending[_pending_index]
		_pending_index += 1
		if is_instance_valid(unit) and unit.alive:
			_command_army(unit, _armies[1 - unit.owner_id], _claims)

func _command_army(unit: BattleUnit, enemies: Array, claims: Dictionary) -> void:
	# Never cancel a release or move a productive fighter out of its firing line.
	if unit.battery.winding or not unit.attack_windup.is_stopped(): return
	var objective := objective_for(unit.owner_id, int(unit.get_meta("moba_lane", -1)))
	if objective == null: return
	# Siege weapons keep pressure on structures instead of spending every shot
	# on endlessly replenished infantry in the centre of the map.
	var siege := unit._stats.combat_class == &"siege"
	if siege and unit._within_attack_range(objective):
		if unit.target != objective:
			unit.issue_attack(objective)
			orders_issued += 1
		return
	if unit._valid_target(unit.target) and unit._can_start_strike(unit.target): return
	var enemy := _choose_enemy(unit, enemies, claims)
	if siege and unit.position.distance_to(objective.position) < 30 and (enemy == null or unit.position.distance_to(enemy.position) > 6): enemy = null
	# Rear ranged units use an available shot immediately, even during deployment.
	if enemy != null and unit._can_start_strike(enemy):
		unit.issue_attack(enemy)
		claims[enemy.entity_id] = int(claims.get(enemy.entity_id, 0)) + 1
		orders_issued += 1
		return
	# An advancing fighter already has useful orders. Redeploy stalled rear
	# ranks, not every unit that has yet to arrive at its opponent.
	if unit._valid_target(unit.target) and unit.order in [BattleUnit.Order.ATTACK, BattleUnit.Order.ATTACK_MOVE] and unit._observed_velocity.length_squared() > .25: return
	if game.elapsed < float(unit.get_meta("moba_redeploy_at", 0.0)) and unit.order != BattleUnit.Order.IDLE: return
	var target: Node3D = enemy if enemy != null else objective
	if enemy == null:
		var changed := int(unit.get_meta("moba_objective", 0)) != objective.entity_id
		if not changed and unit.order != BattleUnit.Order.IDLE and unit.position.distance_to(objective.position) > 30: return
	var station := _station(unit, target)
	if unit.position.distance_to(station) < 1.0:
		unit.issue_attack(target)
	elif unit.order == BattleUnit.Order.MOVE and unit.destination.distance_to(station) < 2.0:
		return
	else:
		# Explicit deployment prevents acquisition from dragging every rear rank
		# back into the same contact. Attack resumes at its assigned position.
		unit.issue_move(station)
		unit.issue_attack(target, true)
		flank_orders += 1
	unit.set_meta("moba_objective", objective.entity_id)
	unit.set_meta("moba_redeploy_at", game.elapsed + 2.5)
	claims[target.entity_id] = int(claims.get(target.entity_id, 0)) + 1
	orders_issued += 1

func _choose_enemy(unit: BattleUnit, enemies: Array, claims: Dictionary) -> BattleUnit:
	var best: BattleUnit
	var best_score := INF
	var ranged := not unit._stats.projectile.is_empty()
	for enemy: BattleUnit in enemies:
		# Snapshots are consumed over several ticks, so deaths are revalidated.
		if not is_instance_valid(enemy) or not enemy.alive: continue
		var distance_squared := unit.position.distance_squared_to(enemy.position)
		if distance_squared > pow(maxf(24.0, unit.attack_range + 3), 2): continue
		var distance := sqrt(distance_squared)
		var pressure: float = float(claims.get(enemy.entity_id, 0))
		if unit.target == enemy: pressure = maxf(0.0, pressure - 1)
		var score := distance + pressure * (1.1 if ranged else 3.5)
		if unit._within_attack_range(enemy): score -= 30.0
		if enemy.position.z * float(unit.get_meta("moba_lane", -1)) < -3: score += 4.0
		if score < best_score:
			best_score = score
			best = enemy
	return best

func _station(unit: BattleUnit, target: Node3D) -> Vector3:
	var forward := 1.0 if unit.owner_id == 0 else -1.0
	var file: float = float(unit.get_meta("moba_file", 0))
	var reach := unit.attack_range * .82 + unit.radius
	var at: Vector3
	if target is BattleBuilding:
		var footprint: Vector3 = target.get_footprint_size()
		var lane: float = float(unit.get_meta("moba_lane", -1))
		# Aim at the wall, never its unwalkable center. Both lanes fan around
		# the two halves of a surviving fort, with ranged ranks behind melee.
		at = target.position + Vector3(-forward * (footprint.x * .5 + reach), 0, lane * footprint.z * .32 + file * 1.3)
	else:
		reach += target.radius
		at = target.position + Vector3(-forward, 0, 0).rotated(Vector3.UP, file * .48) * reach
	return game.clamp_to_map(at)

func _command_hero(armies: Array) -> void:
	if not is_instance_valid(game.heroes[1]) or not game.heroes[1].alive: return
	var hero: MobaHero = game.heroes[1]
	if hero.hp <= hero.max_hp * .35: retreating = true
	if hero.hp >= hero.max_hp * .88: retreating = false
	# A partial heal can land between the normal healing threshold and the
	# retreat exit threshold. Continue healing there instead of waiting forever.
	if retreating or hero.hp <= hero.max_hp * .72: hero.cast_recovery()
	if retreating:
		var shelter: Vector3 = game.bases[1].position + Vector3(-9, 0, 0)
		for tier: Array in game.fronts[1]:
			for fort: BattleBuilding in tier:
				if is_instance_valid(fort) and fort.alive and fort.position.x >= hero.position.x:
					if fort.position.distance_to(hero.position) < shelter.distance_to(hero.position): shelter = fort.position + Vector3(6, 0, 7)
		if hero.destination.distance_to(shelter) > 3 or hero.order == BattleUnit.Order.IDLE: hero.issue_move(shelter)
		return
	var allied_near: int = 0
	var frontline: float = game.bases[1].position.x - 8
	for ally: BattleUnit in armies[1]:
		if ally == hero: continue
		if ally.position.distance_squared_to(hero.position) <= 9: allied_near += 1
		if ally._stats.projectile.is_empty(): frontline = minf(frontline, ally.position.x)
	if allied_near >= 2: hero.cast_morale()
	var objective := objective_for(1, -1)
	if objective == null: return
	# HOLD keeps the rifle at its firing line. Attack-move would chase a fleeing
	# soldier through the tower's range and throw away the hero's range advantage.
	if hero._can_start_strike(objective):
		if hero.order != BattleUnit.Order.HOLD: hero.hold()
		hero.target = objective
		return
	if hero._valid_target(hero.target) and hero._can_start_strike(hero.target):
		if hero.order != BattleUnit.Order.HOLD:
			var victim: Node3D = hero.target
			hero.hold()
			hero.target = victim
		return
	var footprint: Vector3 = objective.get_footprint_size()
	var safety := maxf(objective._stats.range + hero.radius + 1.5, hero.weapon.definition.range * .82)
	var at := Vector3(maxf(frontline + 3, objective.position.x + footprint.x * .5 + safety), 0, -7)
	if hero.order == BattleUnit.Order.IDLE or hero.destination.distance_to(at) > 3:
		hero.issue_move(at)
		hero.hold(true)
		hero.set_meta("moba_objective", objective.entity_id)

func _buy_card(armies: Array) -> void:
	var enemy_cavalry: int = 0
	var our_spears: int = 0
	var our_cannons: int = 0
	var frontline: int = 0
	var ranged: int = 0
	for unit: BattleUnit in armies[0]:
		if unit._stats.combat_class == &"cavalry": enemy_cavalry += 1
	for unit: BattleUnit in armies[1]:
		if unit is HeroUnit: continue
		if unit.unit_type == "spearman": our_spears += 1
		if unit.unit_type == "cannon": our_cannons += 1
		if unit._stats.projectile.is_empty(): frontline += 1
		else: ranged += 1
	var best: int = -1
	var best_score: float = -INF
	for index: int in game.hands[1].slots.size():
		var entry: Dictionary = game.hands[1].slots[index]
		var card: MobaCardDefinition = entry.card
		if card == null or game.army_counts[1] + card.units.size() > game.ARMY_CAP: continue
		var score: float = card.units.size() * 8.0 - card.cost * .03
		var melee_card: bool = BalanceCatalog.unit(card.units[0]).projectile.is_empty()
		if melee_card and frontline < ranged * .65: score += 32
		if not melee_card and ranged < frontline * .7: score += 24
		if card.id == &"spears" and enemy_cavalry * 2 > our_spears: score += 40
		if card.id == &"cannon" and our_cannons < 3 and frontline >= 4: score += 48
		if score > best_score: best_score = score; best = index
	# Save for the chosen reinforcement; repeatedly buying the cheapest card
	# otherwise prevents the commander from ever affording a siege unit.
	if best >= 0 and game.card_error(1, best, game.hands[1].slots[best].uid).is_empty():
		game.play_card(1, best, game.hands[1].slots[best].uid)
