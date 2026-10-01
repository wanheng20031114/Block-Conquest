extends SceneTree
## CPU attribution of a real single-player battle, not rendered FPS/GPU time.
## Run variants serially through tools/profile_block_war_singleplayer.py.
const BATTLE := preload("res://scenes/block_war/block_war.tscn")
const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const SNAPSHOT := preload("res://scripts/network/war_snapshot.gd")
const STEP := 1.0 / 60.0
const BASELINE_ZONE_BODY_SHA256 := "153ba6819cb87d922af7d88356e1af2b186e30dcca6a44e83029b56570c49c63"
const AI_DETAIL_STAGES: Array[String] = ["ai_strategy", "ai_conquest", "ai_tower_losses", "ai_reinforce", "ai_development", "ai_enemy_distance", "ai_skills", "ai_haste_target", "ai_fire_target", "ai_pig_turn", "ai_fox_turn", "ai_frog_turn", "ai_bear_turn", "ai_rabbit_turn"]

class ProfileSkills extends "res://scripts/block_war/war_ai_skills.gd":
	var metrics := {"ai_skills_us": 0, "ai_skills_calls": 0,
		"ai_haste_target_us": 0, "ai_haste_target_calls": 0,
		"ai_fire_target_us": 0, "ai_fire_target_calls": 0,
		"ai_pig_turn_us": 0, "ai_pig_turn_calls": 0,
		"ai_fox_turn_us": 0, "ai_fox_turn_calls": 0,
		"ai_frog_turn_us": 0, "ai_frog_turn_calls": 0,
		"ai_bear_turn_us": 0, "ai_bear_turn_calls": 0,
		"ai_rabbit_turn_us": 0, "ai_rabbit_turn_calls": 0}

	func _init(controlled_faction: int) -> void:
		super(controlled_faction)

	func reset_profile() -> void:
		for field: String in metrics: metrics[field] = 0

	func _record(stage: String, begun: int) -> void:
		metrics[stage + "_us"] += Time.get_ticks_usec() - begun
		metrics[stage + "_calls"] += 1

	func take_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super.take_turn(game)
		_record("ai_skills", begun)

	func _haste_target(game: Node3D, visible: Array[WarMarches.MarchUnit], radius: float = SKILL_RULES.HASTE_RADIUS, minimum: int = 16) -> Dictionary:
		var begun := Time.get_ticks_usec()
		var result: Dictionary = super._haste_target(game, visible, radius, minimum)
		_record("ai_haste_target", begun)
		return result

	func _fire_target(game: Node3D, visible: Array[WarMarches.MarchUnit]) -> Dictionary:
		var begun := Time.get_ticks_usec()
		var result: Dictionary = super._fire_target(game, visible)
		_record("ai_fire_target", begun)
		return result

	func _pig_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super._pig_turn(game)
		_record("ai_pig_turn", begun)

	func _fox_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super._fox_turn(game)
		_record("ai_fox_turn", begun)

	func _frog_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super._frog_turn(game)
		_record("ai_frog_turn", begun)

	func _bear_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super._bear_turn(game)
		_record("ai_bear_turn", begun)

	func _rabbit_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super._rabbit_turn(game)
		_record("ai_rabbit_turn", begun)

class ProfileStrategy extends "res://scripts/block_war/war_ai.gd":
	var metrics := {"ai_strategy_us": 0, "ai_strategy_calls": 0,
		"ai_conquest_us": 0, "ai_conquest_calls": 0,
		"ai_tower_losses_us": 0, "ai_tower_losses_calls": 0,
		"ai_reinforce_us": 0, "ai_reinforce_calls": 0,
		"ai_development_us": 0, "ai_development_calls": 0,
		"ai_enemy_distance_us": 0, "ai_enemy_distance_calls": 0}

	func _init(controlled_faction: int = 1) -> void:
		super(controlled_faction)
		_skills = ProfileSkills.new(controlled_faction)

	func reset_profile() -> void:
		for field: String in metrics: metrics[field] = 0
		(_skills as ProfileSkills).reset_profile()

	func _record(stage: String, begun: int) -> void:
		metrics[stage + "_us"] += Time.get_ticks_usec() - begun
		metrics[stage + "_calls"] += 1

	func take_turn(game: Node3D) -> void:
		var begun := Time.get_ticks_usec()
		super.take_turn(game)
		_record("ai_strategy", begun)

	func _conquest(game: Node3D, neutral: bool) -> Dictionary:
		var begun := Time.get_ticks_usec()
		var result: Dictionary = super._conquest(game, neutral)
		_record("ai_conquest", begun)
		return result

	func _tower_losses(game: Node3D, source: WarBuilding, target: WarBuilding, count: int) -> float:
		var begun := Time.get_ticks_usec()
		var result: float = super._tower_losses(game, source, target, count)
		_record("ai_tower_losses", begun)
		return result

	func _reinforce(game: Node3D) -> bool:
		var begun := Time.get_ticks_usec()
		var result: bool = super._reinforce(game)
		_record("ai_reinforce", begun)
		return result

	func _development(game: Node3D, homes: int, constructing: int) -> Dictionary:
		var begun := Time.get_ticks_usec()
		var result: Dictionary = super._development(game, homes, constructing)
		_record("ai_development", begun)
		return result

	func _enemy_distance(game: Node3D, source: WarBuilding) -> float:
		var begun := Time.get_ticks_usec()
		var result: float = super._enemy_distance(game, source)
		_record("ai_enemy_distance", begun)
		return result

