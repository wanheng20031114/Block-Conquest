class_name MobaCardDefinition
extends Resource
## Only ARMY is implemented in test1; future types cannot fall through to spawning.
enum Type { ARMY, TACTIC, SUPPORT }
@export var id: StringName
@export var title: String
@export var type: Type = Type.ARMY
@export var cost: int = 100
@export var units: PackedStringArray
@export var description: String
@export var category: String
@export var color: Color = Color("58a779")

func is_valid() -> bool:
	return not id.is_empty() and cost > 0 and type == Type.ARMY and not units.is_empty() and Array(units).all(func(kind: String): return BalanceCatalog.UNITS.has(kind))
