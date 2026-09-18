extends Node
## One shared strategic pass; native units own local targeting, contact and cooldowns.
var decision_in: float = 0.0
var card_in: float = 3.0
var decisions: int = 0
var orders_issued: int = 0
var retreating: bool = false
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
	var sign_x := -1.0 if unit.owner_id == 0 else 1.0
	var lane: int = unit.get_meta("moba_lane")
	unit.issue_move(Vector3(sign_x * 70, 0, lane * 11), true)
	unit.queue_move(Vector3(sign_x * 44, 0, lane * 10), true)
	unit.queue_move(Vector3(sign_x * 3, 0, lane * 4), true)
	var target := objective_for(unit.owner_id, lane)
	if target != null:
		unit.queue_move(target.position, true)
		unit.set_meta("moba_objective", target.entity_id)
	orders_issued += 1

func advance(delta: float) -> void:
	decision_in -= delta
	card_in -= delta
	if decision_in > 0: return
	decision_in = .5
	decisions += 1
	var targets := [objectives(0), objectives(1)]
	for unit: BattleUnit in game.unit_container.get_children():
		if not unit.alive or unit is HeroUnit: continue
		var choices: Array = targets[unit.owner_id]
		if choices.is_empty(): continue
		var lane: int = unit.get_meta("moba_lane")
		var objective: BattleBuilding = choices[0] if choices.size() == 1 or lane < 0 else choices[1]
		var changed: bool = unit.get_meta("moba_objective", 0) != objective.entity_id
		if not changed and unit.order != BattleUnit.Order.IDLE: continue
		# Do not reset active contacts/windups. A destroyed objective will be
		# replaced once native combat releases the local target.
		if unit.battery.winding or (is_instance_valid(unit.target) and unit.target.alive): continue
		unit.issue_move(objective.position, true)
		unit.set_meta("moba_objective", objective.entity_id)
		orders_issued += 1
	_command_hero()
	if card_in <= 0:
		card_in = 2.8
		_buy_card()

func _command_hero() -> void:
	if not is_instance_valid(game.heroes[1]) or not game.heroes[1].alive: return
	var hero: MobaHero = game.heroes[1]
	if hero.hp <= hero.max_hp * .72: hero.cast_recovery()
	if hero.hp <= hero.max_hp * .35: retreating = true
	if hero.hp >= hero.max_hp * .88: retreating = false
	if retreating:
		var shelter: Vector3 = game.bases[1].position + Vector3(-9, 0, 0)
		if hero.destination.distance_to(shelter) > 3 or hero.order == BattleUnit.Order.IDLE:
			hero.issue_move(shelter)
		return
	var allied_near: int = 0
	for unit: BattleUnit in game.unit_container.get_children():
		if unit.alive and unit.owner_id == 1 and unit != hero and unit.position.distance_squared_to(hero.position) <= 9: allied_near += 1
	if allied_near >= 2: hero.cast_morale()
	var objective := objective_for(1, -1)
	if objective == null: return
	if is_instance_valid(hero.target) and hero.target.alive: return
	if hero.order == BattleUnit.Order.IDLE or hero.get_meta("moba_objective", 0) != objective.entity_id:
		hero.issue_move(objective.position, true)
		hero.set_meta("moba_objective", objective.entity_id)

func _buy_card() -> void:
	var enemy_cavalry: int = 0
	var our_spears: int = 0
	var our_cannons: int = 0
	for unit: BattleUnit in game.unit_container.get_children():
		if not unit.alive or unit is HeroUnit: continue
		if unit.owner_id == 0 and unit._stats.combat_class == &"cavalry": enemy_cavalry += 1
		if unit.owner_id == 1 and unit.unit_type == "spearman": our_spears += 1
		if unit.owner_id == 1 and unit.unit_type == "cannon": our_cannons += 1
	var best: int = -1
	var best_score: float = -INF
	for index: int in game.hands[1].slots.size():
		var entry: Dictionary = game.hands[1].slots[index]
		if not game.card_error(1, index, entry.uid).is_empty(): continue
		var card: MobaCardDefinition = entry.card
		var score: float = card.units.size() * 8.0 - card.cost * .03
		if card.id == &"spears" and enemy_cavalry * 2 > our_spears: score += 40
		if card.id == &"cannon" and our_cannons < 2: score += 38
		if card.id == &"guards" and game.army_counts[1] > 12: score += 16
		if score > best_score: best_score = score; best = index
	if best >= 0: game.play_card(1, best, game.hands[1].slots[best].uid)
