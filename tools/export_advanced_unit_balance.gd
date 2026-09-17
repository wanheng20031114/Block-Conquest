extends SceneTree
## Design-only resources are never added to the gameplay catalogue.
## All report damage comes from the live resolver, including every tech pairing.
const DESIGN := "res://docs/balance/advanced-units-design.json"
const FAMILIES := ["swordsman", "shield_guard", "spearman", "archer", "crossbowman", "musketeer", "knight", "light_cavalry", "war_elephant"]
const STATS := ["hp", "damage", "melee_armor", "ranged_armor", "armor_penetration"]
const BUILDINGS := ["headquarters", "barracks", "factory", "academy", "defense_tower", "cannon_tower", "castle", "heavy_fortress"]

func _initialize() -> void: _export.call_deferred()

func _export() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1, "Expected one output JSON path")
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DESIGN))
	assert(design.units.size() == FAMILIES.size())
	var definitions: Dictionary[String, UnitDefinition] = {}
	var unit_data: Dictionary = {}
	for id: String in BalanceCatalog.UNITS:
		definitions[id] = BalanceCatalog.unit(id)
		unit_data[id] = _data(definitions[id])
	var seen: Array[String] = []
	for row: Dictionary in design.units:
		var id: String = row.id
		assert(id in FAMILIES and id not in seen)
		seen.append(id)
		var variant := UnitVariantDefinition.new()
		variant.base = definitions[id]
		variant.display_name = "高级" + variant.base.name
		for property: String in STATS:
			assert(float(row[property]) == floorf(float(row[property])), id + " must use integer " + property)
			variant.set(property, int(row[property]))
		for group: String in row.bonuses:
			assert(float(row.bonuses[group]) == floorf(float(row.bonuses[group])))
			variant.bonuses[StringName(group)] = int(row.bonuses[group])
		var advanced := variant.definition()
		assert(advanced.validation_errors().is_empty())
		assert(advanced.hp >= variant.base.hp * 1.15 and advanced.hp <= variant.base.hp * 1.25)
		definitions[String(advanced.id)] = advanced
		unit_data[String(advanced.id)] = _data(advanced)
		assert(_data(variant.base) == unit_data[id], "Variant must not modify the base resource")
		if UnitVariantCatalog.ADVANCED.has(id):
			assert(_data(UnitVariantCatalog.ADVANCED[id].definition()) == _data(advanced), "Shipped variant differs from design: " + id)
	var attacks: Array[int] = []
	var defenses: Array[int] = []
	for level: int in 4:
		var state := PlayerState.new(0, 0)
		state.attack_level = level
		state.defense_level = level
		attacks.append(state.get_attack_bonus())
		defenses.append(state.get_defense_bonus())
	# Compact rows: attacker, defender, attack level, defense level, damage, hits.
	var rows: Array[Array] = []
	for attacker: UnitDefinition in definitions.values():
		for defender: UnitDefinition in definitions.values():
			for al: int in 4:
				for dl: int in 4:
					rows.append(_row(attacker, defender, al, dl, attacks[al] if attacker.military else 0, defenses[dl] if defender.military else 0))
	var building_data: Dictionary = {}
	var building_rows: Array[Array] = []
	for id: String in BUILDINGS:
		var building := BalanceCatalog.building(id)
		building_data[id] = _combat_data(building)
		for unit: UnitDefinition in definitions.values():
			for level: int in 4:
				building_rows.append(_row(unit, building, level, 0, attacks[level] if unit.military else 0, 0))
				if building.damage > 0:
					building_rows.append(_row(building, unit, 0, level, 0, defenses[level] if unit.military else 0))
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"schema_version": 1, "revision": design.revision,
		"design_sha256": FileAccess.get_sha256(DESIGN), "families": FAMILIES,
		"units": unit_data, "buildings": building_data,
		"attack_bonuses": attacks, "defense_bonuses": defenses,
		"row_columns": ["attacker", "defender", "attack_level", "defense_level", "damage", "hits"],
		"matchups": rows, "building_matchups": building_rows}, "\t"))
	file.close()
	print("ADVANCED_BALANCE_EXPORT ", rows.size(), " unit and ", building_rows.size(), " building cases; authored variant matches report")
	quit()

func _row(a: CombatDefinition, d: CombatDefinition, al: int, dl: int, attack: int, defense: int) -> Array:
	var damage := DamageResolver.resolve(DamageResolver.snapshot(a, attack, 0, 0), d, defense)
	return [a.id, d.id, al, dl, damage, ceili(d.hp / damage)]

func _combat_data(d: CombatDefinition) -> Dictionary:
	return {"id": d.id, "name": d.name, "hp": d.hp, "damage": d.damage,
		"melee_armor": d.melee_armor, "ranged_armor": d.ranged_armor, "armor_penetration": d.armor_penetration,
		"damage_channel": d.damage_channel, "combat_class": d.combat_class, "bonuses": d.bonuses,
		"range": d.range, "cooldown": d.cooldown, "splash_radius": d.splash_radius,
		"melee_defense_upgrades": d.melee_defense_upgrades}

func _data(d: UnitDefinition) -> Dictionary:
	var result := _combat_data(d)
	result.merge({"speed": d.speed, "sight": d.sight, "min_range": d.min_range,
		"supply": d.supply, "radius": d.radius, "windup": d.attack_windup_seconds,
		"cost": d.cost, "training_seconds": d.training_seconds, "production_building": d.production_building,
		"role": d.role, "independent_weapons": d.independent_weapons})
	return result
