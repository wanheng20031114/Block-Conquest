extends SceneTree
## Approved kill breakpoints and a complete pre-change damage matrix regression.
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/crossbow-20260914"))
	var families := {"swordsman":&"infantry","shield_guard":&"infantry","spearman":&"infantry","archer":&"infantry","crossbowman":&"infantry","musketeer":&"infantry","engineer":&"infantry","priest":&"infantry","farmer":&"infantry","knight":&"cavalry","light_cavalry":&"cavalry","war_elephant":&"cavalry","catapult":&"siege","cannon":&"siege","heavy_cannon":&"siege","triple_cannon":&"siege"}
	for kind: String in BalanceCatalog.UNITS:
		var unit := BalanceCatalog.unit(kind)
		check(unit.combat_class == families[kind] and unit.validation_errors().is_empty(),kind+" family and valid contract")
		check(unit.is_support() == (kind in ["engineer","priest"]),kind+" support role")
		check(unit.is_construction() == (kind == "farmer") and unit.military == (kind != "farmer"),kind+" construction role and population")
		check(unit.is_ranged_infantry() == (kind in ["archer","crossbowman","musketeer"]),kind+" ranged infantry derivation")
	for kind: String in BalanceCatalog.BUILDINGS:
		check(BalanceCatalog.building(kind).validation_errors().is_empty(),kind+" building contract")
	var crossbow := BalanceCatalog.unit("crossbowman")
	var payload := DamageResolver.snapshot(crossbow,0,0,0)
	var hits := {"swordsman":13,"spearman":9,"shield_guard":29,"archer":9,"knight":24,"light_cavalry":10,"war_elephant":40,"engineer":9,"priest":8,"catapult":16,"cannon":20,"heavy_cannon":29,"triple_cannon":18,"farmer":17,"crossbowman":7}
	var damages := {"swordsman":9,"spearman":9,"shield_guard":5,"archer":7,"knight":5,"light_cavalry":9,"war_elephant":9,"engineer":9,"priest":9,"catapult":9,"cannon":9,"heavy_cannon":9,"triple_cannon":9,"farmer":9,"crossbowman":9}
	for kind: String in hits:
		var target := BalanceCatalog.unit(kind)
		var damage := DamageResolver.resolve(payload,target)
		check(damage == damages[kind] and ceili(target.hp/damage) == hits[kind],"crossbow approved damage and kill breakpoint: "+kind)
	for row: Array in [["knight",12,5],["light_cavalry",9,7],["archer",9,7],["triple_cannon",28,3],["catapult",24,3],["cannon",38,2],["heavy_cannon",98,1]]:
		var damage := DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit(row[0]),0,1,1),crossbow)
		check(damage == row[1] and ceili(crossbow.hp/damage) == row[2],"incoming crossbow damage: "+row[0])
	check(DamageResolver.resolve(payload,BalanceCatalog.building("barracks")) == 2,"building penetration has no building bonus")
	check(DamageResolver.resolve(payload,BalanceCatalog.unit("shield_guard"),3) == 2,"penetration follows full defense technology")
	check(DamageResolver.resolve(DamageResolver.snapshot(crossbow,4,0,0),BalanceCatalog.unit("shield_guard"),3) == 6,"attack research adds four without scaling penetration")
	var renamed: UnitDefinition = crossbow.duplicate()
	renamed.id = &"different_unit_name"
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("knight"),0,0,0),renamed) == 12,"counter selection never depends on unit name")
	renamed.armor_penetration = 90
	renamed.damage = 1
	check(DamageResolver.resolve(DamageResolver.snapshot(renamed,0,0,0),BalanceCatalog.unit("shield_guard")) == 1,"excess penetration cannot create bonus damage")
	check(payload.armor_penetration == 3 and payload.base_damage == 9,"launch snapshot remains immutable")
	var overlap := DamageResolver.snapshot(crossbow,0,0,0)
	overlap.bonuses = {&"infantry":3,&"ranged_infantry":5}
	check(DamageResolver.resolve(overlap,crossbow)==14,"overlapping family and subgroup bonuses apply once")
	renamed.combat_class = &"archer"
	check(not renamed.validation_errors().is_empty(),"legacy mixed-axis class rejected")
	renamed.combat_class = &"infantry"
	renamed.role = UnitDefinition.Role.SUPPORT
	check(not renamed.validation_errors().is_empty(),"support role without capability rejected")
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/combat-before-crossbow.json"))
	for attack_id: String in baseline:
		var old_a: Dictionary = baseline[attack_id]
		var attacker: CombatDefinition = BalanceCatalog.BUILDINGS[attack_id] if old_a.building else BalanceCatalog.UNITS[attack_id]
		for target_id: String in baseline:
			var old_d: Dictionary = baseline[target_id]
			var defender: CombatDefinition = BalanceCatalog.BUILDINGS[target_id] if old_d.building else BalanceCatalog.UNITS[target_id]
			for attack_upgrade: int in [0,4]:
				for defense_upgrade: int in [0,3]:
					var armor: float = old_d.ranged_armor+defense_upgrade if old_a.damage_channel == 1 else old_d.melee_armor+(defense_upgrade if old_d.melee_defense_upgrades else 0)
					var bonus: float = old_a.bonuses.get(old_d.combat_class,0)
					# The one explicitly approved balance change: all infantry receive infantry bonus.
					if target_id in ["archer","farmer"]: bonus = maxf(bonus,old_a.bonuses.get("infantry",0))
					var expected: float = maxf(1,old_a.damage+attack_upgrade+bonus-armor)
					check(DamageResolver.resolve(DamageResolver.snapshot(attacker,attack_upgrade,0,0),defender,defense_upgrade)==expected,
						"legacy matrix %s/%s +%d/%d" % [attack_id,target_id,attack_upgrade,defense_upgrade])
	var accumulated: float = 0
	var began: int = Time.get_ticks_usec()
	for index: int in 100000:
		accumulated += DamageResolver.resolve(payload,BalanceCatalog.unit("shield_guard"),index%4)
	var microseconds: int = Time.get_ticks_usec()-began
	check(accumulated>0,"damage timing sample executed")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/crossbow-20260914"))
	FileAccess.open("res://.local/crossbow-20260914/balance-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"resolver_100000_hits_us":microseconds,"crossbow_kill_hits":hits,"crossbow_damage":damages},"\t"))
	print("CROSSBOW_BALANCE ",checks," checks; ",failures.size()," failures; 100k hits ",microseconds," us")
	quit(0 if failures.is_empty() else 1)
