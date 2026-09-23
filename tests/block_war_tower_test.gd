extends SceneTree
## Real dispatch and tower interception, including an idle short-route regression.

var game: Node3D
var tower: WarBuilding
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)


func _reset(level: int = 1, faction: int = 0) -> void:
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.camera_rig.edge_scroll = false
	for building: WarBuilding in game.buildings:
		building.kind = 0
		building.level = 1
		building.population = 20.0
		building.faction = -1
	game.by_id[0].faction = 1 if faction == 0 else 0
	game.by_id[1].faction = 1
	tower = game.by_id[6]
	tower.kind = 1
	tower.level = level
	tower.faction = faction
	tower.population = 100.0
	for building: WarBuilding in game.buildings:
		building.refresh_visual()
	await physics_frame


func _spawn(offset: Vector3, faction: int, count: int = 1, direction: Vector3 = Vector3.BACK) -> void:
	var start := tower.global_position + offset
	game.marches.send(100 + faction, 12, faction, count, PackedVector3Array([start, start + direction * 35.0]))


func _shots() -> Array:
	return game.effects.filter(func(effect: Dictionary): return effect.kind == "shot")


func _run() -> void:
	await _reset()
	game.by_id[0].population = 6.0
	_check(game.issue_order(game.by_id[0], tower, 100, 1) == 6, "An enemy can issue a real six-soldier order to the nearby tower")
	var shortest: float = game.marches._units[0].order.length
	var initial_population := tower.population
	var shot_seen := false
	for frame: int in 84:
		game.simulate(1.0 / 60.0)
		shot_seen = shot_seen or not _shots().is_empty()
	_check(shot_seen, "An idle tower fires before the adjacent 4.1m route's entire first rank arrives")
	_check(tower.population > initial_population - 6.0, "The first intercepted soldier is removed before building combat settles")
	print("TOWER_SHORT_ROUTE length=", shortest, " shot_seen=", shot_seen, " tower_population=", tower.population)
	await _reset()
	game.simulate(0.1)
	_check(is_zero_approx(game.tower_clocks[tower.building_id]), "An empty target search never consumes the tower's reload")
	_spawn(Vector3(5, 0, 0), 1)
	game.simulate(0.01)
	_check(game.marches.total_for(1) == 0 and _shots().size() == 1, "A target entering an idle tower's range is intercepted on the next simulation tick")
	await _audit_levels()
	await _audit_range_entry()
	await _audit_aim()
	await _audit_pause()
	await _audit_upgrade()
	await _audit_ownership()
	print("BLOCK_WAR_TOWER checks=", checks, " failures=", failures.size())
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _audit_levels() -> void:
	for faction: int in [0, 1]:
		for level: int in [1, 2, 3]:
			await _reset(level, faction)
			var enemy := 1 - faction
			var interval: float = [1.5, 1.2, 0.9][level - 1]
			_spawn(Vector3(4, 0, 0), enemy, 6)
			_spawn(Vector3(4, 0, 2), faction, 6)
			game.marches.tick(0.25)
			game.simulate(0.001)
			var label := "faction %d level %d: " % [faction, level]
			_check(game.marches.total_for(enemy) == 6 - level, label + "one volley removes exactly its level in hostile marching soldiers")
			_check(game.marches.total_for(faction) == 6, label + "all friendly soldiers remain untouched")
			_check(is_equal_approx(game.tower_clocks[tower.building_id], interval), label + "a real shot starts the unchanged level-specific reload")
			_check(_shots().size() == 1, label + "real interception also emits a visible shot effect")
			game.simulate(interval - 0.01)
			_check(game.marches.total_for(enemy) == 6 - level, label + "reload cannot fire early")
			game.simulate(0.011)
			_check(game.marches.total_for(enemy) == 6 - level * 2, label + "the next volley fires when reload completes")
	for level: int in [1, 2, 3]:
		await _reset(level)
		var radius: float = 10.0 + level
		_check(is_equal_approx(game.tower_range(tower), radius), "Level %d preserves its %dm center-based range" % [level, radius])
		_spawn(Vector3(radius + 0.05, 0, 0), 1)
		game.simulate(0.001)
		_check(game.marches.total_for(1) == 1 and _shots().is_empty(), "Level %d never shoots outside its range" % level)
		game.marches.clear()
		_spawn(Vector3(-radius + 0.05, 0, 0), 1)
		game.simulate(0.001)
		_check(game.marches.total_for(1) == 0 and _shots().size() == 1, "Level %d shoots just inside its range without an idle delay" % level)


func _audit_range_entry() -> void:
	await _reset()
	game.simulate(20.0)
	_check(is_zero_approx(game.tower_clocks[tower.building_id]), "Long idle periods neither consume reload nor accumulate burst fire credit")
	_spawn(Vector3(11.1, 0, 0), 1, 1, Vector3.LEFT)
	game.simulate(1.0 / 60.0)
	_check(game.marches.total_for(1) == 1, "An approaching enemy is still safe before crossing the range boundary")
	for frame: int in 3:
		game.simulate(1.0 / 60.0)
	_check(game.marches.total_for(1) == 0 and _shots().size() == 1, "Walking across the range boundary triggers one immediate interception")
	await _reset()
	game.by_id[0].kind = 2
	var stationed: float = game.by_id[0].population
	game.simulate(5.0)
	_check(game.by_id[0].population == stationed and _shots().is_empty(), "A nearby enemy garrison is not a marching target")


