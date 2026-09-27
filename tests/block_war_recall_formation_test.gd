extends SceneTree
## Replay actual outbound positions backwards: files and ranks must not collapse.
const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func positions(units: Array[WarMarches.MarchUnit]) -> PackedVector3Array:
	var result := PackedVector3Array()
	for unit: WarMarches.MarchUnit in units:
		result.append(unit.position)
	return result

func farthest(source: WarBuilding) -> WarBuilding:
	var target: WarBuilding
	var longest := 0.0
	for candidate: WarBuilding in game.buildings:
		var distance: float = game.map.get_building_distance(source, candidate)
		if distance > longest:
			longest = distance
			target = candidate
	return target

func verify_surface(label: String) -> void:
	var home: WarBuilding = game.buildings[0]
	var target := farthest(home)
	var route: PackedVector3Array = game.map.get_building_route(home, target)
	game.marches.send(home.building_id, target.building_id, home.faction, 24, route)
	var units: Array[WarMarches.MarchUnit] = game.marches._units.duplicate()
	game.marches.tick(units[0].order.length * 0.48 / WarMarches.SPEED)
	var history: Array[PackedVector3Array] = [positions(units)]
	for frame: int in 20:
		game.marches.tick(0.1)
		history.append(positions(units))
	var center := Vector3.ZERO
	for at: Vector3 in history[-1]:
		center += at / units.size()
	var headings := PackedVector3Array()
	for unit: WarMarches.MarchUnit in units:
		headings.append(unit.heading)
	units[0].reserved = true
	units[0].cloaked = true
	check(game.RABBIT_SKILLS.recall(game, center, 0) == 24, label + " recalls the entire four-rank squad")
	check(units[0].reserved and units[0].cloaked, label + " retains projectile locks and cloak")
	for index: int in units.size():
		check(units[index].position.is_equal_approx(history[-1][index]), label + " no sideways teleport")
		check(units[index].heading.dot(headings[index]) < -0.999, label + " turns each soldier home")
	for frame: int in 20:
		game.marches.tick(0.1)
		var expected := history[19 - frame]
		for index: int in units.size():
			check(units[index].position.distance_to(expected[index]) < 0.0001, label + " retraces each original file and rank")
	check(game.marches.incoming_for(home.building_id, home.faction) == 24, label + " original home receives the full squad")
	check(game.RABBIT_SKILLS.recall_plan(game, units[0].position).is_empty(), label + " repeated recall leaves the returning formation alone")
	game.marches.clear()

func verify_partial() -> void:
	var home: WarBuilding = game.buildings[0]
	var target := farthest(home)
	var route: PackedVector3Array = game.map.get_building_route(home, target)
	game.marches.send(home.building_id, target.building_id, home.faction, 72, route)
	var units: Array[WarMarches.MarchUnit] = game.marches._units.duplicate()
	var outbound := units[0].order
	game.marches.tick(outbound.length * 0.55 / WarMarches.SPEED)
	var before := positions(units)
	var center := units[0].position
	var plans: Array[Dictionary] = game.RABBIT_SKILLS.recall_plan(game, center)
	check(plans.size() > 6 and plans.size() < units.size(), "circle cuts through a larger formation")
	var selected: Array[WarMarches.MarchUnit] = []
	for plan: Dictionary in plans:
		selected.append(plan.unit)
	game.RABBIT_SKILLS.recall(game, center, 0)
	for index: int in units.size():
		check(units[index].position.is_equal_approx(before[index]), "partial recall keeps everybody in place")
		check((units[index].order == outbound) == (units[index] not in selected), "outside soldiers keep their original order")
	check(game.marches._units.size() == 72, "partial recall neither duplicates nor removes soldiers")
	game.marches.clear()

func verify_tunnel() -> void:
	var home: WarBuilding = game.buildings[0]
	var target := farthest(home)
	var route: PackedVector3Array = game.map.get_building_route(home, target)
	game.marches.send_tunnel(home.building_id, target.building_id, home.faction, 18, route, 0.16)
	game.marches.tick(0.55)
	var units: Array[WarMarches.MarchUnit] = game.marches._units.duplicate()
	var before := positions(units)
	check(game.RABBIT_SKILLS.recall(game, units[0].position, 0) == 18, "emerged tunnel ranks can all return")
	for index: int in units.size():
		check(units[index].position.is_equal_approx(before[index]), "tunnel reversal has no position jump")
	game.marches.tick(1.5)
	var left := units[0].position
	var right := units[5].position
	check(left.distance_to(right) > 2.0, "tunnel ranks expand back into six files after passing the exit")
	for unit: WarMarches.MarchUnit in units:
		check(unit.order.sample(unit.order.length).distance_to(home.global_position) < WarBuilding.MARCH_PERIMETER_RADIUS + 0.08, "tunnel return ends at home, not the tunnel exit")
		check(unit.order.length - unit.distance > 10.0, "distant tunnel squad still has the surface route to walk")
	var garrison := home.population
	game.marches.tick(units[0].order.length / WarMarches.SPEED + 2.0)
	check(game.marches._units.is_empty() and home.population == garrison + 18, "tunnel return credits each original soldier once")

func run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	for definition: Resource in CATALOG.MAPS:
		root.get_node("Session").block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		game = current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		verify_surface(definition.map_id)
		verify_partial()
		verify_tunnel()
		await game.prepare_shutdown()
	print("BLOCK_WAR_RECALL_FORMATION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
