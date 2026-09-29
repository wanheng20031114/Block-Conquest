extends RefCounted
## Environment bonuses are summed separately from temporary skill bonuses.

const FORGE_ATTACK: Array[float] = [0.0, 0.30, 0.50, 0.70, 0.80]
const FORGE_DEFENSE: Array[float] = [0.0, 0.15, 0.25, 0.35, 0.40]
const FORGE_SPEED_PER_BUILDING := 0.10
const TOWER_DEFENSE: Array[float] = [0.25, 0.40, 0.60, 0.70]

static func forge_attack_bonus(count: int) -> float:
	return FORGE_ATTACK[mini(count, FORGE_ATTACK.size() - 1)]

static func forge_defense_bonus(count: int) -> float:
	return FORGE_DEFENSE[mini(count, FORGE_DEFENSE.size() - 1)]

static func forge_speed_bonus(count: int) -> float:
	return count * FORGE_SPEED_PER_BUILDING

static func tower_defense_bonus(level: int) -> float:
	return TOWER_DEFENSE[level - 1]
