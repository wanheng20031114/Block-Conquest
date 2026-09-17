class_name UnitVariantDefinition
extends Resource
## Optional sandbox presentation and combat grade, independent of unit family.
@export var base: UnitDefinition
@export var grade: StringName = &"advanced"
@export var display_name: String
@export var combat_scale: float = 1.2
@export var model: PackedScene
@export var batched_model: PackedScene
var _definition: UnitDefinition

func definition() -> UnitDefinition:
	if _definition == null:
		assert(base.role == UnitDefinition.Role.COMBAT and base.combat_class != &"siege")
		_definition = base.duplicate(true) as UnitDefinition
		_definition.id = StringName(String(base.id) + "_" + String(grade))
		_definition.name = display_name
		# Scale mitigation and counter damage with health and direct damage. This
		# preserves same-grade matchups instead of weakening existing counters.
		for property: String in ["hp", "damage", "melee_armor", "ranged_armor", "armor_penetration"]:
			_definition.set(property, snappedf(float(base.get(property)) * combat_scale, 0.0001))
		for group: StringName in _definition.bonuses:
			_definition.bonuses[group] = snappedf(float(base.bonuses[group]) * combat_scale, 0.0001)
	return _definition
