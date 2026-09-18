class_name UnitVariantCatalog
extends RefCounted
## Kept out of BalanceCatalog: these grades have no recruitment/network entry.
const ADVANCED: Dictionary[String, UnitVariantDefinition] = {
	"musketeer": preload("res://data/sandbox/unit_variants/musketeer_advanced.tres"),
	"swordsman": preload("res://data/sandbox/unit_variants/swordsman_advanced.tres"),
	"shield_guard": preload("res://data/sandbox/unit_variants/shield_guard_advanced.tres"),
	"spearman": preload("res://data/sandbox/unit_variants/spearman_advanced.tres"),
	"archer": preload("res://data/sandbox/unit_variants/archer_advanced.tres"),
}
