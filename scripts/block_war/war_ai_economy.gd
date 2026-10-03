extends RefCounted
## Invest in one spare forge only after observing sustained own skill demand.

const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const OBSERVATION_SECONDS := 30.0
const PRESSURE_SECONDS := 12.0
const LOW_ENERGY := 45.0

var faction := 1
var _observed_since := -1.0
var _last_observed_at := -1.0
var _last_energy_low := false
var _low_energy_seconds := 0.0
# Each entry records a paid skill decision's time and actual energy cost.
var _recent_spending: Array[Vector2] = []

func _init(controlled_faction: int = 1) -> void:
	faction = controlled_faction

func observe(game: Node3D) -> void:
	var now: float = game.elapsed
	var state: RefCounted = game.faction_skills[faction]
	var energy_low: bool = state.energy < LOW_ENERGY
	if _last_observed_at < 0.0 or now < _last_observed_at or now - _last_observed_at > OBSERVATION_SECONDS:
		# A new match or a gap cannot prove continuous pressure in between.
		_observed_since = now
		_low_energy_seconds = 0.0
		_recent_spending.clear()
	elif now == _last_observed_at:
		return
	else:
		var delta := now - _last_observed_at
		_low_energy_seconds = _low_energy_seconds + delta if energy_low and _last_energy_low else 0.0
		while not _recent_spending.is_empty() and _recent_spending[0].x < now - OBSERVATION_SECONDS:
			_recent_spending.pop_front()
	_last_observed_at = now
	_last_energy_low = energy_low

func record_spending(at: float, spent: float) -> void:
	if spent > 0.0:
		_recent_spending.append(Vector2(at, spent))

func tower_score(game: Node3D, building: WarBuilding, homes: int, reserve: float,
		enemy_distance: float, under_attack: bool) -> float:
	if _observed_since < 0.0 or _last_observed_at - _observed_since < OBSERVATION_SECONDS \
			or _low_energy_seconds < PRESSURE_SECONDS or _recent_spending.size() < 2:
		return 0.0
	var recent_spending := 0.0
	for payment: Vector2 in _recent_spending:
		recent_spending += payment.y
	var natural_income := SKILL_RULES.natural_energy_between(game.elapsed - OBSERVATION_SECONDS, OBSERVATION_SECONDS)
	if recent_spending < natural_income or homes < 2 or under_attack:
		return 0.0
	if building.faction != faction or building.kind != 2 or building.is_constructing:
		return 0.0
	if building.available_population < WarBuilding.conversion_cost_for(building.kind, 3) + reserve:
		return 0.0
	var retained_forges := 0
	for owned: WarBuilding in game.buildings:
		if owned.faction != faction:
			continue
		# Count ownership, including sealed towers and paid construction. Active
		# regeneration alone would buy replacements during a temporary seal.
		if owned.kind == 3 or (owned.is_constructing and owned.conversion_target == 3):
			return 0.0
		if owned.kind == 2 and (not owned.is_constructing or owned.conversion_target == -1):
			retained_forges += 1
	if retained_forges < 2:
		return 0.0
	# Keep early housing ahead of this optional investment; prefer the rear.
	return 16.0 + minf(maxf(enemy_distance, 0.0), 60.0) / 15.0