func _audit_aim() -> void:
	for level: int in [1, 2, 3]:
		await _reset(level)
		for direction: Vector3 in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			game.effects.clear()
			game.tower_clocks[tower.building_id] = 0.0
			_spawn(direction * 5.0, 1)
			game.simulate(0.001)
			var shots := _shots()
			_check(shots.size() == 1, "Level %d emits a shot toward %s" % [level, direction])
			if shots.is_empty():
				continue
			var shot: Dictionary = shots[0]
			var gun: Node3D = tower.get_node("Visual/Tower/Gun")
			var forward := -gun.global_basis.z
			forward.y = 0.0
			_check(forward.normalized().dot(direction) > 0.999, "The level %d cannon turns to face %s" % [level, direction])
			_check(shot.at.distance_to(tower.muzzle_position()) < 0.001 and shot.at.y > 1.0, "The level %d shot leaves its current physical muzzle" % level)
			_check(shot.to.distance_to(tower.global_position + direction * 5.0 + Vector3(0, 0.5, 0)) < 0.001, "The shot ends at its actual intercepted soldier")
			var projected := true
			for progress: float in [0.0, 0.25, 0.5, 0.75, 0.99]:
				var at: Vector3 = shot.at.lerp(shot.to, progress) + Vector3(0, sin(progress * PI) * 2.0, 0)
				projected = projected and not game.camera.is_position_behind(at) and game.get_viewport().get_visible_rect().has_point(game.camera.unproject_position(at))
			_check(projected and shot.life > 0.3, "The shot's arc remains visible to the active battlefield camera")


func _audit_pause() -> void:
	await _reset()
	_spawn(Vector3(4, 0, 0), 1, 6)
	game.marches.tick(0.25)
	game.simulate(0.001)
	var remaining: float = game.tower_clocks[tower.building_id]
	var shot_life: float = _shots()[0].life
	var before: float = game.elapsed
	game.set_paused(true)
	game.simulate(5.0)
	_check(game.elapsed == before and game.tower_clocks[tower.building_id] == remaining and game.marches.total_for(1) == 5, "Pause freezes tower reload, marching victims and damage")
	_check(_shots()[0].life == shot_life and not tower._recoil_tween.is_running(), "Pause also freezes the shot arc and cannon recoil")
	game.set_paused(false)
	game.simulate(remaining + 0.001)
	_check(game.marches.total_for(1) == 4, "Resume continues the existing reload and fires exactly one volley")


func _audit_upgrade() -> void:
	await _reset()
	game.select_building(tower)
	game.upgrade_selected()
	_check(tower.level == 1 and tower.is_upgrading and tower.population == 70.0 and game.tower_range(tower) == 11.0, "A paid upgrade retains the current combat level during construction")
	_spawn(Vector3(4, 0, 0), 1, 6)
	game.marches.tick(0.25)
	game.simulate(0.001)
	_check(game.marches.total_for(1) == 5 and is_equal_approx(game.tower_clocks[tower.building_id], 1.5), "A working tower still shoots with its current damage and reload")
	game.marches.clear()
	game.simulate(9.999)
	_check(tower.level == 2 and tower.population == 70.0 and game.tower_range(tower) == 12.0, "Ten seconds completes level two and changes combat range")
	_spawn(Vector3(4, 0, 0), 1, 6)
	game.marches.tick(0.25)
	game.simulate(0.001)
	_check(game.marches.total_for(1) == 4 and is_equal_approx(game.tower_clocks[tower.building_id], 1.2), "The upgraded tower uses level-two damage and reload")
	game.upgrade_selected()
	_check(tower.level == 2 and tower.population == 10.0 and tower.is_upgrading, "A paid level-three upgrade keeps the existing cost and starts another ten seconds")
	game.simulate(1.201)
	_check(game.marches.total_for(1) == 2, "Level-three construction continues firing level-two volleys")
	game.marches.clear()
	game.simulate(8.698)
	_spawn(Vector3(4, 0, 0), 1, 6)
	game.marches.tick(0.25)
	game.simulate(0.001)
	_check(game.marches.total_for(1) == 4, "A volley immediately before completion still uses level two")
	game.simulate(0.1)
	_check(tower.level == 3 and game.tower_range(tower) == 13.0 and game.marches.total_for(1) == 4, "Completion extends range without granting a free shot")
	game.simulate(1.101)
	_check(game.marches.total_for(1) == 1 and is_equal_approx(game.tower_clocks[tower.building_id], 0.9), "The next volley uses level-three damage without bypassing the previous reload")


func _audit_ownership() -> void:
	await _reset(2, -1)
	_spawn(Vector3(4, 0, 0), 0)
	_spawn(Vector3(5, 0, 0), 1)
	game.simulate(0.1)
	_check(game.marches.total_for(0) == 1 and game.marches.total_for(1) == 1 and _shots().is_empty(), "An unclaimed neutral tower does not attack either faction")
	tower.population = 0.0
	game._on_unit_arrived(tower.building_id, 0, 1.0)
	_check(tower.faction == 0 and tower.level == 1 and is_equal_approx(game.tower_clocks[tower.building_id], 0.6), "Capturing a neutral tower enables its new owner after the existing capture delay")
	game.simulate(0.59)
	_check(_shots().is_empty(), "Capture delay cannot be skipped by the idle-ready change")
	game.simulate(0.02)
	_check(game.marches.total_for(0) == 1 and game.marches.total_for(1) == 0 and _shots().size() == 1, "A newly claimed tower intercepts the enemy and preserves its new owner's soldiers")
	await _reset(3)
	_spawn(Vector3(4, 0, 0), 0, 3)
	_spawn(Vector3(5, 0, 0), 1, 3)
	game.marches.tick(0.25)
	tower.population = 0.0
	game._on_unit_arrived(tower.building_id, 1, 1.0)
	game.simulate(0.61)
	_check(tower.faction == 1 and tower.level == 2 and game.marches.total_for(0) == 1 and game.marches.total_for(1) == 3, "Enemy recapture reverses target allegiance and applies the downgraded level-two damage")
