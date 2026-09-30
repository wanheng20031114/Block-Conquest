extends SceneTree
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FOX := preload("res://scripts/block_war/war_fox_skills.gd")
const AI := preload("res://scripts/block_war/war_ai_skills.gd")
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var sounds: Array[StringName] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 0.00001, "%s: %s / %s" % [label, actual, expected])

func reset() -> void:
	game.audio._listener.global_position = Vector3(0, 6, 0)
	for voice: AudioStreamPlayer3D in game.audio.get_node("Combat").get_children():
		voice.stop()
	game.marches.clear()
	game.projectiles.clear()
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.shots.clear(); game.bear.damage_remainders.clear()
	game.morale.configure(game.faction_count)
	game.elapsed = 0.0
	game.finished = false
	game._cancel_skill_drag()
	for building: WarBuilding in game.buildings:
		building.faction = building.building_id if building.building_id < 6 else -1
		building.population = 40.0
		building.kind = 0; building.level = 1
		building.cancel_construction(); building.clear_disruption(); building.clear_burrow()
		building.refresh_visual()
	for state: RefCounted in game.faction_skills:
		state.commander = RULES.FOX
		state.energy = 100.0; state.cooldowns.fill(0.0); state.durations.fill(0.0)
	sounds.clear()

func refill(faction: int = 0) -> void:
	game.faction_skills[faction].energy = 100.0
	game.faction_skills[faction].cooldowns.fill(0.0)

func soldier(faction: int, at: Vector3, target_id: int = 0) -> WarMarches.MarchUnit:
	game.marches.send(1, target_id, faction, 1, PackedVector3Array([at, at + Vector3(30, 0, 0)]))
	return game.marches._units[-1]

func panic_marks(marches: WarMarches) -> MultiMesh:
	return marches.get_node("PanicMarks").multimesh

func check_panic_pose(marches: WarMarches, unit: WarMarches.MarchUnit, index: int, label: String) -> void:
	var at := panic_marks(marches).get_instance_transform(index).origin
	var soldier_at := marches._presentation_position(unit)
	check(Vector2(at.x, at.z).distance_to(Vector2(soldier_at.x, soldier_at.z)) < 0.0001 and at.y > soldier_at.y + 0.4, label)

