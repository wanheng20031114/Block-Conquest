extends SceneTree
## Environment / skill exchange groups, live ownership bonuses and corner chevrons.

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
		[1.0, 1.3, 1.5, 1.7, 1.8, 1.8],
		[0.769230769, 1.0, 1.153846154, 1.307692308, 1.384615385, 1.384615385],
		[0.666666667, 0.866666667, 1.0, 1.133333333, 1.2, 1.2],
		[0.625, 0.8125, 0.9375, 1.0625, 1.125, 1.125],
		[0.588235294, 0.764705882, 0.882352941, 1.0, 1.058823529, 1.058823529],
	]
	for shielded: bool in [false, true]:
		game.shields.clear()
		if shielded:
			game.shields[target.building_id] = 10.0
		for tier: int in 5:
			target.kind = 0 if tier == 0 else 1
			target.level = maxi(1, tier)
			for count: int in 6:
				# Each golden coefficient describes a fresh zero-morale exchange.
				# Battle-earned stars are exercised by block_war_morale_test instead.
				game.morale.configure(game.faction_count)
				forges(count)
				var coefficient: float = coefficients[tier][count] / (1.25 if shielded else 1.0)
				var label := "tower=%d forges=%d shield=%s" % [tier, count, shielded]
				near(game.combat_multiplier(0, target), coefficient, label + " environment times skill coefficient")
				target.population = 100.0
				game._on_unit_arrived(target.building_id, 0, 20.0)
				near(target.population, 100.0 - 20.0 * coefficient, label + " twenty-person attack")
				target.population = 100.0
				for soldier: int in 20:
					game._on_unit_arrived(target.building_id, 0, 1.0)
				near(target.population, 100.0 - 20.0 * coefficient, label + " individual arrivals retain fractional casualties")
	game.shields.clear()
	game.morale.configure(game.faction_count)
	forges(1)
	target.kind = 1
	target.level = 1
	target.population = 100.0
	game._on_unit_arrived(target.building_id, 0, 20.0)
	near(target.population, 80.0, "one forge against a first-tier tower: equal thirty-percent bonuses exchange one for one")
	target.population = 20.0
	game._on_unit_arrived(target.building_id, 0, 20.0)
	check(target.population == 0.0 and target.faction == 1, "an exact exchange needs a surviving attacker to capture")
	# Reset battle-earned morale so this remains the same zero-star exchange.
	game.morale.configure(game.faction_count)
	target.population = 10.0
	game._on_unit_arrived(target.building_id, 0, 20.0)
	near(target.population, 10.0, "capture keeps ten actual survivors rather than inflated attack strength")
	check(target.faction == 0 and target.level == 1, "capture retains the level-one floor")
	target.faction = 1
	# Intrinsic building defense adds to the owner's forge defense.
	game.morale.configure(game.faction_count)
	game.by_id[8].faction = 1
	near(game.combat_multiplier(0, target), 1.0 / 1.45, "defender's forge adds fifteen percent to tower defense")
	for owner: int in [-1, 1]:
		target.faction = owner
		for tier: int in [1, 2, 3, 4]:
			target.kind = 0
			target.level = tier
			near(game.defense_bonus(target), (tier - 1) * 0.1 + (0.0 if owner < 0 else 0.15), "neutral and owned residences add their level defense to the owner's forge bonus")
		target.kind = 1
		target.level = 3
		near(game.combat_multiplier(0, target), 1.0 / (1.6 if owner < 0 else 1.75), "neutral and owned towers share intrinsic defense while owned forges add defense")
	# No upgrade entry, no charge through the gameplay API, compact conversion UI.
	var forge: WarBuilding = game.by_id[8]
	forge.faction = 0
	forge.population = 100.0
	game.select_building(forge)
	game.upgrade_selected()
	check(forge.max_level == 1 and forge.upgrade_cost == 0 and not forge.is_constructing and forge.population == 100.0, "forge upgrade is rejected without spending troops")
	check(not game.hud.get_node("%Upgrade").visible and game.hud.get_node("%Selection").size.x == 200.0 and game.hud.get_node("%ConvertEnergy").visible, "forge hides upgrade and provides three legal conversion actions")
	game.convert_selected(0)
	near(game.attack_bonus(0), 0.3, "forge retains attack while being converted")
	forge.advance_construction(9.999)
	near(game.attack_bonus(0), 0.3, "forge bonus remains until the exact completion")
	forge.advance_construction(0.001)
	near(game.attack_bonus(0), 0.0, "completed residence immediately removes the old forge bonus")
	game.convert_selected(2)
	near(game.attack_bonus(0), 0.0, "unfinished forge grants no attack")
	forge.advance_construction(10.0)
	near(game.attack_bonus(0), 0.3, "completed first forge grants thirty percent attack")
	forge.population = 0.0
	game._on_unit_arrived(forge.building_id, 1, 1.0)
	near(game.attack_bonus(0), 0.0, "capture immediately removes former owner's forge bonus")
	near(game.attack_bonus(1), 0.3, "capture immediately transfers forge attack to its new owner")
	check(forge.level == 1, "captured forge stays at level one")
	# Isolate intrinsic tower defense from the forge ownership change above.
	forge.faction = -1
	target.kind = 1
	target.level = 1
	target.population = 100.0
	target.faction = 0
	game.select_building(target)
	game.upgrade_selected()
	near(game.defense_bonus(target), 0.30, "tower keeps old defense during upgrade")
	target.advance_construction(10.0)
	near(game.defense_bonus(target), 0.50, "tower defense increases on completion")
	target.population = 0.0
	game._on_unit_arrived(target.building_id, 1, 1.0)
	near(game.defense_bonus(target), 0.30, "capture downgrade immediately reduces tower defense")
	# Corner badges use the same actual target and stay separate from count layout.
	game.morale.configure(game.faction_count)
	game.drag_source = source
	game.hovered = target
	source.population = 64.0
	game.percentage = 75
	game.drag_sources.clear()
	game.drag_sources.append(source)
	game.order_previews.clear()
	game.order_previews.append({"source": source, "count": 48, "route": PackedVector3Array()})
	target.kind = 0
	target.level = 1
	game.overlay._update_dispatch_hint()
	var original_rect: Rect2 = game.overlay._hint_rect
	var original_text_at: Vector2 = game.overlay.hint_label.position
	for count: int in 6:
		forges(count)
		var expected: int = [0, 2, 3, 4, 4, 4][count]
		check(game.overlay.dispatch_advantage() == expected, "100–180 percent preview uses capped forge totals and twenty-point blue chevrons")
		game.overlay._update_dispatch_hint()
		check(game.overlay.hint_label.text == "48" and game.overlay._hint_rect == original_rect and game.overlay.hint_label.position == original_text_at, "changing bonuses leaves the count and cloud geometry stable")
	forges(0)
	target.kind = 1
	for tier: int in [1, 2, 3, 4]:
		target.level = tier
		check(game.overlay.dispatch_advantage() == [-2, -2, -2, -3][tier - 1], "unassisted tower attacks show the corresponding red disadvantage")
	forges(3)
	target.level = 4
	check(game.overlay.dispatch_advantage() == 0, "equal seventy-percent environment attack and defense cancel with no symbol")
	game.shields[target.building_id] = 10.0
	check(game.overlay.dispatch_advantage() == -1, "balanced environment divided by the shield gives twenty-percent disadvantage")
	for owner: int in [0, 2]:
		target.faction = owner
		check(game.overlay.dispatch_advantage() == 0, "own and allied reinforcements have no combat symbol")
		var before := target.population
		game._on_unit_arrived(target.building_id, 0, 20.0)
		near(target.population, before + 20.0, "reinforcement transfers actual troops despite attack and defense bonuses")
	game.hovered = null
	check(game.overlay.dispatch_advantage() == 0, "no target has no speculative combat badge")
	game.drag_source = null
	_residence_defense()
	await game.prepare_shutdown()
	print("BLOCK_WAR_EXCHANGE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _residence_defense() -> void:
	var ai: RefCounted = game.AI_STRATEGY.new(0)
	forges(0)
	game.shields.clear()
	target.kind = 0
	for owner: int in [-1, 1]:
		for tier: int in [1, 2, 3, 4]:
			game.morale.configure(game.faction_count)
			target.faction = owner
			target.level = tier
			target.population = 100.0
			var defense := 1.0 + 0.1 * (tier - 1)
			var label := "residence level=%d owner=%d" % [tier, owner]
			near(game.combat_multiplier(0, target), 1.0 / defense, label + ": intrinsic defense divides actual attack damage")
			near(ai._assault_losses(game, target, 10.0), 10.0 * defense, label + ": AI budgets casualties with the same intrinsic defense")
			game._on_unit_arrived(target.building_id, 0, 10.0)
			near(target.population, 100.0 - 10.0 / defense, label + ": arrivals preserve fractional defensive casualties")
			game.morale.configure(game.faction_count)
			target.population = 100.0
			_fire_on_target()
			near(target.population, 100.0 - 25.0 / defense, label + ": fire uses the residence's intrinsic defense")
	# House, forge and morale defense add in the environment denominator;
	# the shield remains a separate skill multiplier.
	target.faction = 1
	target.level = 4
	target.population = 100.0
	game.by_id[8].faction = 1
	game.morale.configure(game.faction_count)
	game.morale.adjust(0, 1000.0)
	game.morale.adjust(1, 2000.0)
	game.shields[target.building_id] = 10.0
	var coefficient := 1.1 / 2.05 / 1.25
	near(game.combat_multiplier(0, target), coefficient, "house +30%, forge +15% and morale +60% add before shield defense")
	game._on_unit_arrived(target.building_id, 0, 10.0)
	near(target.population, 100.0 - 10.0 * coefficient, "mixed residence defense is applied to real arrivals")
	game.morale.configure(game.faction_count)
	game.morale.adjust(0, 1000.0)
	game.morale.adjust(1, 2000.0)
	target.population = 100.0
	_fire_on_target()
	near(target.population, 100.0 - 25.0 * coefficient, "mixed residence defense is also applied to real fire damage")

func _fire_on_target() -> void:
	var fire: RefCounted = game.FIRE_STATE.new()
	fire.faction = 0
	fire.global_position = target.global_position
	game.fire_states.append(fire)
	game._tick_fire_buildings()
	game.fire_states.clear()