class ProfileGame extends "res://scripts/block_war/block_war.gd":
	var profile_enabled := false
	var simulate_us := 0
	var simulate_calls := 0
	var substep_us := 0
	var substep_calls := 0
	var tower_us := 0
	var tower_calls := 0
	var ai_us := 0
	var ai_calls := 0
	var hud_us := 0
	var hud_calls := 0
	var combat_multiplier_calls := 0

	func reset_profile() -> void:
		simulate_us = 0
		simulate_calls = 0
		substep_us = 0
		substep_calls = 0
		tower_us = 0
		tower_calls = 0
		ai_us = 0
		ai_calls = 0
		hud_us = 0
		hud_calls = 0
		combat_multiplier_calls = 0

	func simulate(delta: float) -> void:
		if not profile_enabled:
			super.simulate(delta)
			return
		var begun := Time.get_ticks_usec()
		super.simulate(delta)
		simulate_us += Time.get_ticks_usec() - begun
		simulate_calls += 1

	func _simulate_step(delta: float) -> void:
		if not profile_enabled:
			super._simulate_step(delta)
			return
		var begun := Time.get_ticks_usec()
		super._simulate_step(delta)
		substep_us += Time.get_ticks_usec() - begun
		substep_calls += 1

	func _fire_tower(building: Node3D) -> void:
		if not profile_enabled:
			super._fire_tower(building)
			return
		var begun := Time.get_ticks_usec()
		super._fire_tower(building)
		tower_us += Time.get_ticks_usec() - begun
		tower_calls += 1

	func _ai_turn() -> void:
		if not profile_enabled:
			super._ai_turn()
			return
		var begun := Time.get_ticks_usec()
		super._ai_turn()
		ai_us += Time.get_ticks_usec() - begun
		ai_calls += 1

	func update_hud() -> void:
		if not profile_enabled:
			super.update_hud()
			return
		var begun := Time.get_ticks_usec()
		super.update_hud()
		hud_us += Time.get_ticks_usec() - begun
		hud_calls += 1

