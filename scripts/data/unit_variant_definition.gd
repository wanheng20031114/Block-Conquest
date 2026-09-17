class_name UnitVariantDefinition
extends Resource
## Optional sandbox presentation and combat grade, independent of unit family.
@export var base: UnitDefinition
@export var grade: StringName = &"advanced"
@export var display_name: String
## Authored integer combat values; small armor/penetration values cannot be
## scaled uniformly without changing counter relationships and kill thresholds.
@export var hp: int = 1
@export var damage: int = 0
@export var melee_armor: int = 0
@export var ranged_armor: int = 0
@export var armor_penetration: int = 0
@export var bonuses: Dictionary[StringName, int] = {}
@export var model: PackedScene
@export var batched_model: PackedScene
var _definition: UnitDefinition

func definition() -> UnitDefinition:
	if _definition == null:
		assert(base.role == UnitDefinition.Role.COMBAT and base.combat_class != &"siege")
		assert(hp > 0 and damage >= 0 and melee_armor >= 0 and ranged_armor >= 0 and armor_penetration >= 0)
		_definition = base.duplicate(true) as UnitDefinition
		_definition.id = StringName(String(base.id) + "_" + String(grade))
		_definition.name = display_name
		for property: String in ["hp", "damage", "melee_armor", "ranged_armor", "armor_penetration"]:
			_definition.set(property, get(property))
		_definition.bonuses = bonuses.duplicate()
	return _definition
