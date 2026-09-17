extends SceneTree
## Actual sandbox/codex integration plus a design-only nine-family matchup study.
const OUTPUT := "res://.local/advanced-units/"
const FAMILIES := ["swordsman", "shield_guard", "spearman", "archer", "crossbowman", "musketeer", "knight", "light_cavalry", "war_elephant"]
var checks := 0
var failures: Array[String] = []
var study: Array[Dictionary] = []
var game: Node3D

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var variant: UnitVariantDefinition = UnitVariantCatalog.ADVANCED["musketeer"]
	var base := BalanceCatalog.unit("musketeer")
	var advanced := variant.definition()
	check(UnitVariantCatalog.ADVANCED.size() == 1 and not BalanceCatalog.UNITS.has("musketeer_advanced"), "Only current accepted-stage sample is registered, outside recruitment roster")
	check(base.hp == 75 and base.damage == 22 and base.ranged_armor == 1 and base.armor_penetration == 3, "Normal resource unchanged")
	check(advanced.hp == 90 and is_equal_approx(advanced.damage, 26.4) and advanced.melee_armor == 0 and is_equal_approx(advanced.ranged_armor, 1.2) and is_equal_approx(advanced.armor_penetration, 3.6), "Advanced combat values")
	check(advanced.range == 7 and advanced.speed == 3.6 and advanced.cooldown == 2.2 and advanced.attack_windup_seconds == .35 and advanced.radius == base.radius, "Role, timing, footprint preserved")
	check(advanced.is_ranged_infantry() and advanced.validation_errors().is_empty(), "Advanced remains valid ranged infantry")
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("knight"), 0, 1, 1), advanced) == 12, "Cavalry counter still applies")
	check(is_equal_approx(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("triple_cannon"), 0, 1, 1), advanced), 28.8), "Infantry counter still applies")
	for attacker: String in FAMILIES:
		for defender: String in FAMILIES:
			var a := BalanceCatalog.unit(attacker)
			var d := BalanceCatalog.unit(defender)
			# These temporary definitions are analytical fixtures, never catalogue entries.
			var av := UnitVariantDefinition.new()
			av.base = a
			var dv := UnitVariantDefinition.new()
			dv.base = d
			var damage: float = DamageResolver.resolve(DamageResolver.snapshot(a, 0, 0, 0), d)
			var scaled: float = DamageResolver.resolve(DamageResolver.snapshot(av.definition(), 0, 0, 0), dv.definition())
			var old_hits := ceili((d.hp - .000001) / damage)
			var new_hits := ceili((dv.definition().hp - .000001) / scaled)
			check(old_hits == new_hits, "Same-grade baseline hits: " + attacker + " -> " + defender)
			study.append({"attacker": attacker, "defender": defender, "normal_damage": damage, "advanced_damage": scaled, "normal_hits": old_hits, "advanced_hits": new_hits})
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	codex.select_entry(0, "musketeer")
	var count: int = codex._entries.size()
	codex.get_node("%AdvancedGrade").pressed.emit()
	check(codex.advanced and codex.selected_id == "musketeer" and codex._entries.size() == count, "Codex toggle preserves page and entry count")
	check(codex._preview_unit.grade == &"advanced" and codex.get_node("%EntryTitle").text == "高级火枪手", "Codex advanced model and title")
	check("26.4" in codex.get_node("%Stats").text and "3.6" in codex.get_node("%Stats").text and "训练费用" not in codex.get_node("%Stats").text, "Codex displays fractional stats and sandbox availability")
	codex.select_entry(0, "priest")
	check(not codex.advanced and not codex.get_node("%GradeRow").visible, "Unsupported family has no grade toggle")
	codex.select_entry(1, "castle")
	check(not codex.get_node("%GradeRow").visible, "Buildings unchanged")
	codex.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.set_paint_kind("musketeer")
	game.hud.get_node("%AdvancedGrade").pressed.emit()
	check(game.paint_advanced and game._ghost.grade == &"advanced", "Sandbox grade button changes placement ghost")
	var normal: BattleUnit = game.spawn_unit("musketeer", 0, Vector3(-3, 0, 0))
	var elite: BattleUnit = game.spawn_variant("musketeer", 0, Vector3(0, 0, 0))
	check(elite.unit_type == "musketeer" and elite.display_name == "高级火枪手" and elite.max_hp == 90, "Entity uses family and grade independently")
	check(elite._model.grade == &"advanced" and elite.render_batches == game.get_node("VariantRenderBatches"), "Actual authored variant batch rig")
	game.select_entities([normal, elite])
	game.hud.refresh()
	var composition: SelectionComposition = game.hud.get_node("UnitPanel").composition
	check(composition.groups.size() == 2 and composition.total_count == 2, "Mixed grades retain separate composition groups")
	check(game.hud.portraits.has("musketeer_advanced"), "Advanced native portrait available")
	composition.activate(1)
	game.hud.refresh()
	check(composition.focused_entity() == elite, "Advanced subgroup focus")
	var payload := DamageResolver.snapshot(advanced, 0, 1, 1)
	for shot: int in 3: elite.receive_hit(payload)
	check(elite.alive and is_equal_approx(elite.hp, 10.8), "Three same-grade hits leave 10.8 HP")
	elite.receive_hit(payload)
	check(not elite.alive and elite.hp == 0, "Fourth actual hit kills, matching normal matchup")
	game.set_paint_kind("farmer")
	check(not game.paint_advanced and game._ghost.grade.is_empty(), "Changing to worker resets placement grade")
	game.set_running(false)
	game.clear_units()
	await physics_frame
	await physics_frame
	check(game.get_node("VariantRenderBatches").registered_models == 0, "Clearing releases grade batch registrations")
	# Real projectile path, not direct debug damage.
	var shooter: BattleUnit = game.spawn_variant("musketeer", 0, Vector3(0,0,3))
	var target: BattleUnit = game.spawn_unit("shield_guard", 1, Vector3(0,0,-3))
	target.hold()
	shooter.issue_attack(target)
	game.set_running(true)
	var began: float = game.elapsed
	while target.hp == target.max_hp and game.elapsed - began < 4:
		await physics_frame
	check(is_equal_approx(target.max_hp - target.hp, 23.0), "Real advanced bullet applies 26.4 damage, 3.6 penetration against seven armor")
	game.set_running(false)
	FileAccess.open(OUTPUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "same_grade_study": study}, "\t"))
	print("ADVANCED_MUSKETEER ", checks, " checks; ", failures.size(), " failures")
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