class ProfileMarches extends WarMarches:
	var profile_enabled := false
	var baseline_targeting := false
	var baseline_zone_geometry := false
	var tick_us := 0
	var tick_calls := 0
	var target_us := 0
	var target_calls := 0
	var selected_targets := 0
	var render_us := 0
	var render_calls := 0
	var render_submissions := 0
	var zone_us := 0
	var zone_calls := 0
	var zone_sample_segments := 0
	var new_haste_zones := 0
	var movement_distance_calls := 0

	func reset_profile() -> void:
		tick_us = 0
		tick_calls = 0
		target_us = 0
		target_calls = 0
		selected_targets = 0
		render_us = 0
		render_calls = 0
		render_submissions = 0
		zone_us = 0
		zone_calls = 0
		zone_sample_segments = 0
		new_haste_zones = 0
		movement_distance_calls = 0

	func _zone_intervals(order: MarchOrder, lane: float, zone: Dictionary) -> PackedVector2Array:
		if not profile_enabled:
			if baseline_zone_geometry: return _baseline_zone_intervals(order, lane, zone)
			return super._zone_intervals(order, lane, zone)
		var begun := Time.get_ticks_usec()
		var result: PackedVector2Array
		if baseline_zone_geometry:
			result = _baseline_zone_intervals(order, lane, zone)
		else:
			result = super._zone_intervals(order, lane, zone)
		zone_us += Time.get_ticks_usec() - begun
		zone_calls += 1
		# Geometric segment count, not a count of cache misses or pose evaluations.
		zone_sample_segments += ceili(order.length / 0.24)
		return result

	# Frozen from ReferenceMarches._zone_intervals in the zone geometry test.
	# Keep the exact body; no SceneTree test script is loaded as a dependency.
	func _baseline_zone_intervals(order: MarchOrder, lane: float, zone: Dictionary) -> PackedVector2Array:
		var intervals := PackedVector2Array()
		var center := Vector2(zone.at.x, zone.at.z)
		var count := ceili(order.length / 0.24)
		var from := order.sample(0.0)
		for index: int in count:
			var low := order.length * float(index) / count
			var high := order.length * float(index + 1) / count
			var to := _formation_position(order, high, lane, _route_heading(order, high))
			var a := Vector2(from.x, from.z)
			var b := Vector2(to.x, to.z)
			var start := 0.0 if a.distance_to(center) <= zone.radius else Geometry2D.segment_intersects_circle(a, b, center, zone.radius)
			if start >= 0.0:
				var end := 1.0 if b.distance_to(center) <= zone.radius else 1.0 - Geometry2D.segment_intersects_circle(b, a, center, zone.radius)
				var span := Vector2(lerpf(low, high, start), lerpf(low, high, end))
				if span.y > span.x:
					if not intervals.is_empty() and absf(intervals[-1].y - span.x) < 0.00001:
						intervals[-1] = Vector2(intervals[-1].x, span.y)
					else:
						intervals.append(span)
			from = to
		return intervals

	func create_haste_zone(faction: int, at: Vector3, radius: float, duration: float, multiplier: float, style: StringName = &"squirrel") -> void:
		super.create_haste_zone(faction, at, radius, duration, multiplier, style)
		if profile_enabled: new_haste_zones += 1

	func tick(delta: float, fire_segments: Array[Dictionary] = [], defer_mist_expiry: bool = false) -> void:
		if not profile_enabled:
			super.tick(delta, fire_segments, defer_mist_expiry)
			return
		var begun := Time.get_ticks_usec()
		super.tick(delta, fire_segments, defer_mist_expiry)
		tick_us += Time.get_ticks_usec() - begun
		tick_calls += 1

	func acquire_targets(center: Vector3, attacking_faction: int, radius: float, count: int, farthest: bool = false, tower_shot: bool = false) -> Array[MarchUnit]:
		var begun := Time.get_ticks_usec()
		var result: Array[MarchUnit]
		if baseline_targeting:
			result = _baseline_acquire_targets(center, attacking_faction, radius, count, farthest, tower_shot)
		else:
			result = super.acquire_targets(center, attacking_faction, radius, count, farthest, tower_shot)
		if profile_enabled:
			target_us += Time.get_ticks_usec() - begun
			target_calls += 1
			selected_targets += result.size()
		return result

	# The old production method, unchanged apart from its name/indentation.
	# Keep this body fixed: the runner records its independent SHA-256.
	func _baseline_acquire_targets(center: Vector3, attacking_faction: int, radius: float, count: int, farthest: bool = false, tower_shot: bool = false) -> Array[MarchUnit]:
		var targets: Array[MarchUnit] = []
		var radius_squared := radius * radius
		for target_index: int in count:
			var nearest := -1
			var nearest_distance := -1.0 if farthest else radius_squared
			for index: int in _units.size():
				var unit := _units[index]
				if FACTIONS.allied(unit.order.faction, attacking_faction) or not unit.is_exposed() or unit.reserved:
					continue
				if tower_shot and not tower_can_target(unit):
					continue
				var distance_squared := Vector2(unit.position.x - center.x, unit.position.z - center.z).length_squared()
				if distance_squared <= radius_squared and ((farthest and distance_squared > nearest_distance) or (not farthest and distance_squared <= nearest_distance)):
					nearest_distance = distance_squared
					nearest = index
			if nearest < 0:
				break
			_units[nearest].reserved = true
			_units[nearest].intercepted_by = attacking_faction
			targets.append(_units[nearest])
		return targets

	func _render() -> void:
		if not profile_enabled:
			super._render()
			return
		var submission := _render_batch_depth == 0
		var begun := Time.get_ticks_usec()
		super._render()
		render_us += Time.get_ticks_usec() - begun
		render_calls += 1
		render_submissions += int(submission)

# These per-soldier overrides exist only when detailed attribution is requested.
# Count calls without per-call clocks; normal A/B runs use the classes above.
class DetailedProfileGame extends ProfileGame:
	func combat_multiplier(faction: int, target: Node3D, unit_attack_bonus: float = 0.0) -> float:
		if profile_enabled: combat_multiplier_calls += 1
		return super.combat_multiplier(faction, target, unit_attack_bonus)

class DetailedProfileMarches extends ProfileMarches:
	func movement_distance(unit: MarchUnit, delta: float) -> float:
		if profile_enabled: movement_distance_calls += 1
		return super.movement_distance(unit, delta)

class BaselineInformationGame extends ProfileGame:
	var reference_strategies: Array[RefCounted] = []

	func _ai_turn() -> void:
		# The authored primary alias is typed to the production strategy script.
		# Independent generated scripts use this offline-only list, in the exact
		# native primary-then-other order, and the shared snapshot dictionary.
		var begun := Time.get_ticks_usec()
		if is_authority() and not is_rule_paused():
			for strategy: RefCounted in reference_strategies:
				strategy.take_turn(self)
		if profile_enabled:
			ai_us += Time.get_ticks_usec() - begun
			ai_calls += 1

class DetailedBaselineInformationGame extends BaselineInformationGame:
	func combat_multiplier(faction: int, target: Node3D, unit_attack_bonus: float = 0.0) -> float:
		if profile_enabled: combat_multiplier_calls += 1
		return super.combat_multiplier(faction, target, unit_attack_bonus)

