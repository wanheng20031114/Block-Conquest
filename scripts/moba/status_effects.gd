extends Node
## Refresh one named modifier; never multiply the previous result or mutate shared resources.
var recipients: Dictionary = {}

func apply_morale(caster: MobaHero) -> void:
	for unit: BattleUnit in get_parent().unit_container.get_children():
		if unit.alive and unit.alliance_id == caster.alliance_id and Vector2(unit.position.x - caster.position.x, unit.position.z - caster.position.z).length_squared() <= 9.000001:
			unit.movement_multiplier = 1.25
			recipients[unit.entity_id] = {"unit": unit, "remaining": 3.0}

func advance(delta: float) -> void:
	for id: int in recipients.keys():
		var entry: Dictionary = recipients[id]
		entry.remaining -= delta
		if not is_instance_valid(entry.unit):
			recipients.erase(id)
		elif entry.remaining <= .000001 or not entry.unit.alive:
			entry.unit.movement_multiplier = 1.0
			recipients.erase(id)

func reset() -> void:
	for entry: Dictionary in recipients.values():
		if is_instance_valid(entry.unit): entry.unit.movement_multiplier = 1.0
	recipients.clear()
