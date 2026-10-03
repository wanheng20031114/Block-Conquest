extends SceneTree
## HUD cache is checked against the inspector's previous independent traversal.
## Exercise real accounting transitions without advancing the automatic game loop.

const DATA := preload("res://scripts/block_war/war_debug_data.gd")
const SNAPSHOT := preload("res://scripts/network/war_snapshot.gd")
const FIELDS: Array[String] = ["garrison", "queued", "marching", "airlifting"]
var game: Node3D
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL DEBUG_ARMY_CACHE ", label)


func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s (%s / %s)" % [label, actual, expected])


func oracle(faction: int) -> Dictionary:
	var result := {"garrison": 0.0, "queued": 0, "marching": 0, "airlifting": 0}
	for building: WarBuilding in game.buildings:
		if building.faction == faction:
			result.garrison += building.population
			result.queued += building.queued_population
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.alive and unit.order.faction == faction and not unit.pending_departure:
			result.marching += 1
	for airlift: Dictionary in game.pig.airlifts:
		if airlift.faction == faction:
			result.airlifting += game.SKILL_RULES.PIG_AIRLIFT_COUNT - int(airlift.landed)
	return result


func verify(label: String) -> void:
	game.update_hud()
	check(game.hud_armies.size() == 6, label + " has one cache row per seat")
	if game.hud_armies.size() != 6:
		return
	var before: Dictionary = SNAPSHOT.new().capture(game, 42)
	var cache_before: Array = game.hud_armies.duplicate(true)
	var original_viewer: int = game.local_faction
	for faction: int in 6:
		var expected := oracle(faction)
		var cached: Dictionary = game.hud_armies[faction]
		game.local_faction = faction
		var displayed: Dictionary = DATA.capture(game)
		for field: String in FIELDS:
			near(float(cached[field]), float(expected[field]), "%s seat %d cached %s" % [label, faction, field])
			near(float(displayed[field]), float(expected[field]), "%s seat %d inspector %s" % [label, faction, field])
		near(displayed.army_total, expected.garrison + expected.marching + expected.airlifting,
			"%s seat %d total counts each soldier once" % [label, faction])
	game.local_faction = original_viewer
	check(game.hud_armies == cache_before, label + " repeated inspector reads do not mutate cached rows")
	check(SNAPSHOT.digest(SNAPSHOT.new().capture(game, 42)) == SNAPSHOT.digest(before),
		label + " inspector reads leave all canonical game facts unchanged")


func exposed(faction: int) -> WarMarches.MarchUnit:
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.faction == faction and unit.is_exposed():
			return unit
	return null


func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	session.block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.marches.clear()
	game.morale.configure(game.faction_count)
	game.elapsed = 1.0
	for building: WarBuilding in game.buildings:
		building.faction = building.building_id if building.building_id < 6 else -1
		building.kind = 3
		building.level = 1
		building.population = 80.25 + building.building_id * 3.0
		building.cancel_construction()
		building.clear_disruption()
		building.clear_burrow()
		building.refresh_visual()
	for state: RefCounted in game.faction_skills:
		state.commander = game.SKILL_RULES.COMMANDER_ID
		state.energy = 100.0
		state.cooldowns.fill(0.0)
		state.durations.fill(0.0)
	game.faction_skills[0].commander = game.SKILL_RULES.FOX
	game.faction_skills[2].commander = game.SKILL_RULES.RABBIT
	game.faction_skills[4].commander = game.SKILL_RULES.PIG
	game.faction_skills[5].commander = game.SKILL_RULES.PIG
	game.sync_environment_bonuses()
	verify("initial fractional garrisons")

	for faction: int in 6:
		var source: WarBuilding = game.by_id[faction]
		var accepted: Dictionary = game.execute_network_command(faction,
			{"type": "dispatch", "source": source.building_id, "target": 6, "percent": 100})
		check(accepted.accepted and source.queued_population > 0,
			"seat %d accepts a real command with pending departures" % faction)
	verify("six simultaneous departure queues")
	game.marches.tick(0.25)
	verify("partial ranks depart")
	for faction: int in 6:
		check(oracle(faction).marching > 0 and oracle(faction).queued > 0,
			"seat %d has both queued and departed soldiers" % faction)

	var casualty := exposed(0)
	check(casualty != null, "casualty fixture finds an exposed soldier")
	if casualty != null:
		var marching_before: int = oracle(0).marching
		check(game.marches.hit_target(casualty, Vector3.RIGHT), "real casualty removes a live soldier")
		check(oracle(0).marching == marching_before - 1, "casualty reduces the independent field count")
	verify("casualty compacts the live array")

	var damaged: WarBuilding = game.by_id[1]
	var queued_before: int = damaged.queued_population
	game._on_unit_arrived(damaged.building_id, 0, floorf(damaged.population) - 3.0)
	check(damaged.faction == 1 and damaged.queued_population > 0 and damaged.queued_population < queued_before,
		"garrison damage trims the real reservation queue without capture")
	verify("damaged garrison trims newest reservations")
	game._on_unit_arrived(damaged.building_id, 0, 10.0)
	check(damaged.faction == 0 and damaged.queued_population == 0,
		"capture changes owner and cancels remaining reservations")
	verify("capture retains already departed former-owner soldiers")

	var converted := exposed(3)
	check(converted != null, "conversion fixture finds an enemy soldier")
	if converted != null:
		check(game.cast_ground_skill(2, converted.position, 0), "fox casts a real conversion")
		check(converted.alive and converted.order.faction == 0, "conversion transfers live soldier accounting")
	verify("fox conversion changes marching owner")

	var recalled := exposed(2)
	check(recalled != null, "recall fixture finds a departed soldier")
	if recalled != null:
		var units_before: int = game.marches._units.size()
		check(game.cast_ground_skill(2, recalled.position, 2), "rabbit casts a real recall")
		check(recalled.order.returning and game.marches._units.size() == units_before,
			"recall changes route without adding or removing troops")
	verify("recalled troops remain in the marching count")

	for faction: int in [4, 5]:
		check(game.cast_skill(2, game.by_id[faction], faction), "seat %d starts a real pig airlift" % faction)
		check(oracle(faction).airlifting == game.SKILL_RULES.PIG_AIRLIFT_COUNT,
			"seat %d owns its generated airborne soldiers" % faction)
	verify("opposing pig airlifts")
	game.pig.advance(game, 0.4)
	for faction: int in [4, 5]:
		check(oracle(faction).airlifting == game.SKILL_RULES.PIG_AIRLIFT_COUNT - game.SKILL_RULES.PIG_AIRLIFT_BATCH_SIZE,
			"seat %d lands exactly one batch" % faction)
	verify("airlift batch transfers to physical garrison")

	var saved: Dictionary = SNAPSHOT.new().capture(game, 42)
	check(SNAPSHOT.valid(saved, game), "mixed queued marching converted recalled and airborne snapshot validates")
	game.marches.clear()
	game.pig.airlifts.clear()
	for building: WarBuilding in game.buildings:
		building.population = 0.0
	verify("cleared live armies invalidate previous totals on refresh")
	SNAPSHOT.new().install(game, saved)
	verify("snapshot installation restores all six cached armies")
	check(SNAPSHOT.digest(SNAPSHOT.new().capture(game, 42)) == SNAPSHOT.digest(saved),
		"cache refresh and inspector preserve the restored canonical snapshot")

	await game.prepare_shutdown()
	print("BLOCK_WAR_DEBUG_ARMY_CACHE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