var sample_frames := 3000
var initial_population := 1800
var fixed_seed := 20260930
var map_id := "islands"
var baseline_targeting := false
var detailed_ai := false
var front_towers := false
var baseline_ai_information := false
var baseline_zone_geometry := false
var ai_strategy_script := ""
var ai_commander := "squirrel"
var variant_label := ""
var ai_decision_checkpoints := false
var ai_checkpoints: Array[Dictionary] = []
var ai_probes: Array[RefCounted] = []
var output_directory := "res://.local/singleplayer-profile/manual"
var top_count := 20
var game: ProfileGame
var march_probe: ProfileMarches
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL SINGLEPLAYER_PROFILE ", message)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): sample_frames = int(argument.get_slice("=", 1))
		elif argument.begins_with("--population="): initial_population = int(argument.get_slice("=", 1))
		elif argument.begins_with("--seed="): fixed_seed = int(argument.get_slice("=", 1))
		elif argument.begins_with("--map="): map_id = argument.get_slice("=", 1)
		elif argument.begins_with("--baseline-targeting="): baseline_targeting = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--detailed-ai="): detailed_ai = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--front-towers="): front_towers = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--baseline-ai-information="): baseline_ai_information = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--baseline-zone-geometry="): baseline_zone_geometry = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--ai-strategy-script="): ai_strategy_script = argument.trim_prefix("--ai-strategy-script=")
		elif argument.begins_with("--ai-commander="): ai_commander = argument.get_slice("=", 1)
		elif argument.begins_with("--variant="): variant_label = argument.get_slice("=", 1)
		elif argument.begins_with("--ai-decision-checkpoints="): ai_decision_checkpoints = argument.get_slice("=", 1) == "true"
		elif argument.begins_with("--out="): output_directory = argument.trim_prefix("--out=")
		elif argument.begins_with("--top="): top_count = int(argument.get_slice("=", 1))
	var definition: Resource = CATALOG.find_map(map_id)
	if variant_label.is_empty(): variant_label = "baseline" if baseline_targeting else "candidate"
	if ai_commander not in ["squirrel", "pig", "fox", "frog", "bear", "rabbit"] or variant_label not in ["baseline", "candidate"]:
		printerr("FAIL SINGLEPLAYER_PROFILE invalid commander or variant")
		quit(2)
		return
	if detailed_ai and baseline_ai_information:
		printerr("FAIL SINGLEPLAYER_PROFILE detailed AI cannot be combined with generated information reference")
		quit(2)
		return
	if sample_frames < 1 or sample_frames > 36000 or initial_population < 600 or initial_population > 16384 or top_count < 1 or top_count > 200 or definition == null or definition.team_size != 3:
		printerr("FAIL SINGLEPLAYER_PROFILE invalid arguments; require a six-faction map, 1..36000 frames and 600..16384 population")
		quit(2)
		return
	output_directory = ProjectSettings.globalize_path(output_directory)
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		printerr("FAIL SINGLEPLAYER_PROFILE could not create output directory")
		quit(2)
		return
	var session: Node = root.get_node("Session")
	check(session.get_node("Online").match_config.is_empty(), "probe starts offline")
	if not failures.is_empty():
		quit(1)
		return
	session.block_war_map_id = map_id
	session.block_war_commander = &"pig"
	session.block_war_opponent_commander = StringName(ai_commander)
	seed(fixed_seed)
	var instance: Node3D = BATTLE.instantiate()
	# Keep every authored native child and canonical WarMarches nested type.
	# Instrumentation is installed before either script runs _enter_tree/_ready.
	if not ai_strategy_script.is_empty():
		instance.set_script(DetailedBaselineInformationGame if detailed_ai else BaselineInformationGame)
	else:
		instance.set_script(BaselineInformationGame if baseline_ai_information else (DetailedProfileGame if detailed_ai else ProfileGame))
	instance.get_node("Marches").set_script(DetailedProfileMarches if detailed_ai else ProfileMarches)
	game = instance as ProfileGame
	march_probe = instance.get_node("Marches") as ProfileMarches
	march_probe.baseline_targeting = baseline_targeting
	march_probe.baseline_zone_geometry = baseline_zone_geometry
	game.get_node("Audio").muted = true
	root.add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.audio.muted = true
	game.ai_enabled = true
	for faction: int in game.faction_count:
		game.faction_skills[faction].commander = &"pig" if faction == 0 else StringName(ai_commander)
	if not ai_strategy_script.is_empty():
		_install_ai_script(ai_strategy_script)
	elif baseline_ai_information:
		_install_ai_script("res://.local/singleplayer-reference/war_ai.gd")
	elif detailed_ai:
		_install_ai_probes()
	var fixture: Dictionary = _prepare_fixture()
	check(game.faction_count == 6 and game._bot_factions == [1, 2, 3, 4, 5], "one human and five actual native AI seats")
	check(game.match_config.is_empty() and game.network_match == null, "no network coordinator participates")
	check(fixture.population.total == initial_population, "starting total counts reserved soldiers exactly once")
	check(fixture.dispatched > 0 and fixture.population.pending > 0, "real issue_order creates paid departure reservations")
	var initial_hashes: Dictionary = _save_state("initial", 0)
	print("SINGLEPLAYER_PROFILE_CONTRACT ", JSON.stringify({
		"engine": Engine.get_version_info().string, "display": DisplayServer.get_name(),
		"variant": variant_label, "map": map_id, "detailed_ai": detailed_ai, "front_towers": front_towers,
		"baseline_targeting": baseline_targeting, "ai_strategy_script": ai_strategy_script,
		"ai_commander": ai_commander,
		"ai_decision_checkpoints": ai_decision_checkpoints,
		"baseline_ai_information": baseline_ai_information,
		"baseline_zone_geometry": baseline_zone_geometry, "baseline_zone_body_sha256": BASELINE_ZONE_BODY_SHA256,
		"map_title": definition.title, "seed": fixed_seed, "frames": sample_frames, "step": STEP,
		"start_elapsed": game.elapsed, "population_requested": initial_population, "fixture": fixture,
		"commanders": ["pig", ai_commander, ai_commander, ai_commander, ai_commander, ai_commander],
		"limits": ["CPU method attribution with nested inclusive timers; do not sum parent and child stages",
			"No wall-clock pacing, renderer frame waits, GPU timing or FPS claim",
			"Synthetic midgame ownership/population on unchanged authored geometry, not a reconstruction of a screenshot save",
			"One nearest-enemy house per faction becomes a level-3 frontline tower" if front_towers else "All building kinds preserved; houses/towers start at level 3",
			"No artificial soldier positioning or repeated routes; converted tower IDs and real route distances are recorded in the fixture",
			"Call the real _process at fixed 1/60 to retain native 0.1-second HUD cadence and five AI decisions",
			"Reference variants independently opt into frozen acquire_targets, incoming_damage and _zone_intervals; all other helpers use current source",
			"Setup/hash/counting/JSON output excluded from frame timing",
			"Optional AI checkpoints capture each decision frame after _process returns, outside all measured timings",
			"Reference/candidate execute in separate serial processes; no concurrent benchmark load",
			"_render requests include deferred batch calls; render_submissions counts calls at batch depth zero",
			"Optional detailed_ai replaces the five strategies/skills with super-only timing wrappers; nested times include instrumentation overhead",
			"Detailed combat_multiplier/movement_distance metrics count all controller calls without per-soldier timing; counters are diagnostic, not rule hashes"]}))
	if not failures.is_empty():
		await _finish()
		return
	game.profile_enabled = true
	march_probe.profile_enabled = true
	for frame: int in sample_frames:
		game.reset_profile()
		march_probe.reset_profile()
		for strategy: RefCounted in ai_probes: strategy.reset_profile()
		var before: Dictionary = _population()
		var begun := Time.get_ticks_usec()
		game._process(STEP)
		var frame_us := Time.get_ticks_usec() - begun
		var after: Dictionary = _population()
		var row := {"frame": frame, "elapsed": game.elapsed, "frame_us": frame_us,
			"simulate_us": game.simulate_us, "simulate_calls": game.simulate_calls,
			"substep_us": game.substep_us, "substep_calls": game.substep_calls,
			"tower_us": game.tower_us, "tower_calls": game.tower_calls,
			"target_us": march_probe.target_us, "target_calls": march_probe.target_calls,
			"selected_targets": march_probe.selected_targets,
			"march_tick_us": march_probe.tick_us, "march_tick_calls": march_probe.tick_calls,
			"render_us": march_probe.render_us, "render_calls": march_probe.render_calls,
			"render_submissions": march_probe.render_submissions,
			"zone_us": march_probe.zone_us, "zone_calls": march_probe.zone_calls,
			"zone_sample_segments": march_probe.zone_sample_segments,
			"new_haste_zones": march_probe.new_haste_zones,
			"ai_us": game.ai_us, "ai_calls": game.ai_calls,
			"hud_us": game.hud_us, "hud_calls": game.hud_calls,
			"before": before, "after": after,
			"tower_projectiles": game.projectiles.size(), "orb_projectiles": game.bear.shots.size(),
			"weak_fields": march_probe.weak_zones.size(), "haste_fields": march_probe.haste_zones.size(),
			"fire_fields": game.fire_states.size(), "finished": game.finished}
		if detailed_ai: _append_ai_metrics(row)
		rows.append(row)
		if ai_decision_checkpoints and game.ai_calls > 0:
			ai_checkpoints.append({"frame": frame, "elapsed": game.elapsed, "ai_calls": game.ai_calls,
				"hashes": _save_state("ai-decision-%06d" % frame, frame + 1)})
		if game.finished:
			break
	game.profile_enabled = false
	march_probe.profile_enabled = false
	check(rows.size() == sample_frames, "battle remains active for the entire requested sample")
	if front_towers and sample_frames >= 3000:
		var fired := false
		for row: Dictionary in rows:
			fired = fired or (row.selected_targets > 0 and row.tower_projectiles > 0)
		check(fired, "front-tower long sample includes real tower target acquisition and projectiles")
	var final_hashes: Dictionary = _save_state("final", rows.size())
	var trace := FileAccess.open(output_directory.path_join("frames.jsonl"), FileAccess.WRITE)
	check(trace != null, "raw frame trace opens")
	if trace != null:
		for row: Dictionary in rows: trace.store_line(JSON.stringify(row, "", true, true))
		trace.close()
	var result := {"variant": variant_label, "map": map_id, "detailed_ai": detailed_ai, "front_towers": front_towers,
		"baseline_targeting": baseline_targeting, "ai_strategy_script": ai_strategy_script,
		"ai_commander": ai_commander,
		"ai_decision_checkpoints": ai_decision_checkpoints, "ai_checkpoints": ai_checkpoints,
		"baseline_ai_information": baseline_ai_information,
		"baseline_zone_geometry": baseline_zone_geometry, "baseline_zone_body_sha256": BASELINE_ZONE_BODY_SHA256,
		"seed": fixed_seed, "frames": rows.size(), "step": STEP, "start_elapsed": 100.0,
		"end_elapsed": game.elapsed, "initial_hashes": initial_hashes, "final_hashes": final_hashes,
		"initial_population": fixture.population, "final_population": _population(),
		"statistics": _statistics(), "top_peaks": _top_peaks(), "checks": checks,
		"failures": failures, "output_directory": output_directory}
	_write_json("summary.json", result)
	print("SINGLEPLAYER_PROFILE_RESULT ", JSON.stringify(result, "", true, true))
	await _finish()

