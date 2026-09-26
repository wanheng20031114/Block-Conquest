extends SceneTree
## Original-source returns must remain navigable on every authored battlefield.
const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL ", label)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	for definition: Resource in CATALOG.MAPS:
		root.get_node("Session").block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		for source: WarBuilding in game.buildings:
			if source.faction < 0:
				continue
			var target: WarBuilding
			var longest := 0.0
			for candidate: WarBuilding in game.buildings:
				var distance: float = game.map.get_building_distance(source, candidate)
				if distance > longest:
					longest = distance
					target = candidate
			var guide: PackedVector3Array = game.map.get_building_route(source, target)
			var order: WarMarches.MarchOrder = game.marches._make_order(source.building_id, target.building_id, source.faction, guide)
			for progress: float in [0.01, 0.07, 0.48, 0.87, 0.98]:
				for lane: float in [-1.4, 0.0, 1.4]:
					var distance := order.length * progress
					var from: Vector3 = game.marches._formation_position(order, distance, lane, game.marches._route_heading(order, distance))
					var route: PackedVector3Array = game.map.get_return_route(from, source, target)
					var label := "%s faction=%d progress=%.2f lane=%.1f" % [definition.map_id, source.faction, progress, lane]
					check(route.size() >= 2, label + " gets a return path")
					if route.size() < 2:
						continue
					check(route[0].is_equal_approx(from), label + " preserves position")
					check(absf(route[-1].distance_to(source.global_position) - WarBuilding.MARCH_PERIMETER_RADIUS) < 0.08, label + " ends at original source")
					var clear := true
					for index: int in range(1, route.size()):
						if not game.map._recall_segment_clear(route[index - 1], route[index], source):
							clear = false
					check(clear, label + " stays on clear terrain and bridges")
		await game.prepare_shutdown()
	print("BLOCK_WAR_RECALL_ROUTES checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
