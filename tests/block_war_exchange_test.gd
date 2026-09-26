extends SceneTree
## Additive troop exchange, live construction/ownership bonuses and corner chevrons.

var game: Node3D
var source: WarBuilding
var target: WarBuilding
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s = %s" % [label, actual, expected])

func forges(count: int) -> void:
	for index: int in 5:
		var forge: WarBuilding = game.by_id[8 + index]
		forge.kind = 2
		forge.level = 1
		forge.faction = 0 if index < count else -1

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.overlay.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.faction = -1
		building.population = 100.0
	source = game.by_id[0]
	source.faction = 0
	target = game.by_id[6]
	target.faction = 1
	game.drag_source = source
	game.hovered = target
	# Golden coefficients for no defense and each tower level, with 0–5 forges.
	var coefficients := [
		[1.0, 1.1, 1.2, 1.3, 1.4, 1.5],
		[0.95, 1.05, 1.15, 1.25, 1.35, 1.45],
		[0.9, 1.0, 1.1, 1.2, 1.3, 1.4],
		[0.85, 0.95, 1.05, 1.15, 1.25, 1.35],
	]
	for shielded: bool in [false, true]:
		game.shields.clear()
		if shielded:
			game.shields[target.building_id] = 10.0
		for tier: int in 4:
			target.kind = 0 if tier == 0 else 1
			target.level = maxi(1, tier)
			for count: int in 6:
				forges(count)
				var coefficient: float = coefficients[tier][count] - (0.25 if shielded else 0.0)
				var label := "tower=%d forges=%d shield=%s" % [tier, count, shielded]
				near(game.combat_multiplier(0, target), coefficient, label + " additive coefficient")
				target.population = 100.0
				game._on_unit_arrived(target.building_id, 0, 20.0)
				near(target.population, 100.0 - 20.0 * coefficient, label + " twenty-person attack")
				target.population = 100.0
				for soldier: int in 20:
					game._on_unit_arrived(target.building_id, 0, 1.0)
				near(target.population, 100.0 - 20.0 * coefficient, label + " individual arrivals retain fractional casualties")
	game.shields.clear()
	forges(1)
	target.kind = 1
	target.level = 1
	target.population = 100.0
	game._on_unit_arrived(target.building_id, 0, 20.0)
	near(target.population, 79.0, "user example: twenty troops remove twenty-one defenders")
	target.population = 21.0
	game._on_unit_arrived(target.building_id, 0, 20.0)
	check(target.population == 0.0 and target.faction == 1, "an exact exchange needs a surviving attacker to capture")
	target.population = 10.5
	game._on_unit_arrived(target.building_id, 0, 20.0)
	near(target.population, 10.0, "capture keeps ten actual survivors rather than inflated attack strength")
	check(target.faction == 0 and target.level == 1, "capture retains the level-one floor")
	target.faction = 1
	# Defense belongs to the structure, not to its owner's forges or house level.
	game.by_id[8].faction = 1
	near(game.combat_multiplier(0, target), 0.95, "defender's forge does not grant defense")
	for owner: int in [-1, 1]:
		target.faction = owner
		for tier: int in [1, 2, 3, 4]:
			target.kind = 0
			target.level = tier
			near(game.defense_bonus(target), 0.0, "residences have no level-based defense")
		target.kind = 1
		target.level = 3
		near(game.combat_multiplier(0, target), 0.85, "neutral and owned towers share intrinsic defense")
	# No upgrade entry, no charge through the gameplay API, compact conversion UI.
	var forge: WarBuilding = game.by_id[8]
	forge.faction = 0
	forge.population = 100.0
	game.select_building(forge)
	game.upgrade_selected()
	check(forge.max_level == 1 and forge.upgrade_cost == 0 and not forge.is_constructing and forge.population == 100.0, "forge upgrade is rejected without spending troops")
	check(not game.hud.get_node("%Upgrade").visible and game.hud.get_node("%Selection").size.x == 134.0, "forge hides upgrade and shrinks to two actions")
	game.convert_selected(0)
	near(game.attack_bonus(0), 0.1, "forge retains attack while being converted")
	forge.advance_construction(9.999)
	near(game.attack_bonus(0), 0.1, "forge bonus remains until the exact completion")
	forge.advance_construction(0.001)
	near(game.attack_bonus(0), 0.0, "completed residence immediately removes the old forge bonus")
	game.convert_selected(2)
	near(game.attack_bonus(0), 0.0, "unfinished forge grants no attack")
	forge.advance_construction(10.0)
	near(game.attack_bonus(0), 0.1, "completed forge grants ten percent attack")
	forge.population = 0.0
	game._on_unit_arrived(forge.building_id, 1, 1.0)
	near(game.attack_bonus(0), 0.0, "capture immediately removes former owner's forge bonus")
	near(game.attack_bonus(1), 0.1, "capture immediately transfers forge attack to its new owner")
	check(forge.level == 1, "captured forge stays at level one")
	target.kind = 1
	target.level = 1
	target.population = 100.0
	target.faction = 0
	game.select_building(target)
	game.upgrade_selected()
	near(game.defense_bonus(target), 0.05, "tower keeps old defense during upgrade")
	target.advance_construction(10.0)
	near(game.defense_bonus(target), 0.1, "tower defense increases on completion")
	target.population = 0.0
	game._on_unit_arrived(target.building_id, 1, 1.0)
	near(game.defense_bonus(target), 0.05, "capture downgrade immediately reduces tower defense")
	# Corner badges use the same actual target and stay separate from count layout.
	game.drag_source = source
	game.hovered = target
	source.population = 64.0
	game.percentage = 75
	target.kind = 0
	target.level = 1
	game.overlay._update_dispatch_hint()
	var original_rect: Rect2 = game.overlay._hint_rect
	var original_text_at: Vector2 = game.overlay.hint_label.position
	for count: int in 6:
		forges(count)
		var expected: int = [0, 1, 1, 2, 2, 3][count]
		check(game.overlay.dispatch_advantage() == expected, "100–150 percent preview uses zero/one/two/three blue chevrons")
		game.overlay._update_dispatch_hint()
		check(game.overlay.hint_label.text == "48" and game.overlay._hint_rect == original_rect and game.overlay.hint_label.position == original_text_at, "changing bonuses leaves the count and cloud geometry stable")
	forges(0)
	target.kind = 1
	for tier: int in [1, 2, 3]:
		target.level = tier
		check(game.overlay.dispatch_advantage() == -1, "unassisted attack on any tower shows a red downward chevron")
	forges(1)
	target.level = 2
	check(game.overlay.dispatch_advantage() == 0, "equal ten-percent attack and defense cancel with no symbol")
	game.shields[target.building_id] = 10.0
	check(game.overlay.dispatch_advantage() == -2, "net twenty-five-percent disadvantage stacks two downward chevrons")
	for owner: int in [0, 2]:
		target.faction = owner
		check(game.overlay.dispatch_advantage() == 0, "own and allied reinforcements have no combat symbol")
		var before := target.population
		game._on_unit_arrived(target.building_id, 0, 20.0)
		near(target.population, before + 20.0, "reinforcement transfers actual troops despite attack and defense bonuses")
	game.hovered = null
	check(game.overlay.dispatch_advantage() == 0, "no target has no speculative combat badge")
	game.drag_source = null
	await game.prepare_shutdown()
	print("BLOCK_WAR_EXCHANGE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