func _install_ai_script(path: String) -> void:
	var reference_script: Script = load(path)
	check(reference_script != null, "generated AI information reference loads")
	if reference_script == null: return
	var reference_game := game as BaselineInformationGame
	game._other_ai.clear()
	for faction: int in game._bot_factions:
		var original: RefCounted = game._ai_by_faction[faction]
		var strategy: RefCounted = reference_script.new(faction)
		strategy._next_attack_at = original._next_attack_at
		strategy._next_expansion_at = original._next_expansion_at
		strategy._economy = original._economy
		strategy._reserves = original._reserves
		strategy._tower_exposure = original._tower_exposure
		strategy._incoming_teams = original._incoming_teams
		strategy._departure_delays = original._departure_delays
		strategy._skills.next_decision = original._skills.next_decision
		game._ai_by_faction[faction] = strategy
		reference_game.reference_strategies.append(strategy)
		if faction != 1: game._other_ai.append(strategy)
		if detailed_ai: ai_probes.append(strategy)
	check(reference_game.reference_strategies.size() == 5 and game._other_ai.size() == 4,
		"five generated reference AI seats retain native turn order")
	for index: int in reference_game.reference_strategies.size():
		var strategy: RefCounted = reference_game.reference_strategies[index]
		check(strategy.faction == game._bot_factions[index] and strategy == game._ai_by_faction[strategy.faction],
			"generated reference decision and snapshot aliases agree " + str(strategy.faction))

