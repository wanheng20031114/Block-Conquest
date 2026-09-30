extends RefCounted
## Environment bonuses are summed separately from temporary skill bonuses.

const FORGE_ATTACK: Array[float] = [0.0, 0.30, 0.50, 0.70, 0.80]
const FORGE_DEFENSE: Array[float] = [0.0, 0.15, 0.25, 0.35, 0.40]
const HOUSE_DEFENSE: Array[float] = [0.0, 0.10, 0.20, 0.30]
const TOWER_DEFENSE: Array[float] = [0.30, 0.50, 0.60, 0.70]
const TOWER_ATTACK_INTERVALS: Array[float] = [1.0, 0.8, 0.6, 0.4]

static func forge_attack_bonus(count: int) -> float:
	return FORGE_ATTACK[mini(count, FORGE_ATTACK.size() - 1)]

static func forge_defense_bonus(count: int) -> float:
	return FORGE_DEFENSE[mini(count, FORGE_DEFENSE.size() - 1)]

static func tower_defense_bonus(level: int) -> float:
	return TOWER_DEFENSE[level - 1]

static func house_defense_bonus(level: int) -> float:
	return HOUSE_DEFENSE[level - 1]

static func building_defense_bonus(kind: int, level: int) -> float:
	match kind:
		0: return house_defense_bonus(level)
		1: return tower_defense_bonus(level)
	return 0.0

static func tower_attack_interval(level: int) -> float:
	return TOWER_ATTACK_INTERVALS[level - 1]
