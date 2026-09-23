extends SceneTree
## Accelerated campaign, corner-case audits and all authored march routes.

var game: Node3D
var checks := 0
var failures: Array[String] = []
var audit_findings: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func _reset() -> void:
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	await physics_frame

func _run() -> void:
	await _reset()
	game.ai_enabled = true
	for step: int in 6000:
		if step % 40 == 0:
			_player_turn()
		game.simulate(0.05)
		if step % 1200 == 0:
			print("CAMPAIGN_PROGRESS time=", game.elapsed, " player=", game.total_for(0), " enemy=", game.total_for(1), " ownership=", _ownership())
		if game.finished:
			break
	print("CAMPAIGN_RESULT time=", game.elapsed, " finished=", game.finished, " player=", game.total_for(0), " enemy=", game.total_for(1), " ownership=", _ownership())
	_check(game.finished, "A player using legal expansion, reinforcement and skills finishes within 300 simulated seconds")
	for building: Node3D in game.buildings:
		_check(building.population >= 0.0 and is_finite(building.population), "Campaign keeps valid population at building %d" % building.building_id)
	await _reset()
	_audit_queue_ownership()
	await _reset()
	_audit_empty_conversions()
	await _reset()
	_audit_fractional_victory()
	await _reset()
	_audit_fractional_stalemate()
	await _reset()
	_audit_same_column_ai()
	await _reset()
	_audit_routes()
	print("BLOCK_WAR_CAMPAIGN checks=", checks, " failures=", failures.size(), " audit_findings=", audit_findings)
	quit(0 if failures.is_empty() else 1)

func _player_turn() -> void:
	var residence: Node3D
	for building: Node3D in game.buildings:
		if building.faction == 0 and building.kind == 0:
			if residence == null or building.population > residence.population:
				residence = building
	if residence != null and game.cooldowns[0] <= 0.0:
		game.cast_skill(0, residence)
	if game.marches.total_for(0) >= 24 and game.cooldowns[1] <= 0.0:
		game.cast_skill(1, null)
	var bombard: Node3D
	for building: Node3D in game.buildings:
		if building.faction == 1 and building.population > 20.0:
			if bombard == null or building.population > bombard.population:
				bombard = building
	if bombard != null and game.cooldowns[3] <= 0.0:
		game.cast_ground_skill(3, bombard.global_position)
	var best_source: Node3D
	var best_target: Node3D
	var best_score := -INF
	for source: Node3D in game.buildings:
		if source.faction != 0 or source.population < 15.0:
			continue
		for target: Node3D in game.buildings:
			if target.faction == 0:
				continue
			var incoming: int = game.marches.incoming_for(target.building_id, 0)
			var required: float = target.population * game.defense_multiplier(target) / game.attack_multiplier(0) + 5.0
			if incoming >= required or floorf(source.population * 0.75) + incoming < required:
				continue
			var route: PackedVector3Array = game.map.get_building_route(source, target)
			var distance := _route_length(route)
			var score: float = (34.0 if target.kind == 0 else 20.0) - distance * 0.6 - required * 0.2
			if target.faction == 1:
				score += 10.0
			if score > best_score:
				best_source = source
				best_target = target
				best_score = score
	if best_source != null:
		game.issue_order(best_source, best_target, 75)
		return
	# Consolidate toward the nearest hostile location regardless of compass direction.
	var front: Node3D
	var front_distance := INF
	for own: Node3D in game.buildings:
		if own.faction != 0:
			continue
		for hostile: Node3D in game.buildings:
			if hostile.faction == 1:
				var distance := own.position.distance_to(hostile.position)
				if distance < front_distance:
					front = own
					front_distance = distance
	if front != null and game.marches.incoming_for(front.building_id, 0) < 80:
		for source: Node3D in game.buildings:
			if source.faction == 0 and source != front and source.population >= 40.0:
				game.issue_order(source, front, 75)
				return

func _ownership() -> Array[int]:
	var result: Array[int] = []
	for building: Node3D in game.buildings:
		result.append(building.faction)
	return result

func _route_length(route: PackedVector3Array) -> float:
	var result := 0.0
	for index: int in range(1, route.size()):
		result += route[index - 1].distance_to(route[index])
	return result

func _audit_queue_ownership() -> void:
	var source: Node3D = game.by_id[0]
	var target: Node3D = game.by_id[2]
	source.population = 60.0
	game.issue_order(source, target, 100)
	source.kind = 2
	source.faction = 1
	source.population = 0.0
	game._check_victory()
	_check(not game.finished and game.marches.total_for(0) == 60, "Capturing a source preserves already-dispatched soldiers and delays defeat")
	for step: int in 600:
		game.simulate(0.05)
	_check(target.faction == 0 and game.marches.total_for(0) == 0, "The old owner's queued soldiers can capture a new home after losing their source")
	_check(not game.finished, "A successful queued rescue prevents premature defeat")

