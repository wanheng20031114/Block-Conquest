class_name RogueCatalog
extends RefCounted

const BALANCE: Resource = preload("res://data/rogue/first_floor.tres")
static var STRATEGIES: Dictionary = BALANCE.strategies
static var PACKS: Dictionary = BALANCE.packs
static var RECRUIT: Dictionary = BALANCE.recruit
static var RELICS: Dictionary = BALANCE.relics
static var EVENTS: Dictionary = BALANCE.events
const NODE_NAMES: Dictionary = {"road": "林间道路", "battle": "作战", "emergency": "紧急作战", "shop": "林中商店", "event": "不期而遇", "camp": "补给营地"}
const DEPLOYMENT_HALF_SIZE: float = 12.0
const SIEGE_BASE_HALF_SIZE: Vector2 = Vector2(5.65, 5.15)

static func is_ranged_infantry(kind: String) -> bool:
	return kind == "archer"