func _install_ai_probes() -> void:
	# Install before fixture setup or any decision, retaining every native rule
	# field and the economy instance rather than restarting its observation state.
	game._other_ai.clear()
	for faction: int in game._bot_factions:
		var original: RefCounted = game._ai_by_faction[faction]
		var strategy := ProfileStrategy.new(faction)
		strategy._next_attack_at = original._next_attack_at
		strategy._next_expansion_at = original._next_expansion_at
		strategy._economy = original._economy
		strategy._reserves = original._reserves
		strategy._tower_exposure = original._tower_exposure
		strategy._incoming_teams = original._incoming_teams
		strategy._departure_delays = original._departure_delays
		strategy._skills.next_decision = original._skills.next_decision
		game._ai_by_faction[faction] = strategy
		if faction == 1:
			game._ai_strategy = strategy
		else:
			game._other_ai.append(strategy)
		ai_probes.append(strategy)
	check(ai_probes.size() == 5 and game._other_ai.size() == 4, "five detailed AI wrappers installed")
	check(game._ai_strategy == game._ai_by_faction[1], "primary AI alias uses detailed strategy")
	for strategy: RefCounted in game._other_ai:
		check(strategy == game._ai_by_faction[strategy.faction] and strategy is ProfileStrategy,
			"secondary AI alias uses detailed strategy " + str(strategy.faction))

