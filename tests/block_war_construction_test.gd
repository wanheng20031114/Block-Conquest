extends SceneTree
## Timed construction, simultaneous completions, capture and particle lifecycle.

var game: Node3D
var home: WarBuilding
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.0001, "%s: %s = %s" % [message, actual, expected])

func fixture(kind: int = 0, tier: int = 1, population: float = 200.0) -> void:
	game.marches.clear()
	game._cancel_recruitment()
	game.shields.clear()
	game.energy = 100.0
	game.cooldowns.fill(0.0)
	for building: WarBuilding in game.buildings:
		building.cancel_construction()
		building.kind = 0
		building.level = 1
		building.faction = -1
		building.population = 100.0
		building.refresh_visual()
	game.by_id[1].faction = 1
	game.by_id[3].faction = 0
	home.kind = kind
	home.level = tier
	home.faction = 0
	home.population = population
	home.refresh_visual()
	game.select_building(home)

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	home = game.by_id[0]
	var upgrade: Button = game.hud.get_node("%Upgrade")
	var dust: GPUParticles3D = home.get_node("Construction/Dust")
	var chips: GPUParticles3D = home.get_node("Construction/Chips")
	var completion: GPUParticles3D = home.get_node("Construction/Complete")
	var original_nodes := home.find_children("*", "", true, false).size()
	for kind: int in [0, 1, 2]:
		var max_level: int = [4, 3, 1][kind]
		for tier: int in range(1, max_level):
			fixture(kind, tier)
			var path: String = "Visual/%s/Stone" % ["House", "Tower", "Smithy"][kind]
			var old_mesh: Mesh = home.get_node(path).mesh
			var cost := home.upgrade_cost
			var defense: float = game.defense_bonus(home)
			var attack: float = game.attack_bonus(0)
			game.upgrade_selected()
			check(home.is_constructing and home.level == tier and home.construction_remaining == 10.0, "each paid tier starts ten seconds without an immediate level")
			near(home.population, 200.0 - cost, "construction deducts the exact cost once")
			check(home.get_node(path).mesh == old_mesh, "unfinished construction retains its current model")
			near(game.defense_bonus(home), defense, "unfinished construction retains current defense")
			near(game.attack_bonus(0), attack, "construction cannot grant an early global bonus")
			check(dust.emitting and chips.emitting and dust.is_visible_in_tree(), "construction begins visible dust and debris")
			check(upgrade.disabled and upgrade.get_node("Cost/Amount").text == "10s", "paid upgrade shows ten seconds and rejects duplicate clicks")
			for repeat: int in 3:
				game.upgrade_selected()
			game.convert_selected((kind + 1) % 3)
			check(home.kind == kind and home.population == 200.0 - cost and home.construction_remaining == 10.0, "duplicate upgrade and conflicting conversion cannot spend or reset work")
			for button: String in ["%ConvertHouse", "%ConvertTower", "%ConvertForge"]:
				check(game.hud.get_node(button).disabled, "conversion actions are disabled during construction")
			game.simulate(9.999)
			game.update_hud()
			check(home.level == tier and home.is_constructing and home.get_node(path).mesh == old_mesh, "9.999 seconds never changes the level or model")
			check(upgrade.get_node("Cost/Amount").text == "1s", "last fraction of a second remains visible as one second")
			game.simulate(0.001)
			check(home.level == tier + 1 and not home.is_constructing, "level changes exactly at ten seconds")
			check(home.get_node(path).mesh != old_mesh and home.get_node("Visual/Flag").get_instance_shader_parameter("building_level") == tier + 1, "completion changes geometry and flag together")
			check(not dust.emitting and not chips.emitting and completion.emitting, "completion stops the work emitters and releases one final puff")
			check(home.find_children("*", "", true, false).size() == original_nodes, "construction reuses authored scene nodes")
	# Start two builds four seconds apart, then cross both completion boundaries.
	for small_steps: bool in [false, true]:
		fixture(0, 1, 10.0)
		game.upgrade_selected()
		game.simulate(4.0)
		var second: WarBuilding = game.by_id[3]
		second.level = 2
		second.population = 20.0
		second.refresh_visual()
		game.select_building(second)
		game.upgrade_selected()
		if small_steps:
			for frame: int in 120:
				game.simulate(0.1)
		else:
			game.simulate(12.0)
		check(home.level == 2 and second.level == 3, "unselected and selected buildings finish independent construction")
		near(home.population, 17.5, "first home integrates ten old-rate seconds and six new-rate seconds")
		near(second.population, 15.3, "second home integrates its own later completion boundary")
	# Q spans the completion boundary; both large and small steps have the same sum.
	for small_steps: bool in [false, true]:
		fixture(0, 1, 10.0)
		game.upgrade_selected()
		game.simulate(8.0)
		check(game.cast_skill(0, home), "recruitment can start during construction")
		if small_steps:
			for frame: int in 80:
				game.simulate(0.1)
		else:
			game.simulate(8.0)
		near(home.population, 47.5, "recruitment and natural growth use the correct rates across completion")
	fixture(0, 1, 40.0)
	game.upgrade_selected()
	game.simulate(12.0)
	near(home.population, 32.5, "old production cap stays stopped until completion opens room")
	fixture(0, 2, 20.0)
	game.upgrade_selected()
	game.simulate(5.0)
	game._on_unit_arrived(home.building_id, 0, 100.0)
	game.simulate(5.0)
	near(home.population, 106.25, "friendly reinforcements remain uncapped throughout construction")
	check(home.level == 3, "reinforcement does not interrupt work")
	for old_kind: int in [1, 2]:
		fixture(old_kind, 1, 20.0)
		for building: WarBuilding in game.buildings:
			if building != home:
				building.kind = 2
				building.population = 0.0
		game.convert_selected(0)
		game.simulate(9.9)
		check(not game.finished and home.kind == old_kind and home.population == 0.0, "a pending residence prevents premature draw when both sides exhaust their garrisons")
		game.simulate(0.2)
		check(not game.finished and home.kind == 0, "last viable residence can complete its conversion")
		near(home.population, 0.1, "the completed residence restarts natural growth after the ten-second boundary")
	# A lost construction never finishes for a new owner, including a level-one floor.
	for kind: int in [0, 1, 2]:
		for tier: int in range(1, [4, 3, 1][kind] + 1):
			fixture(kind, tier)
			if tier < home.max_level:
				game.upgrade_selected()
				game.simulate(4.0)
			home.population = 0.0
			game._on_unit_arrived(home.building_id, 1, 100.0)
			var captured_level := maxi(1, tier - 1)
			check(home.faction == 1 and home.level == captured_level and not home.is_constructing, "capture immediately changes owner, loses one existing level and cancels construction")
			check(home.get_node("Visual/Flag").get_instance_shader_parameter("building_level") == captured_level, "capture updates the downgraded flag in the same frame")
			check(not dust.is_visible_in_tree() and not dust.emitting and not chips.emitting and not completion.emitting, "capture immediately clears every construction emitter")
			game.simulate(12.0)
			check(home.level == captured_level, "captured building never receives an abandoned upgrade")
			near(home.population, 100.0, "capture and abandoned work do not refund cost or discard surviving attackers")
	for old_kind: int in [0, 1, 2]:
		for new_kind: int in [0, 1, 2]:
			if old_kind == new_kind:
				continue
			var old_level := 1 if old_kind == 2 else 2
			fixture(old_kind, old_level, 19.99)
			game.convert_selected(new_kind)
			check(not home.is_constructing and home.population == 19.99, "conversion rejects a fractional twenty-person shortfall")
			home.population = 20.0
			var path: String = "Visual/%s/Stone" % ["House", "Tower", "Smithy"][old_kind]
			var previous_mesh: Mesh = home.get_node(path).mesh
			var old_rate := home.production_rate
			game.convert_selected(new_kind)
			check(home.kind == old_kind and home.level == old_level and home.population == 0.0 and home.conversion_target == new_kind, "each conversion pays twenty once and retains its original kind and level")
			check(home.get_node(path).mesh == previous_mesh and home.get_node("Construction/Dust").emitting, "conversion keeps the original model and begins construction smoke")
			var conversion: Button = game.hud.get_node(["%ConvertHouse", "%ConvertTower", "%ConvertForge"][new_kind])
			check(conversion.disabled and conversion.get_node("Cost/Amount").text == "10s", "conversion countdown belongs to the chosen destination icon")
			game.upgrade_selected()
			game.convert_selected(new_kind)
			check(home.construction_remaining == 10.0 and home.population == 0.0, "repeated conversion or upgrade cannot restart or double-charge work")
			game.simulate(9.9)
			check(home.kind == old_kind and home.level == old_level, "conversion keeps all original functions before ten seconds")
			near(home.population, old_rate * 9.9, "old house production continues during conversion")
			game.simulate(0.1)
			check(home.kind == new_kind and home.level == 1 and not home.is_constructing, "conversion changes kind and resets level exactly at ten seconds")
			near(home.population, old_rate * 10.0, "conversion completion never charges a second time")
		fixture(old_kind, 1 if old_kind == 2 else 2, 100.0)
		game.convert_selected((old_kind + 1) % 3)
		game.simulate(3.0)
		game.set_paused(true)
		game.simulate(20.0)
		check(home.kind == old_kind and home.construction_remaining == 7.0, "pause freezes conversion without changing function")
		game.set_paused(false)
		home.population = 0.0
		game._on_unit_arrived(home.building_id, 1, 100.0)
		game.simulate(12.0)
		check(home.kind == old_kind and home.level == 1 and home.conversion_target == -1, "capture interrupts conversion and downgrades the original building")
	# A former enemy can be recaptured and start an entirely fresh construction.
	fixture(0, 1, 0.0)
	home.faction = 1
	home.population = 0.0
	game._on_unit_arrived(home.building_id, 0, 200.0)
	game.select_building(home)
	game.upgrade_selected()
	check(home.level == 1 and home.construction_remaining == 10.0 and dust.is_visible_in_tree(), "recapture starts a fresh full timer and restores dust")
	game.simulate(3.0)
	game.set_paused(true)
	game.simulate(100.0)
	near(home.construction_remaining, 7.0, "pause cannot consume construction time")
	check(dust.speed_scale == 0.0 and chips.speed_scale == 0.0 and completion.speed_scale == 0.0, "pause freezes all native construction particles")
	game.set_paused(false)
	check(dust.speed_scale == 1.0 and chips.speed_scale == 1.0, "resume restores particle speed")
	game.simulate(7.0)
	check(home.level == 2 and not home.is_constructing, "resume completes only the remaining work")
	game.upgrade_selected()
	game._finish_match(0)
	game.simulate(20.0)
	check(home.level == 2 and home.construction_remaining == 10.0 and dust.speed_scale == 0.0, "match result freezes active construction and effects")
	await game.prepare_shutdown()
	print("BLOCK_WAR_CONSTRUCTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
