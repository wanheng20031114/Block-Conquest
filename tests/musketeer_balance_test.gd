extends SceneTree
## Approved full-health breakpoints, technology and class consumers.
const OUTPUT := "res://.local/musketeer-20260914/"
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var unit := BalanceCatalog.unit("musketeer")
	check(unit.cost==150 and unit.hp==75 and unit.damage==22 and unit.armor_penetration==3,"approved price, health, damage and penetration")
	check(unit.melee_armor==0 and unit.ranged_armor==1 and unit.range==7 and unit.min_range==0 and unit.cooldown==2.2 and unit.attack_windup_seconds==.35,"approved defense and firing timing")
	check(unit.speed==3.6 and unit.radius==.42 and unit.sight==14 and unit.supply==1 and unit.training_seconds==15 and unit.production_building==&"barracks","approved movement and training")
	check(unit.is_ranged_infantry() and unit.combat_class==&"infantry" and unit.role==UnitDefinition.Role.COMBAT and unit.military,"independent family, attack and role axes")
	check(unit.bonuses.is_empty() and unit.splash_radius==0 and unit.independent_weapons==1 and unit.projectile=="bullet" and not unit.cannon_range_upgrades,"single bullet without hidden siege rules")
	check(unit.validation_errors().is_empty(),"valid resource")
	var payload := DamageResolver.snapshot(unit,0,0,0)
	var table := {
		"swordsman":[22,5],"spearman":[22,4],"shield_guard":[18,9],"archer":[20,3],"crossbowman":[22,3],
		"knight":[18,7],"light_cavalry":[22,5],"war_elephant":[22,17],"engineer":[22,4],"priest":[22,4],
		"catapult":[22,7],"cannon":[22,9],"heavy_cannon":[22,12],"triple_cannon":[22,8],"farmer":[22,7],"musketeer":[22,4]}
	for kind: String in table:
		var defender := BalanceCatalog.unit(kind)
		var damage := DamageResolver.resolve(payload,defender)
		check(damage==table[kind][0] and ceili(defender.hp/damage)==table[kind][1],"outgoing damage and hits "+kind)
	for row: Array in [["swordsman",9,9],["knight",12,7],["light_cavalry",9,9],["war_elephant",32,3],["archer",10,8],["crossbowman",9,9],["catapult",25,3],["cannon",39,2],["triple_cannon",29,3],["heavy_cannon",99,1]]:
		var damage := DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit(row[0]),0,1,1),unit)
		check(damage==row[1] and ceili(unit.hp/damage)==row[2],"incoming damage and hits "+row[0])
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.building("defense_tower"),0,1,1),unit)==18,"tower infantry bonus includes musketeer")
	check(DamageResolver.resolve(payload,BalanceCatalog.building("barracks"))==15,"ten-armor building takes fifteen without building bonus")
	check(DamageResolver.resolve(payload,BalanceCatalog.unit("shield_guard"),3)==15,"defense technology applied before fixed penetration")
	check(DamageResolver.resolve(DamageResolver.snapshot(unit,4,0,0),BalanceCatalog.unit("shield_guard"),3)==19,"attack technology does not scale penetration")
	var renamed: UnitDefinition = unit.duplicate()
	renamed.id = &"arbitrary_name"
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("knight"),0,1,1),renamed)==12,"cavalry bonus follows classification rather than unit id")
	renamed.projectile = "misspelled_bullet"
	check(not renamed.validation_errors().is_empty(),"unknown projectile cannot silently enter splash path")
	FileAccess.open(OUTPUT+"balance-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"damage_and_hits":table},"\t"))
	print("MUSKETEER_BALANCE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
