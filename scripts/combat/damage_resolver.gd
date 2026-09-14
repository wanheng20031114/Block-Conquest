class_name DamageResolver
extends RefCounted
## Pure damage arithmetic: ownership, presentation and death handling stay in entities.

static func snapshot(definition: CombatDefinition, attack_bonus: float, owner_id: int, alliance_id: int) -> DamagePayload:
	var payload := DamagePayload.new()
	payload.base_damage = definition.damage
	payload.attack_bonus = attack_bonus
	payload.armor_penetration = definition.armor_penetration
	payload.bonuses = definition.bonuses.duplicate()
	payload.channel = definition.damage_channel
	payload.owner_id = owner_id
	payload.alliance_id = alliance_id
	return payload

static func resolve(payload: DamagePayload, defender: CombatDefinition, defense_bonus: float = 0.0) -> float:
	var armor: float = maxf(0.0, armor_for_channel(defender, payload.channel, defense_bonus) - payload.armor_penetration)
	var bonus: float = 0.0
	# A family and its subgroup may overlap: apply the strongest matching bonus
	# once, without allocating tag arrays or querying other units per hit.
	for group: StringName in payload.bonuses:
		if defender.matches_combat_group(group):
			bonus = maxf(bonus, float(payload.bonuses[group]))
	return maxf(1.0, payload.base_damage + payload.attack_bonus + bonus - armor)

static func armor_for_channel(definition: CombatDefinition, channel: CombatDefinition.DamageChannel, defense_bonus: float = 0.0) -> float:
	if channel == CombatDefinition.DamageChannel.MELEE:
		return definition.melee_armor + (defense_bonus if definition.melee_defense_upgrades else 0.0)
	return definition.ranged_armor + defense_bonus