func _append_ai_metrics(row: Dictionary) -> void:
	for stage: String in AI_DETAIL_STAGES:
		row[stage + "_us"] = 0
		row[stage + "_calls"] = 0
	var factions: Dictionary = {}
	for strategy: RefCounted in ai_probes:
		var values: Dictionary = strategy.metrics.duplicate()
		values.merge(strategy._skills.metrics)
		for field: String in values:
			row[field] += values[field]
		factions[str(strategy.faction)] = values
	row["ai_by_faction"] = factions
	row["combat_multiplier_calls"] = game.combat_multiplier_calls
	row["movement_distance_calls"] = march_probe.movement_distance_calls

func _prepare_fixture() -> Dictionary:
	var homes: Array[WarBuilding] = []
	for faction: int in game.faction_count:
		for building: WarBuilding in game.buildings:
			if building.faction == faction:
				homes.append(building)
				break
	assert(homes.size() == 6)
	# Assign the native structures to the closest authored starting seat. Exact
	# ties alternate by building id so the centre does not all belong to one side.
	var owned: Array = [[], [], [], [], [], []]
	for building: WarBuilding in game.buildings:
		var closest := INF
		var candidates: Array[int] = []
		for faction: int in game.faction_count:
			var squared := building.position.distance_squared_to(homes[faction].position)
			if squared < closest:
				closest = squared
				candidates.assign([faction])
			elif squared == closest:
				candidates.append(faction)
		building.faction = candidates[building.building_id % candidates.size()]
		building.level = 3 if building.kind in [0, 1] else 1
		owned[building.faction].append(building)
	var conversions: Array[Dictionary] = _prepare_front_towers(owned) if front_towers else []
	for faction: int in game.faction_count:
		var budget := initial_population / 6 + int(faction < initial_population % 6)
		var group: Array = owned[faction]
		assert(not group.is_empty())
		for index: int in group.size():
			var building: WarBuilding = group[index]
			building.population = budget / group.size() + int(index < budget % group.size())
			building.refresh_visual()
		game.faction_skills[faction].energy = 75.0
	game.elapsed = 100.0
	game.ai_clock = 0.0
	game._hud_clock = 0.0
	game.sync_environment_bonuses()
	var dispatched := 0
	var dispatches: Array[Dictionary] = []
	for source: WarBuilding in game.buildings:
		if source.kind != 0:
			continue
		var target: WarBuilding
		var closest := INF
		for candidate: WarBuilding in game.buildings:
			if not game.FACTIONS.hostile(source.faction, candidate.faction): continue
			var route: PackedVector3Array = game.map.get_building_route(source, candidate)
			if route.size() < 2: continue
			var distance: float = game.map.get_building_distance(source, candidate)
			if distance < closest:
				closest = distance
				target = candidate
		if target == null: continue
		var count: int = game.issue_order(source, target, 50, source.faction)
		dispatched += count
		dispatches.append({"source": source.building_id, "target": target.building_id,
			"faction": source.faction, "count": count, "route_length": closest})
	game.update_hud()
	return {"ownership": "closest authored start; exact ties by building id", "level": 3,
		"energy_each": 75.0, "dispatch_percent": 50, "dispatched": dispatched,
		"dispatches": dispatches, "population": _population(), "front_tower_conversions": conversions}

func _prepare_front_towers(owned: Array) -> Array[Dictionary]:
	var conversions: Array[Dictionary] = []
	for faction: int in game.faction_count:
		var selected: WarBuilding
		var enemy: WarBuilding
		var closest := INF
		for source: WarBuilding in owned[faction]:
			if source.kind != 0: continue
			for target: WarBuilding in game.buildings:
				if not game.FACTIONS.hostile(faction, target.faction): continue
				var route: PackedVector3Array = game.map.get_building_route(source, target)
				if route.size() < 2: continue
				var distance: float = game.map.get_building_distance(source, target)
				var stable_tie := distance == closest and selected != null and (source.building_id < selected.building_id or (source.building_id == selected.building_id and target.building_id < enemy.building_id))
				if distance < closest or stable_tie:
					selected = source
					enemy = target
					closest = distance
		check(selected != null, "reachable frontline house for faction " + str(faction))
		if selected == null: continue
		conversions.append({"building": selected.building_id, "faction": faction,
			"from_kind": selected.kind, "from_level": selected.level, "kind": 1, "level": 3,
			"nearest_enemy": enemy.building_id, "route_length": closest})
		selected.kind = 1
		selected.level = 3
		game.tower_clocks[selected.building_id] = 0.0
		selected.refresh_visual()
	check(conversions.size() == 6, "one frontline tower conversion per faction")
	return conversions

func _population() -> Dictionary:
	var total := 0.0
	var garrison := 0.0
	var available := 0.0
	var exposed := 0
	var pending := 0
	var reserved := 0
	for building: WarBuilding in game.buildings:
		if building.faction >= 0:
			garrison += building.population
			available += building.available_population
	for unit: WarMarches.MarchUnit in march_probe._units:
		exposed += int(unit.is_exposed())
		pending += int(unit.pending_departure)
		reserved += int(unit.reserved)
	total = available + march_probe._units.size()
	return {"total": total, "garrison_including_pending": garrison, "available_garrison": available,
		"march_records": march_probe._units.size(), "exposed": exposed, "pending": pending,
		"projectile_reserved": reserved}

