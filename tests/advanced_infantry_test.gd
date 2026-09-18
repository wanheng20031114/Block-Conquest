extends SceneTree
## Sandbox/codex integration and real contact/arrow regression for a two-unit batch.
var families: Array[String] = ["swordsman", "shield_guard"]
const Probe = preload("res://tests/engagement_approach_test.gd").ApproachProbe
const UNIT := preload("res://scenes/unit.tscn")
const OUT := "res://.local/advanced-units/infantry/"
var output := OUT
var game: Node3D
var checks := 0
var failures: Array[String] = []
var contacts: Array[Dictionary] = []

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ", label)
func ticks(count: int) -> void:
	for tick: int in count:
		await physics_frame
		await process_frame
func clear() -> void:
	game.set_running(false)
	game.clear_units()
	await ticks(3)
	check(game.get_node("VariantRenderBatches").registered_models == 0, "variant slots released")

func _run() -> void:
	create_timer(180, true, false, true).timeout.connect(func(): quit(3))
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		families.assign(args)
		output = "res://.local/advanced-units/" + "-".join(families) + "/"
	for kind: String in families: assert(kind in ["swordsman", "shield_guard", "spearman", "archer"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var design: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/balance/advanced-units-design.json"))
	for kind: String in families:
		var variant: UnitVariantDefinition = UnitVariantCatalog.ADVANCED[kind]
		var advanced := variant.definition()
		var base := BalanceCatalog.unit(kind)
		var row: Dictionary = design.units.filter(func(value: Dictionary): return value.id == kind)[0]
		for property: String in ["hp", "damage", "melee_armor", "ranged_armor", "armor_penetration"]:
			check(advanced.get(property) == row[property], kind + " matches approved " + property)
		check(advanced.bonuses.size() == row.bonuses.size(), kind + " approved bonus categories")
		for group: String in row.bonuses:
			check(advanced.bonuses[StringName(group)] == int(row.bonuses[group]), kind + " approved bonus " + group)
		for property: String in ["speed", "sight", "range", "cooldown", "attack_windup_seconds", "radius", "supply", "damage_channel", "combat_class", "role", "projectile", "independent_weapons", "splash_radius"]:
			check(advanced.get(property) == base.get(property), kind + " retains " + property)
		check(advanced.validation_errors().is_empty(), kind + " valid classification")
		check(not BalanceCatalog.UNITS.has(kind + "_advanced"), kind + " excluded from recruitment")
		check(variant.definition() == advanced and advanced != base, kind + " independent cached resource")
		var old_hits := ceili(base.hp / DamageResolver.resolve(DamageResolver.snapshot(base, 0, 0, 0), base))
		var new_hits := ceili(advanced.hp / DamageResolver.resolve(DamageResolver.snapshot(advanced, 0, 0, 0), advanced))
		check(abs(new_hits - old_hits) <= old_hits * .1, kind + " mirror matchup stays within approved ten-percent tolerance")
	var guard := UnitVariantCatalog.ADVANCED["shield_guard"].definition()
	var sword := UnitVariantCatalog.ADVANCED["swordsman"].definition()
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("archer"), 0, 1, 1), guard) == 3, "normal arrow deals three to advanced guard")
	check(DamageResolver.resolve(DamageResolver.snapshot(BalanceCatalog.unit("triple_cannon"), 0, 1, 1), guard) == 22, "infantry bonus still applies through guard armor")
	check(DamageResolver.resolve(DamageResolver.snapshot(sword, 0, 0, 0), BalanceCatalog.unit("knight")) == 15, "advanced sword deals fifteen to cavalry")
	var codex: Control = load("res://scenes/unit_codex.tscn").instantiate()
	root.add_child(codex)
	for kind: String in families:
		codex.select_entry(0, kind)
		var count: int = codex._entries.size()
		codex.get_node("%AdvancedGrade").pressed.emit()
		check(codex.advanced and codex.get_node("%EntryTitle").text == UnitVariantCatalog.ADVANCED[kind].display_name, kind + " codex grade title")
		check(codex._entries.size() == count and codex.selected_id == kind, kind + " single codex entry")
		check(codex._model.presentation_key() == kind + "_advanced", kind + " codex model matches grade")
		codex.select_advanced(false)
		check(codex._model.grade.is_empty(), kind + " normal toggle restored")
	codex.queue_free()
	await process_frame
	change_scene_to_file("res://scenes/sandbox.tscn")
	await scene_changed
	game = current_scene
	while not game._match_ready: await process_frame
	game.camera_rig.set_process(false)
	for kind: String in families:
		game.set_paint_kind(kind)
		game.hud.get_node("%AdvancedGrade").pressed.emit()
		check(game.paint_advanced and game._ghost.presentation_key() == kind + "_advanced", kind + " correct placement preview")
		game.paint_count = 1
		check(game.place_units(Vector3.ZERO) == 1, kind + " native placement succeeds")
		game.set_placing(false)
		var unit: BattleUnit = game.owned_entities(0, "units")[0]
		var normal: BattleUnit = game.spawn_unit(kind, 0, Vector3(3, 0, 0))
		check(unit.max_hp == UnitVariantCatalog.ADVANCED[kind].hp and unit._model.batch_parts.size() == (11 if kind == "archer" else 7), kind + " authored stats and original rigid-part count")
		check(unit.render_batches == game.get_node("VariantRenderBatches"), kind + " variant batches")
		game.select_entities([normal, unit])
		game.hud.refresh()
		var composition: SelectionComposition = game.hud.get_node("UnitPanel").composition
		check(composition.groups.size() == 2 and composition.total_count == 2, kind + " mixed grades separate in composition")
		check(game.hud.portraits.has(kind + "_advanced"), kind + " portrait registered")
		unit.issue_move(Vector3(0, 0, 4))
		unit.queue_move(Vector3(0, 0, 8))
		game.set_running(true)
		await ticks(40)
		game.set_running(false)
		var paused_at := unit.position
		await ticks(8)
		check(unit.position.is_equal_approx(paused_at), kind + " pause preserves position")
		game.set_running(true)
		await ticks(170)
		check(unit.position.distance_to(Vector3(0, 0, 8)) < .8 and unit.waypoint_queue.is_empty(), kind + " queued navigation and resume")
		unit.hold()
		check(unit.order == BattleUnit.Order.HOLD, kind + " hold order")
		unit.stop()
		check(unit.order == BattleUnit.Order.IDLE, kind + " stop order")
		var instance := unit.get_instance_id()
		unit.receive_damage(1000)
		check(not unit.alive and not unit._model.attack.is_playing(), kind + " death cancels animation")
		await ticks(285)
		check(not is_instance_id_valid(instance), kind + " corpse released after fall/fade")
		await clear()
		game.set_paint_advanced(false)
	for kind: String in families:
		for cavalry: String in (["knight", "light_cavalry", "war_elephant"] if kind in ["spearman", "archer"] else ["knight", "light_cavalry"]):
			await contact(kind, cavalry)
	if "archer" in families: await arrow_commands()
	# A small active mixed army checks real combat using both current grades.
	await clear()
	for index: int in 10:
		game.spawn_variant(families[index % families.size()], 0, Vector3((index - 4.5) * 1.5, 0, -3))
		game.spawn_unit("knight" if index % 2 == 0 else "swordsman", 1, Vector3((index - 4.5) * 1.5, 0, 3))
	game.set_running(true)
	await ticks(210)
	for owner: int in [0, 1]:
		check(game.owned_entities(owner, "units").any(func(unit: BattleUnit): return unit.hp < unit.max_hp), "mixed army delivers actual damage to team " + str(owner))
	await clear()
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	FileAccess.open(output + "integration-results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "contacts": contacts, "families": families}, "\t"))
	print("ADVANCED_INFANTRY ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func probe(kind: String, owner: int, at: Vector3, advanced: bool) -> Probe:
	var unit: BattleUnit = UNIT.instantiate()
	unit.set_script(Probe)
	unit.unit_type = kind
	if advanced:
		var variant: UnitVariantDefinition = UnitVariantCatalog.ADVANCED[kind]
		unit.definition_override = variant.definition()
		unit.model_scene_override = variant.batched_model
		unit.render_batches = game.get_node("VariantRenderBatches")
	else:
		unit.model_scene_override = load("res://assets/models/units/batched/" + kind + ".tscn")
		unit.render_batches = game.get_node("UnitRenderBatches")
	unit.prune_stationary_avoidance = game.stationary_avoidance_pruning_enabled
	game.attach_unit(unit, owner, at)
	# Survive the complete approach trace; real authored HP is checked separately.
	unit.max_hp = 10000
	unit.hp = 10000
	return unit

func contact(kind: String, cavalry: String) -> void:
	await clear()
	var infantry := probe(kind, 0, Vector3(0, 0, 6), true)
	var opponent := probe(cavalry, 1, Vector3(0, 0, -6), false)
	await ticks(3)
	infantry.issue_attack(opponent)
	opponent.issue_attack(infantry)
	game.set_running(true)
	var start := -1.0
	var hit := -1.0
	var first_damage := 0.0
	var launches: Array[Dictionary] = []
	var on_launch := func(flight: ProjectileFlight):
		if flight._source == infantry:
			launches.append({"time": game.elapsed, "kind": flight._kind, "origin_error": flight._start.distance_to(infantry.get_projectile_origin())})
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	pool.launched.connect(on_launch)
	for tick: int in 300:
		await ticks(1)
		if start < 0 and infantry.attack_starts > 0: start = game.elapsed
		if hit < 0 and opponent.hp < opponent.max_hp:
			hit = game.elapsed
			first_damage = opponent.max_hp - opponent.hp
	game.set_running(false)
	pool.launched.disconnect(on_launch)
	var label := kind + " vs " + cavalry
	check(infantry.attack_starts >= 2 and opponent.attack_starts >= 2, label + " sustained actual combat")
	check(infantry.backwards_intents == 0 and opponent.backwards_intents == 0, label + " no backwards movement intent")
	check(infantry.retreat_distance < .05 and opponent.retreat_distance < .05, label + " no visible reverse step")
	check(infantry.turned_away_near_contact == 0 and opponent.turned_away_near_contact == 0, label + " no turn away near contact")
	var definition := UnitVariantCatalog.ADVANCED[kind].definition()
	var release := hit
	if kind == "archer":
		check(launches.size() >= 2, label + " sustained real arrows")
		if not launches.is_empty():
			release = launches[0].time
			check(launches[0].kind == "arrow" and launches[0].origin_error < .001, label + " arrow starts at actual animated socket")
			check(hit > release, label + " damage waits for projectile flight")
	check(start >= 0 and release > start and absf(release - start - definition.attack_windup_seconds) < .06, label + " contact or release matches authored windup")
	check(first_damage == DamageResolver.resolve(DamageResolver.snapshot(definition, 0, 0, 0), BalanceCatalog.unit(cavalry)), label + " real hit uses advanced damage/counter bonus")
	contacts.append({"kind": kind, "opponent": cavalry, "backwards_intents": infantry.backwards_intents, "retreat_distance": infantry.retreat_distance, "cavalry_retreat": opponent.retreat_distance, "windup_seconds": release - start, "first_damage": first_damage, "arrows": launches.size()})

func arrow_commands() -> void:
	await clear()
	var archer := probe("archer", 0, Vector3.ZERO, true)
	var target := probe("shield_guard", 1, Vector3(0, 0, -7), false)
	target.set_physics_process(false)
	var launches: Array[float] = []
	var pool: BattleProjectilePool = game.get_node("ProjectilePool")
	var record := func(flight: ProjectileFlight):
		if flight._source == archer: launches.append(game.elapsed)
	pool.launched.connect(record)
	archer.issue_attack(target)
	game.set_running(true)
	while archer.attack_starts == 0: await ticks(1)
	archer.stop()
	archer.set_physics_process(false)
	await ticks(30)
	check(launches.is_empty() and target.hp == target.max_hp, "stopping before arrow release cancels flight and damage")
	archer.set_physics_process(true)
	archer.issue_attack(target)
	for step: int in 200:
		# Reissuing the same target cannot bypass the unit's shared cooldown.
		archer.issue_attack(target)
		await ticks(1)
	check(launches.size() >= 3, "repeated commands still complete bow attacks")
	var minimum_interval := INF
	for index: int in range(1, launches.size()): minimum_interval = minf(minimum_interval, launches[index] - launches[index - 1])
	check(minimum_interval >= 1.5 - .035, "repeated commands cannot accelerate the 1.5-second bow cooldown")
	archer.stop()
	archer.set_physics_process(false)
	await ticks(60)
	check(target.max_hp - target.hp == launches.size() * 6, "every arrow hits once for thirteen minus seven ranged armor")
	pool.launched.disconnect(record)
	for cavalry: String in ["knight", "light_cavalry"]:
		var a := BalanceCatalog.unit(cavalry)
		var d := UnitVariantCatalog.ADVANCED["archer"].definition()
		check(d.is_ranged_infantry() and DamageResolver.resolve(DamageResolver.snapshot(a, 0, 1, 1), d) == a.damage + a.bonuses[&"ranged_infantry"], cavalry + " retains ranged-infantry counter against advanced archer")
