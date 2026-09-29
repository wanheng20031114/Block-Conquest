extends RefCounted
## Read-only local diagnostics. Never expose another player's private account
## or the garrison of a building hidden by the normal visibility rules.

static func capture(game: Node3D) -> Dictionary:
	var faction: int = game.local_faction
	var level: int = game.morale.level(faction)
	var counts: Array[int] = [0, 0, 0, 0]
	var garrison := 0.0
	var queued := 0
	var marching := 0
	for building: WarBuilding in game.buildings:
		if building.faction == faction:
			counts[building.kind] += 1
			garrison += building.population
			queued += building.queued_population
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.alive and unit.order.faction == faction and not unit.pending_departure:
			marching += 1
	var selected: Dictionary = {}
	var target: WarBuilding = game.selected
	if target != null:
		var known := target.is_population_visible()
		selected = {
			"id": target.building_id, "kind_name": WarBuilding.KIND_NAMES[target.kind], "level": target.level,
			"owner": game.faction_name(target.faction) if target.faction >= 0 else "中立",
			"population": target.population if known else -1.0,
			"available": target.available_population if known else -1.0,
			"queued": target.queued_population if known else -1,
			"defense_multiplier": game.morale.defense(target.faction) + game.defense_bonus(target),
			"skill_defense": game.skill_defense_bonus(target),
			"construction_remaining": target.construction_remaining,
			"disruption_remaining": target.disruption_remaining,
		}
	var forges: int = game.forge_count(faction)
	var morale_attack: float = game.morale.attack(faction) - 1.0
	var morale_defense: float = game.morale.defense(faction) - 1.0
	var morale_speed: float = game.morale.speed(faction) - 1.0
	var forge_attack: float = game.COMBAT_RULES.forge_attack_bonus(forges)
	var forge_defense: float = game.COMBAT_RULES.forge_defense_bonus(forges)
	var fps := float(Engine.get_frames_per_second())
	return {
		"commander_name": game.SKILL_RULES.name_for(game.faction_skills[faction].commander),
		"faction_name": game.faction_name(faction),
		"mode": "单机" if game.match_config.is_empty() else ("联机主机" if game.is_authority() else "联机客户端"),
		"match_state": "对局结束" if game.finished else ("已投降 · 观战" if game.has_surrendered(faction) else ("暂停" if game.is_rule_paused() else "进行中")),
		"attack_multiplier": 1.0 + morale_attack + forge_attack,
		"defense_multiplier": 1.0 + morale_defense + forge_defense,
		"speed_multiplier": 1.0 + morale_speed, "move_speed": WarMarches.SPEED * (1.0 + morale_speed),
		"forge_attack": forge_attack, "forge_defense": forge_defense,
		"morale_attack": morale_attack, "morale_defense": morale_defense, "morale_speed": morale_speed,
		"morale_level": level, "morale_points": game.morale.points(faction),
		"morale_next": game.MORALE.THRESHOLDS[level + 1] if level < 5 else -1.0,
		"buildings": counts, "forges_active": forges, "energy_towers_active": game.energy_tower_count(faction),
		"garrison": garrison, "marching": marching, "queued": queued, "army_total": garrison + marching,
		"energy": game.faction_skills[faction].energy, "energy_max": game.ENERGY_MAX, "energy_regen": game.energy_regen_for(faction),
		"energy_natural_regen": game.SKILL_RULES.natural_energy_regen(game.elapsed),
		"combat_energy_per_loss": game.SKILL_RULES.combat_energy_per_loss(game.morale.stars(faction)),
		"selected": selected, "fps": fps, "frame_ms": 1000.0 / fps if fps > 0.0 else 0.0, "sim_time": game.elapsed,
	}
