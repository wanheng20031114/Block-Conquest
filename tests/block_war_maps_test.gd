extends SceneTree
## Each authored map is loaded through the real match and every route is checked.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	for definition: Resource in CATALOG.MAPS:
		var arguments := OS.get_cmdline_user_args()
		if not arguments.is_empty() and definition.map_id != arguments[0]:
			continue
		var started := Time.get_ticks_msec()
		session.block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		check(game.map.definition == definition, "%s loads the selected native map" % definition.map_id)
		check(game.faction_count == definition.team_size * 2, "size determines the requested team composition")
		check(game.buildings.size() == definition.building_positions.size(), "scene and tactical preview have the same building count")
		var starters := PackedInt32Array()
		starters.resize(game.faction_count)
		for i: int in game.buildings.size():
			var building: WarBuilding = game.buildings[i]
			check(building.building_id == i and building.global_position == definition.building_positions[i], "preview positions match authored building IDs")
			check(building.kind == definition.building_kinds[i] and building.faction == definition.building_factions[i], "preview ownership and building roles match the scene")
			check(game.map.is_walkable(building.global_position), "every building is placed on traversable land")
			if building.faction >= 0:
				starters[building.faction] += 1
				check(building.kind == 0 and building.population == 60.0, "all players start with the same residence and garrison")
		for count: int in starters:
			check(count == 1, "each participating commander has exactly one starting home")
		check(game.team_total_for(0) == game.team_total_for(1), "both alliances have equal initial strength")
		game.camera_rig.focus_at(Vector3(1000, 0, -1000), true)
		check(game.camera_rig.position == Vector3(definition.half_size.x - 6, 0, -definition.half_size.y + 5), "camera bounds follow the map's true size")
		check(game._valid_ground_skill_target(Vector3(definition.half_size.x - 1, 0, 0)), "skills reach the edges of every map size")
		check(not game._valid_ground_skill_target(Vector3(definition.half_size.x + 1, 0, 0)), "skills cannot target outside the battlefield")
		var missing := 0
		var off_ground := 0
		var routes := 0
		var first_failure := ""
		for i: int in game.buildings.size():
			for j: int in range(i + 1, game.buildings.size()):
				var source: WarBuilding = game.buildings[i]
				var target: WarBuilding = game.buildings[j]
				var route: PackedVector3Array = game.map.get_building_route(source, target)
				routes += 1
				if route.size() < 2:
					missing += 1
					if first_failure.is_empty():
						first_failure = "missing %d -> %d" % [i, j]
					continue
				var reverse: PackedVector3Array = game.map.get_building_route(target, source)
				reverse.reverse()
				check(reverse == route, "both route directions share the same safe corridor")
				game.marches.clear()
				game.marches.send(i, j, 0, 6, route)
				var length: float = game.marches._units[0].order.length
				check(absf(game.map.get_building_distance(source, target) - length) < 0.02, "AI distance matches the actual march curve")
				for step: int in range(ceili(length) + 1):
					for unit: WarMarches.MarchUnit in game.marches._units:
						unit.distance = minf(length - 0.001, step)
						game.marches._update_pose(unit)
						var basis := Basis(Vector3.UP, atan2(-unit.heading.x, -unit.heading.z)).scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
						for corner: Vector3 in [Vector3(-0.842, 0, -0.55), Vector3(-0.842, 0, 0.383), Vector3(0.695, 0, -0.55), Vector3(0.695, 0, 0.383)]:
							if not game.map.is_walkable(unit.position + basis * corner):
								off_ground += 1
								if first_failure.is_empty():
									first_failure = "%d -> %d at %s" % [i, j, unit.position]
		game.marches.clear()
		check(missing == 0, "%s: every pair of buildings has a route" % definition.map_id)
		check(off_ground == 0, "%s: six full soldier footprints stay on land or bridges" % definition.map_id)
		game.ai_enabled = true
		game.ai_clock = 0.0
		game.simulate(0.001)
		for building: WarBuilding in game.buildings:
			if building.faction > 0:
				check(building.is_constructing and building.population == 50.0, "every computer independently develops its own starting home")
		print("WAR_MAP ", definition.map_id, " buildings=", game.buildings.size(), " routes=", routes, " missing=", missing, " off_ground=", off_ground, " ms=", Time.get_ticks_msec() - started, " first=", first_failure)
		await game.prepare_shutdown()
	session.block_war_map_id = "rift"
	print("BLOCK_WAR_MAPS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