func _audit_empty_conversions() -> void:
	for building: Node3D in game.buildings:
		building.kind = 2
		building.population = 0.0
		building.faction = 0 if building.building_id == 0 else 1
	game.ai_enabled = true
	for step: int in 600:
		game.simulate(0.5)
	_check(game.finished and game.hud.get_node("%ResultTitle").text == "战局僵持", "Both exhausted armies with no productive residences end in an explicit draw")
	print("EMPTY_CONVERSION_AUDIT finished=", game.finished, " totals=", game.total_for(0), ",", game.total_for(1))

func _audit_fractional_victory() -> void:
	for building: Node3D in game.buildings:
		building.faction = -1
		building.kind = 1
		building.population = 0.0
	var last_enemy: Node3D = game.by_id[1]
	last_enemy.faction = 1
	last_enemy.population = 0.5
	# A final arriving soldier defeats the fractional guard and occupies the last
	# enemy tower with half a survivor; no residence or marching army remains.
	game._on_unit_arrived(last_enemy.building_id, 0, 1.0)
	_check(last_enemy.faction == 0 and is_equal_approx(last_enemy.population, 0.5), "The last enemy tower is captured by a fractional survivor")
	game._check_victory()
	_check(game.finished and game.hud.get_node("%ResultTitle").text == "胜利", "Eliminating the final enemy wins even when the surviving garrison rounds down to zero")
	_check(game.map._visual_paused and last_enemy._visual_paused and game._local_menu, "Fractional victory retains map, building and match pause")

func _audit_fractional_stalemate() -> void:
	for building: Node3D in game.buildings:
		building.faction = -1
		building.kind = 1
		building.population = 0.0
	for id: int in [0, 2, 1, 4]:
		game.by_id[id].faction = 0 if id in [0, 2] else 1
		game.by_id[id].population = 0.6
	_check(game.total_for(0) == 1 and game.total_for(1) == 1, "Separate fractional garrisons sum to a displayed soldier on both sides")
	_check(game.issue_order(game.by_id[0], game.by_id[1], 100) == 0 and game.issue_order(game.by_id[1], game.by_id[0], 100, 1) == 0, "Neither side can dispatch a whole soldier from a fractional garrison")
	game._check_victory()
	_check(game.finished and game.hud.get_node("%ResultTitle").text == "战局僵持", "Two 0.6 garrisons on each side without homes or marches end in a draw")

func _audit_same_column_ai() -> void:
	for building: Node3D in game.buildings:
		building.faction = 1 if building.building_id in [4, 5] else 0
		building.population = 200.0
		building.level = 1
	game.ai_enabled = true
	for step: int in 600:
		game.simulate(0.5)
	var stuck: bool = game.marches.total_for(1) == 0 and game.by_id[4].population == 200.0 and game.by_id[5].population == 200.0
	if stuck:
		audit_findings.append("AI garrisons 4 and 5 share x=29: 400 soldiers remain idle for 300 seconds because consolidation requires a strictly smaller target.x")
	_check(not stuck, "AI consolidates garrisons even when they share the same map X coordinate")
	print("SAME_COLUMN_AI_AUDIT stuck=", stuck, " enemy=", game.total_for(1), " elapsed=", game.elapsed)

func _audit_routes() -> void:
	var missing_routes := 0
	var off_ground := 0
	var route_count := 0
	var footprint_samples := 0
	var first_failure := ""
	var footprint := [Vector3(-0.842, 0, -0.55), Vector3(-0.842, 0, 0.383), Vector3(0.695, 0, -0.55), Vector3(0.695, 0, 0.383)]
	for source: Node3D in game.buildings:
		for target: Node3D in game.buildings:
			if source == target:
				continue
			route_count += 1
			var route: PackedVector3Array = game.map.get_building_route(source, target)
			if route.size() < 2:
				missing_routes += 1
				continue
			game.marches.clear()
			game.marches.send(source.building_id, target.building_id, 0, 6, route)
			var length: float = game.marches._units[0].order.length
			var steps := ceili(length / 0.4)
			for step: int in range(steps + 1):
				for unit in game.marches._units:
					unit.distance = minf(length - 0.001, float(step) / float(steps) * length)
					game.marches._update_pose(unit)
					var yaw := atan2(-unit.heading.x, -unit.heading.z)
					var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * game.marches.MODEL_SCALE)
					for point: Vector3 in footprint:
						var world: Vector3 = unit.position + basis * point
						footprint_samples += 1
						if not game.map.is_walkable(world):
							off_ground += 1
							if first_failure.is_empty():
								first_failure = "%d -> %d at %s" % [source.building_id, target.building_id, world]
	game.marches.clear()
	_check(missing_routes == 0, "All 156 ordered building pairs have a route")
	_check(off_ground == 0, "Every rotated full-model footprint remains on land or a bridge across all six files")
	print("REAL_ROUTE_AUDIT routes=", route_count, " samples=", footprint_samples, " missing=", missing_routes, " off_ground=", off_ground, " first=", first_failure)