func _run() -> void:
	create_timer(50.0, true, false, true).timeout.connect(func(): quit(3))
	var session := root.get_node("Session")
	session.block_war_map_id = "highland"
	session.block_war_commander = &"fox"
	session.block_war_opponent_commander = &"fox"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false); game.ai_enabled = false
	# Dummy audio renders silently while still exercising the real success events.
	assert(AudioServer.get_driver_name() == "Dummy")
	game.audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool): sounds.append(kind))
	reset()
	for index: int in 4:
		check(game.skill_is_ground(index) == (index == 2), "fox target mode %d" % index)
		check(not RULES.description(index, RULES.FOX).is_empty(), "tooltip %d" % index)
	game.energy = 30
	check(game.can_cast_skill(0), "Q affordable at opening")
	refill()
	var target: WarBuilding = game.by_id[1]
	target.population = 31
	check(game.cast_skill(0, target), "Q accepts enemy")
	near(target.population, 16, "31 loses exactly 15")
	near(game.energy, 75, "Q costs 25")
	check(sounds.has(&"war_fox_bomb"), "Q emits own sound")
	check(not game.cast_skill(0, target), "Q cooldown")
	refill(); target.population = 1000
	check(game.cast_skill(0, target), "Q large garrison")
	near(target.population, 970, "Q capped at thirty")
	refill(); target.faction = -1; target.population = 3
	check(game.cast_skill(0, target), "Q neutral")
	near(target.population, 2, "odd neutral garrison")
	refill(); target.population = 1
	check(not game.cast_skill(0, target), "Q rejects zero integer loss")
	near(game.energy, 100, "rejected cast free")
	for faction: int in [0, 2, 4]:
		target.faction = faction; target.population = 60
		check(not game.cast_skill(0, target), "Q protects team %d" % faction)
	reset(); target.population = 42
	game.by_id[3].faction = 1
	game.bear.links[1] = {"target": 1, "support": 3, "faction": 1, "remaining": 8.0, "settled": 0, "pulse": 0.0}
	check(game.cast_skill(0, target), "bomb respects chain link")
	near(target.population, 32, "21 damage keeps 10 at target")
	near(game.by_id[3].population, 29, "support takes 11")
	refill(); game.bear.wards[1] = {"faction": 1, "remaining": 5.0, "shot_clock": 0.5, "pulse": 0.0}
	check(game.cast_skill(0, target), "warded target remains vulnerable to proportional bomb damage")
	near(target.population, 24, "ward does not reduce the bomb before ordinary link sharing")
	near(game.by_id[3].population, 21, "linked support pays its full assigned bomb share")
	refill()
	check(game.cast_skill(3, target), "warded target remains vulnerable to panic")
	near(target.population, 5, "panic still removes floor eighty percent of the warded garrison")
	check(game.marches.total_for(1) == 19, "all nineteen displaced soldiers are real friendly refugees")
	reset()
	game.morale.adjust(1, 8000)
	check(game.cast_skill(1, target), "steal via building owner")
	near(game.morale.stars(1), 4, "five-star victim loses one")
	near(game.morale.stars(0), 1, "zero-star thief gains only one")
	check(sounds.has(&"war_fox_steal"), "W sound")
	reset(); game.morale.adjust(3, 125)
	check(game.cast_skill(1, game.by_id[3]), "correct enemy in teams")
	near(game.morale.stars(3), 0, "fractional star victim drained")
	near(game.morale.stars(0), 0.25, "quarter star received")
	near(game.morale.stars(1), 0, "unselected enemy unchanged")
	reset(); game.morale.adjust(1, 8000); game.morale.adjust(0, WarMorale.points_for_stars(4.75))
	check(game.cast_skill(1, target), "near-cap transfer")
	near(game.morale.stars(0), 5, "no overfill")
	near(game.morale.stars(1), 4.75, "only capacity actually taken")
	refill(); check(not game.cast_skill(1, target), "full morale is free refusal")
	reset(); check(not game.cast_skill(1, target), "empty victim is free refusal")
	game.morale.adjust(2, 8000)
	check(not game.cast_skill(1, game.by_id[2]), "cannot steal from teammate")
	check(not game.cast_skill(1, game.by_id[6]), "cannot steal from neutral")
	reset()
	var center := Vector3.ZERO
	var originals: Array[Dictionary] = []
	for i: int in 12:
		var unit := soldier(1, Vector3((i % 4) * 0.45, 0, (i / 4) * 0.45))
		unit.rush_remaining = 3.0; unit.weakened = true
		originals.append({"unit": unit, "at": unit.position, "distance": unit.distance, "lane": unit.lane, "curve": unit.order.curve})
	var far := soldier(1, Vector3(3.1, 0, 0))
	var ally := soldier(2, Vector3(1, 0, 0))
	var friend := soldier(0, Vector3(1, 0, 1))
	var pending := soldier(1, Vector3(1, 0, 1)); pending.spawn_delay = 2
	check(game.cast_ground_skill(2, center), "recruit enemies")
	for entry: Dictionary in originals:
		var unit: WarMarches.MarchUnit = entry.unit
		check(unit.order.faction == 0 and unit.order.target_id == 0 and unit.alive, "permanent faction and target")
		check(unit.position == entry.at and unit.distance == entry.distance and unit.lane == entry.lane and unit.order.curve == entry.curve, "identity/formation/position kept")
		check(unit.rush_remaining == 3.0 and unit.weakened, "existing statuses retained")
	check(far.order.faction == 1 and pending.order.faction == 1 and ally.order.faction == 2 and friend.order.faction == 0, "area, team and exposure boundaries")
	check(sounds.has(&"war_fox_convert"), "E sound")
	var recruited: WarMarches.MarchUnit = originals[0].unit
	recruited.reserved = true; recruited.intercepted_by = 0
	check(not game.marches.hit_target(recruited, Vector3.RIGHT, true) and recruited.alive, "in-flight allied cannon cannot kill recruit")
	recruited.reserved = true; recruited.intercepted_by = 2
	check(not game.marches.hit_target(recruited, Vector3.RIGHT) and recruited.alive, "allied orb cannot kill recruit")
	recruited.reserved = true; recruited.intercepted_by = 1
	check(game.marches.hit_target(recruited, Vector3.RIGHT) and not recruited.alive, "enemy projectile still lethal")
	refill(); check(not game.cast_ground_skill(2, Vector3(70, 0, 60)), "empty conversion free refusal")
	reset()
	game.marches.send(1, 0, 1, 36, PackedVector3Array([Vector3(-6, 0, 0), Vector3(30, 0, 0)]))
	game.marches.tick(1.7)
	var original_order: WarMarches.MarchOrder = game.marches._units[0].order
	var selected: Array[WarMarches.MarchUnit] = FOX.conversion_targets(game, Vector3.ZERO, 0)
	check(selected.size() > 0 and selected.size() < 36, "part of a shared formation selected")
	check(game.cast_ground_skill(2, Vector3.ZERO), "partial formation recruitment")
	var transferred: WarMarches.MarchOrder = selected[0].order
	check(transferred != original_order and transferred.order_id != original_order.order_id, "new order identity for new ownership")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order == (transferred if unit in selected else original_order), "selected subset shares curve without changing other soldiers")
	# A cloaked march can be caught by a manually aimed area spell, but the AI
	# cannot use invisible positions to decide where to cast.
	reset()
	for i: int in 12:
		var hidden := soldier(0, Vector3((i % 4) * 0.4, 0, (i / 4) * 0.4), 1)
		hidden.cloaked = true
	game.elapsed = 10
	game.faction_skills[1].cooldowns.fill(999.0); game.faction_skills[1].cooldowns[2] = 0
	AI.new(1).take_turn(game)
	near(game.faction_skills[1].cooldowns[2], 0, "AI cannot see cloaked targets")
	reset()
	# Exactly one refuge, deliberately the most distant reachable building.
	var farthest: WarBuilding = game.by_id[7]
	for b: WarBuilding in game.buildings:
		if b == target: continue
		b.faction = 0
		if game.map.get_building_distance(target, b) > game.map.get_building_distance(target, farthest): farthest = b
	farthest.faction = 1
	target.population = 31
	check(game.map.get_building_distance(target, farthest) > 40, "refuge genuinely far away")
	check(game.cast_skill(3, target), "distant refuge accepts panic")
	near(target.population, 7, "31 loses floor 80 percent = 24")
	check(game.marches._units.size() == 24, "exactly 24 flee")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.target_id == farthest.building_id and unit.order.faction == 1, "flee toward own distant faction")
		check(unit.order.panicked, "every fleeing soldier retains panic for its journey")
	check(sounds.has(&"war_fox_panic"), "R sound")
	var total: float = farthest.population + target.population + game.marches._units.size()
	game.marches.tick(1.6)
	game.world_effects.get_node("Fox").advance(1.6)
	check(game.world_effects.get_node("Fox/Casts").get_children().all(func(slot: Node3D): return slot.kind != 3 or not slot.active), "short R cast effects have ended")
	check(panic_marks(game.marches).visible_instance_count == 24, "panic remains visible on every refugee after the cast effect ends")
	check_panic_pose(game.marches, game.marches._units[0], 0, "panic mark follows the distant fleeing soldier")
	game.marches.tick(300)
	near(farthest.population + target.population, total, "all refugees arrive with conserved population")
	check(panic_marks(game.marches).visible_instance_count == 0, "arrivals remove every panic mark")
	reset(); target.population = 50
	for id: int in [3, 5, 7, 9]: game.by_id[id].faction = 1
	game.marches.queue_departure(1, 0, 1, 30, game.map.get_building_route(target, game.by_id[0]))
	var before: float = target.population
	var paid_before: int = game.marches._units.filter(func(u: WarMarches.MarchUnit): return not u.pending_departure).size()
	check(game.cast_skill(3, target), "panic cancels existing queue cleanly")
	check(target.queued_population == 0, "no stale garrison reservations")
	var destinations := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		if unit.order.target_id != 0: destinations[unit.order.target_id] = true
	check(destinations.size() <= 3 and destinations.size() > 1, "at most three nearby refuges")
	near(target.population + game.marches._units.size(), before + paid_before, "queued panic conservation")
	refill()
	for b: WarBuilding in game.buildings:
		if b != target: b.faction = 0
	check(not game.cast_skill(3, target), "last enemy building has no refuge")
	near(game.energy, 100, "no refuge consumes nothing")
	_panic_marker_checks()
	await _network_check()
	_ai_checks()
	await game.prepare_shutdown()
	print("FOX_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _panic_marker_checks() -> void:
	reset()
	var ordinary := soldier(1, Vector3.ZERO)
	var fleeing := soldier(1, Vector3(2, 0, 0))
	fleeing.order.panicked = true
	var hidden := soldier(1, Vector3(4, 0, 0))
	hidden.order.panicked = true; hidden.cloaked = true
	var delayed := soldier(1, Vector3(6, 0, 0))
	delayed.order.panicked = true; delayed.spawn_delay = 2.0
	var unstarted := soldier(1, Vector3(8, 0, 0))
	unstarted.order.panicked = true; unstarted.distance = -1.0
	game.marches.queue_departure(1, 0, 1, 1, PackedVector3Array([Vector3(10, 0, 0), Vector3(40, 0, 0)]))
	var queued: WarMarches.MarchUnit = game.marches._units[-1]
	queued.order.panicked = true
	check(queued.pending_departure, "panic visibility fixture includes a reserved garrison soldier")
	game.marches._render()
	check(not ordinary.order.panicked and panic_marks(game.marches).visible_instance_count == 1, "only the exposed fleeing soldier is marked; ordinary, cloaked, delayed and queued soldiers are not")
	check_panic_pose(game.marches, fleeing, 0, "panic mark begins above its own soldier")
	fleeing.presentation_offset = Vector3(0.7, 0.1, -0.4)
	game.marches._render()
	check_panic_pose(game.marches, fleeing, 0, "panic mark follows the interpolated position across terrain")
	fleeing.order = game.marches.transfer_order(fleeing.order, 0)
	check(fleeing.order.panicked, "recruitment preserves panic on the remaining journey")
	var recall: WarMarches.MarchOrder = game.marches.return_order(fleeing.order)
	game.marches.redirect(fleeing, recall)
	game.marches._render()
	check(recall.panicked and panic_marks(game.marches).visible_instance_count == 1, "recall keeps the refugee's panic mark")
	fleeing.intercepted_by = 1
	check(game.marches.hit_target(fleeing, Vector3.RIGHT), "a real projectile kills the fleeing soldier")
	check(panic_marks(game.marches).visible_instance_count == 0, "death removes its panic mark immediately")
	hidden.cloaked = false
	game.marches._render()
	check(panic_marks(game.marches).visible_instance_count == 1, "revealing a still fleeing soldier restores its mark")
	game.marches.clear()
	check(panic_marks(game.marches).visible_instance_count == 0, "clearing the battle leaves no stale panic marks")

func _network_check() -> void:
	reset(); game.morale.adjust(1, 2000)
	check(game.cast_skill(1, game.by_id[1]), "network W setup")
	soldier(1, Vector3.ZERO)
	check(game.cast_ground_skill(2, Vector3.ZERO), "network E setup")
	game.energy = 100
	game.by_id[3].faction = 1
	check(game.cast_skill(3, game.by_id[1]), "network R setup")
	game.marches.tick(1.6)
	game.elapsed = 1.6
	var replica: Node3D = load("res://scenes/block_war/block_war.tscn").instantiate()
	root.add_child(replica)
	replica.set_process(false); replica.camera_rig.set_process(false); replica.ai_enabled = false; replica.audio.muted = true
	var writer := Snapshot.new()
	var reader := Snapshot.new()
	var state := writer.capture(game, 4)
	check(Snapshot.valid(state, replica), "fox snapshot validates")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(state, "", true, true))
	check(Snapshot.valid(wire, replica), "fox JSON snapshot validates")
	reader.install(replica, wire)
	check(replica.faction_skills[0].commander == RULES.FOX, "replica fox commander")
	near(replica.morale.stars(0), game.morale.stars(0), "replica stolen morale")
	check(replica.marches._units.size() == game.marches._units.size(), "replica recruited and fleeing count")
	for unit: WarMarches.MarchUnit in game.marches._units:
		var copy: WarMarches.MarchUnit = reader._objects[str(unit.unit_id)]
		check(copy.order.faction == unit.order.faction and copy.order.target_id == unit.order.target_id and is_equal_approx(copy.lane, unit.lane), "replica faction destination formation")
		check(copy.order.panicked == unit.order.panicked, "replica preserves panic and ordinary march states")
	check(panic_marks(replica.marches).visible_instance_count == panic_marks(game.marches).visible_instance_count and panic_marks(replica.marches).visible_instance_count > 0, "snapshot alone restores fleeing marks without replaying a cast")
	var refugees: Array = replica.marches._units.filter(func(unit: WarMarches.MarchUnit): return unit.order.panicked and unit.is_exposed())
	var displayed: WarMarches.MarchUnit = refugees[0]
	game.marches.tick(0.2)
	game.elapsed += 0.2
	state = writer.capture(game, 5)
	reader.install(replica, state)
	check(displayed.presentation_offset.length() > 0.01, "network correction exercises real interpolation for a fleeing soldier")
	check_panic_pose(replica.marches, displayed, 0, "replica panic mark follows corrected display position")
	reader.present(replica, state, 0.1)
	check_panic_pose(replica.marches, displayed, 0, "replica panic mark keeps following between snapshots")
	game.marches.clear()
	reader.install(replica, writer.capture(game, 6))
	check(panic_marks(replica.marches).visible_instance_count == 0, "authoritative march removal clears replica panic marks")
	await replica.prepare_shutdown()
	replica.queue_free()
	await process_frame

func _ai_checks() -> void:
	for index: int in 4:
		reset()
		game.elapsed = 10
		game.faction_skills[1].cooldowns.fill(999.0)
		game.faction_skills[1].cooldowns[index] = 0
		game.by_id[0].level = 4
		game.by_id[0].population = 80
		if index == 1: game.morale.adjust(0, 1000)
		if index == 2:
			for i: int in 12: soldier(0, Vector3((i % 4) * 0.4, 0, (i / 4) * 0.4), 1)
		if index == 3:
			game.by_id[2].faction = 0
			for i: int in 12:
				var at: Vector3 = game.by_id[0].global_position + Vector3(5, 0, i * 0.07)
				game.marches.send(1, 0, 1, 1, PackedVector3Array([at, game.by_id[0].global_position]))
		var policy := AI.new(1)
		policy.take_turn(game)
		check(game.faction_skills[1].cooldowns[index] > 0, "AI casts fox %d" % index)
		near(game.faction_skills[1].energy, 100 - RULES.FOX_COSTS[index], "AI pays fox %d" % index)