func _save_state(label: String, frame: int) -> Dictionary:
	var state: Dictionary = SNAPSHOT.new().capture(game, frame)
	_write_json(label + "-snapshot.json", state)
	var units: Array = []
	for unit: WarMarches.MarchUnit in march_probe._units:
		units.append([unit.unit_id, unit.order.order_id, unit.alive, SNAPSHOT.v3(unit.position),
			SNAPSHOT.v3(unit.heading), unit.distance, unit.lane, unit.gait, unit.pending_departure,
			unit.spawn_delay, unit.rush_remaining, unit.levitation_remaining, unit.cloaked,
			unit.weakened, unit.reserved, unit.intercepted_by])
	var decisions: Array = []
	for faction: int in game._bot_factions:
		var strategy: RefCounted = game._ai_by_faction[faction]
		var economy: RefCounted = strategy._economy
		decisions.append([faction, strategy._next_attack_at, strategy._next_expansion_at,
			strategy._skills.next_decision, economy._observed_since, economy._last_observed_at,
			economy._last_energy_low, economy._low_energy_seconds, economy._recent_spending])
	var backbone := [state, units, decisions, game.ai_clock, game._hud_clock,
		march_probe._next_order_id, march_probe._next_unit_id, march_probe._departure_sequence]
	return {"snapshot_exact_sha256": _exact_hash(state), "snapshot_rule_sha256": SNAPSHOT.digest(state),
		"backbone_exact_sha256": _exact_hash(backbone)}

func _exact_hash(value: Variant) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(value))
	return digest.finish().hex_encode()

func _statistics() -> Dictionary:
	var result := {}
	var timings: Array[String] = ["frame_us", "simulate_us", "substep_us", "tower_us", "target_us", "march_tick_us", "render_us", "zone_us", "ai_us", "hud_us"]
	var counters: Array[String] = ["simulate_calls", "substep_calls", "tower_calls", "target_calls", "selected_targets", "march_tick_calls", "render_calls", "render_submissions", "zone_calls", "zone_sample_segments", "new_haste_zones", "ai_calls", "hud_calls"]
	if detailed_ai:
		for stage: String in AI_DETAIL_STAGES:
			timings.append(stage + "_us")
			counters.append(stage + "_calls")
		counters.append_array(["combat_multiplier_calls", "movement_distance_calls"])
	for field: String in timings:
		var values: Array[int] = []
		var total := 0
		for row: Dictionary in rows:
			var value := int(row[field])
			values.append(value)
			total += value
		values.sort()
		result[field] = {"total": total, "mean": float(total) / values.size(),
			"p50": values[ceili(values.size() * 0.50) - 1], "p95": values[ceili(values.size() * 0.95) - 1],
			"p99": values[ceili(values.size() * 0.99) - 1], "max": values[-1]}
	for field: String in counters:
		var total := 0
		for row: Dictionary in rows: total += int(row[field])
		result[field] = total
	return result

func _top_peaks() -> Dictionary:
	var result := {}
	var timings: Array[String] = ["frame_us", "simulate_us", "target_us", "march_tick_us", "zone_us", "ai_us", "hud_us"]
	if detailed_ai:
		for stage: String in AI_DETAIL_STAGES: timings.append(stage + "_us")
	for field: String in timings:
		var ranked: Array[Dictionary] = rows.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary):
			return a[field] > b[field] if a[field] != b[field] else a.frame < b.frame)
		result[field] = ranked.slice(0, mini(top_count, ranked.size()))
	return result

func _write_json(name: String, value: Variant) -> void:
	var output := FileAccess.open(output_directory.path_join(name), FileAccess.WRITE)
	check(output != null, "open " + name)
	if output != null:
		output.store_string(JSON.stringify(value, "\t", true, true) + "\n")
		output.close()

func _finish() -> void:
	game.profile_enabled = false
	march_probe.profile_enabled = false
	# Flush native audio playback and queued Music disposal before releasing the
	# authored scene. This happens after snapshots/timings have been saved.
	await game.prepare_shutdown()
	if game is BaselineInformationGame:
		(game as BaselineInformationGame).reference_strategies.clear()
	ai_probes.clear()
	game._ai_by_faction.clear()
	game._other_ai.clear()
	game.free()
	game = null
	march_probe = null
	rows.clear()
	# Allow deferred rendering/Tween disposal to release scene/script resources.
	await process_frame
	print("SINGLEPLAYER_PROFILE_CHECKS checks=", checks, " failures=", failures.size())
	# The bounded parent process verifies process exit and every diagnostic.
	quit(0 if failures.is_empty() else 1)
