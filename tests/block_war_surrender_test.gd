extends "res://tests/block_war_multiplayer_core_test.gd"
const Codec := preload("res://scripts/network/war_snapshot.gd")

func config() -> Dictionary:
	var value := super.config()
	value.match_id = "surrender-rules"
	for slot: Dictionary in value.slots:
		slot.kind = "bot" if slot.faction_id == 3 else "human"
		slot.controller = slot.kind
		slot.player_id = 100 + slot.faction_id if slot.kind == "human" else -1
		slot.connected = true
	return value

func clean() -> void:
	super.clean()
	game.match_paused = false
	game.pause_faction = -1
	game.surrendered_factions.clear()
	game.initial_human_factions.clear()
	game.configure_match(config(), 105)
	game.winner_team = -2
	game.bear.links.clear(); game.bear.wards.clear(); game.bear.damage_remainders.clear()
	game.shields.clear(); game.fire_states.clear()
	for state: RefCounted in game.faction_skills:
		state.recruit_target_id = -1; state.durations.fill(0.0)
	game.sync_match_control_presentation()

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) < 0.000001, label)

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false); game.camera_rig.set_process(false); game.ai_enabled = false; game.audio.muted = true
	clean()
	_pause_rules()
	_transfer_rules()
	_recipient_rules()
	_spectator_rules()
	_victory_rules()
	await game.prepare_shutdown()
	game.sync_match_control_presentation()
	check(game._closing and game.audio._pools.is_empty(), "late transport pause after shutdown does not reopen disposed audio or visuals")
	print("SURRENDER_RULES checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _pause_rules() -> void:
	check(game.initial_human_factions == [0, 1, 2, 4, 5], "human identity comes from seat kind")
	check(not game.execute_network_command(3, {"type": "pause", "paused": true}).accepted, "computer cannot issue a human pause")
	check(not game.execute_network_command(0, {"type": "pause", "paused": 1}).accepted, "pause payload requires a real boolean")
	game.online_host = false
	check(not game.set_match_paused(true, 0).accepted and not game.surrender_faction(0).accepted, "replica cannot write pause or surrender")
	game.online_host = true
	game.simulation_paused = true
	check(not game.can_request_match_control(0) and not game.set_match_paused(true, 0).accepted and not game.surrender_faction(0).accepted, "transport recovery blocks match controls before authoritative execution")
	game.simulation_paused = false
	game.drag_source = game.by_id[5]; game.armed_skill = 1; game.camera_rig.dragging = true
	check(game.execute_network_command(0, {"type": "pause", "paused": true}).accepted, "any active human may pause")
	check(game.match_paused and game.pause_faction == 0 and game.is_rule_paused(), "global pause has a stable actor")
	check(game.drag_source == null and game.armed_skill == -1 and not game.camera_rig.dragging, "global pause cancels every local aim and drag")
	var elapsed: float = game.elapsed
	var population: float = game.by_id[0].population
	game.simulate(5.0)
	check(game.elapsed == elapsed and game.by_id[0].population == population, "pause halts authoritative time and production")
	check(not game.execute_network_command(0, {"type": "upgrade", "building": 0}).accepted, "battle command cannot spend during global pause")
	check(not game.set_match_paused(true, 1).changed and game.pause_faction == 0, "duplicate pause is idempotent and keeps original actor")
	game.set_paused(true)
	check(game.submit_player_command({"type": "pause", "paused": false}).accepted, "resume can be requested while local menu is open")
	check(not game.match_paused and game._local_menu and not game.is_rule_paused(), "resuming global pause does not close local menu or stop battle")
	check(game.set_match_paused(true, 0).accepted and game.set_match_paused(false, 1).accepted, "opposing active player may resume another player's pause")
	game.set_paused(false)
	game.simulate(0.1)
	check(game.elapsed > elapsed and game.pause_faction == -1, "simulation resumes with actor cleared")
	clean()

func _transfer_rules() -> void:
	seed(83091)
	var owned: Array[int] = [0, 6, 8, 10]
	for id: int in owned:
		game.by_id[id].faction = 0
		game.by_id[id].population = 70.5
	game.by_id[6].kind = 3
	game.by_id[8].kind = 1
	game.by_id[10].kind = 2
	game.by_id[10].begin_construction(3, 20)
	game.by_id[0].begin_disruption(4.0)
	game.by_id[6].begin_burrow(15.0)
	game.shields[0] = 7.0
	game.bear.links[0] = {"target": 0, "support": 6, "faction": 0, "remaining": 5.0, "settled": 21, "pulse": 0.0}
	game.bear.wards[8] = {"faction": 0, "remaining": 5.0, "shot_clock": 0.25, "pulse": 0.0}
	game.bear.damage_remainders[0] = 0.375
	game.faction_skills[0].recruit_target_id = 2
	game.faction_skills[0].durations.fill(5.0)
	game.faction_skills[4].recruit_target_id = 0
	game.faction_skills[4].durations[0] = 6.0
	game.faction_skills[2].energy = 44.0
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	game.marches.queue_tunnel_departure(0, 7, 0, 50, route, 0.16, 0.7)
	game.marches.send(6, 1, 0, 8, route, 0.75, true)
	var soldier: WarMarches.MarchUnit = game.marches._units[-1]
	soldier.distance = 12.0; soldier.rush_remaining = 4.0; soldier.cloaked = true; soldier.weakened = true; soldier.levitation_remaining = 0.2
	soldier.reserved = true; soldier.intercepted_by = 1
	game.marches._update_pose(soldier)
	var returning: WarMarches.MarchUnit = game.marches._units[-2]
	returning.distance = 10.0
	game.marches._update_pose(returning)
	game.marches.redirect(returning, game.marches.return_order(returning.order))
	game.marches.send(1, 0, 1, 1, route)
	var enemy: WarMarches.MarchUnit = game.marches._units[-1]
	enemy.reserved = true; enemy.intercepted_by = 0
	game.projectiles.append({"target": enemy, "at": Vector3(0, 2, 0), "position": Vector3.ZERO, "previous": Vector3.ZERO, "to": enemy.position, "tracking": true, "age": 0.0, "duration": 0.4})
	game.bear.shots.append({"target": soldier, "origin": Vector3(0, 2, 0), "position": Vector3.ZERO, "previous": Vector3.ZERO, "to": soldier.position, "age": 0.0, "duration": 0.4})
	game.marches.create_haste_zone(0, Vector3.ZERO, 4.0, 6.0, 1.6)
	game.marches.create_slow_zone(0, Vector3.ZERO, 4.0, 6.0)
	game.marches.apply_frog_field(0, 0, Vector3(10, 0, 10))
	var fire: RefCounted = game.start_fire(Vector3(20, 0, 20), 4.5, 0)
	fire.hit_buildings[7] = true
	var original_orders := {}
	var positions := {}
	var original_ids := {}
	for unit: WarMarches.MarchUnit in game.marches._units:
		original_ids[unit.unit_id] = true
		positions[unit.unit_id] = unit.position
		if unit.order.faction == 0 and not unit.pending_departure: original_orders[unit.unit_id] = unit.order.order_id
	var writer := Codec.new()
	var before := writer.capture(game, 1)
	var result: Dictionary = game.surrender_faction(0)
	check(result.accepted and not result.defeated and not game.finished, "partial surrender transfers and continues")
	check(result.transfer.cancelled_reservations == 8 and game.by_id[0].queued_population == 42, "garrison loss cancels exactly the newest eight unpaid reservations")
	for id: int in owned:
		check(game.by_id[id].faction in [2, 4], "building goes only to surviving human ally")
		near(game.by_id[id].population, 42.3, "every building's actual garrison loses exactly forty percent")
	check(game.by_id[10].is_constructing and game.by_id[10].conversion_target == 3 and game.by_id[10].construction_cost == 20, "paid energy-tower construction survives transfer")
	check(game.by_id[0].disruption_remaining == 4.0 and game.shields[0] == 7.0, "hostile disruption and attached shield persist")
	check(game.by_id[6].burrow_remaining == 0.0 and game.bear.links.is_empty() and game.bear.wards.is_empty(), "caster-bound building skills end without stale ownership")
	check(game.bear.damage_remainders.is_empty() and game.faction_skills[0].recruit_target_id == -1, "former bear debt and surrendered caster recruitment clear")
	check(game.faction_skills[4].recruit_target_id == 0 and game.faction_skills[2].energy == 44.0, "other teammates' skills and energy are not overwritten")
	check(not game.marches.haste_zones.has(0) and not game.marches.slow_zones.has(0) and not game.marches.weak_zones.has(0), "surrendered caster ground fields expire")
	check(fire.faction in [2, 4] and fire.hit_buildings.has(7), "in-flight fire retains hit ledger under allied credit")
	var group_owners := {}
	var hidden := 0
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(original_ids.has(unit.unit_id) and positions[unit.unit_id] == unit.position, "transfer keeps surviving soldier identities and world positions")
		check(unit.order.faction != 0, "no surrendered soldier remains controllable")
		if unit.pending_departure:
			hidden += 1
			check(unit.order.faction == game.by_id[unit.order.source_id].faction, "hidden reservation follows its building's new owner")
			check(unit.departure_sequence < 42, "newest queue entries are cancelled before older entries")
		if original_orders.has(unit.unit_id):
			var id: int = original_orders[unit.unit_id]
			check(unit.order.order_id != id and unit.order.faction in [2, 4], "moving army receives a new immutable order identity")
			if group_owners.has(id): check(group_owners[id] == unit.order.faction, "one original marching army is never split among recipients")
			else: group_owners[id] = unit.order.faction
	check(hidden == game.by_id[0].queued_population, "pending unit ledger equals displayed queue")
	check(soldier.reserved and soldier.intercepted_by == 1 and soldier.rush_remaining == 4.0 and soldier.cloaked and soldier.weakened and soldier.levitation_remaining == 0.2, "unit buffs and enemy projectile reservation survive transfer")
	check(soldier.order.energy_origin and soldier.order.strength == 0.75 and returning.order.returning, "energy provenance, attack strength and recall direction survive")
	check(game.projectiles[0].target == enemy and game.bear.shots[0].target == soldier and enemy.intercepted_by in [2, 4], "both projectile pools keep valid living object locks and legal credit")
	var tower_owner: int = game.by_id[6].faction
	check(game.energy_tower_count(0) == 0 and game.energy_tower_count(tower_owner) == 1, "energy-tower regeneration follows the new building owner")
	var after := writer.capture(game, 2)
	check(Codec.valid(after, game), "post-surrender complete snapshot preserves all cross references")
	Codec.apply_delta(before, Codec.diff(before, after))
	check(Codec.valid(before, game) and Codec.digest(before) == Codec.digest(after), "one reliable transaction carries all ownership and queue changes")
	var stable := Codec.digest(after)
	check(not game.surrender_faction(0).accepted and stable == Codec.digest(writer.capture(game, 2)), "replayed surrender cannot charge garrison loss twice")
	game.simulate(1.0)
	check(game.by_id[0].queued_population < 42 and game.by_id[0].available_population >= 0.0, "transferred tunnel queue can depart normally without negative garrison")
	clean()

func _recipient_rules() -> void:
	var slots: Array = config().slots
	slots[2].kind = "bot"; slots[2].controller = "bot"; slots[2].player_id = -1
	slots[4].controller = "bot"; slots[4].connected = false
	game.configure_controllers(slots)
	game.by_id[0].population = 70.5
	var route := PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)])
	game.marches.send(0, 1, 0, 8, route)
	check(game.surrender_faction(0).accepted and not game.finished, "temporarily disconnected human remains eligible during AI takeover")
	check(game.by_id[0].faction == 4 and game.by_id[2].population == 60.0, "former human permanently replaced by a bot cannot receive the building")
	for unit: WarMarches.MarchUnit in game.marches._units:
		check(unit.order.faction == 4, "transferred marching army belongs to the recoverable human identity")
	near(game.by_id[0].population, 42.3, "disconnect-aware recipient filtering preserves exact garrison loss")
	clean()
	slots = config().slots
	slots[2]["forfeit_requested"] = true
	slots[2].controller = "spectator"; slots[2].connected = false
	game.configure_controllers(slots)
	check(game.surrender_faction(0).accepted and game.by_id[0].faction == 4, "voluntary leaver awaiting Host settlement cannot receive another player's assets")
	check(game.surrender_faction(2).accepted and game.by_id[2].faction == 4, "Host can settle the voluntary leaver's own pending surrender")
	clean()

func _spectator_rules() -> void:
	check(game.surrender_faction(5).accepted and game.online_host and game.is_authority(), "Host surrender preserves simulation authority")
	check(game.has_surrendered(5) and not game.can_request_match_control(5), "Host becomes an observer without pause authority")
	check(not game.submit_player_command({"type": "pause", "paused": true}).accepted, "observer local controls cannot pause")
	check(not game.execute_network_command(5, {"type": "dispatch", "source": 5, "target": 7, "percent": 100}).accepted, "observer cannot dispatch via network executor")
	check(not game.can_cast_skill(0, 5) and not game.begin_building_construction(game.by_id[5], -1, 5), "observer cannot cast or buy construction")
	var slots: Array = config().slots
	slots[5].controller = "bot"
	game.configure_controllers(slots)
	check(5 not in game._bot_factions, "late room update cannot reactivate surrendered Host as AI")
	var at: float = game.elapsed
	game.simulate(0.1)
	check(game.elapsed > at and not game.finished, "surrendered Host continues hosting teammates' simulation")
	check(game.set_match_paused(true, 1).accepted and game.set_match_paused(false, 2).accepted, "remaining players retain pause and resume rights")
	clean()

func _victory_rules() -> void:
	check(game.surrender_faction(0).accepted and game.surrender_faction(2).accepted and not game.finished, "team remains alive with one initial human remaining")
	game.set_match_paused(true, 4)
	check(game.surrender_faction(4).defeated and game.finished and game.winner_team == 1, "last human surrender settles immediate defeat even while paused")
	check(not game.surrender_faction(4).accepted, "finished match rejects replayed surrender")
	clean()
	var bots_only_side := config()
	for slot: Dictionary in bots_only_side.slots:
		if slot.team_id == 0:
			slot.kind = "bot"; slot.controller = "bot"; slot.player_id = -1
	game.initial_human_factions.clear()
	game.configure_match(bots_only_side, 105)
	game._check_victory()
	check(not game.finished and not game.surrender_faction(0).accepted, "pure-computer team never loses merely for having no humans")
	check(game.surrender_faction(5).accepted and not game.finished, "allied computer does not count as an extra surrender vote")
	check(game.surrender_faction(1).defeated and game.winner_team == 0, "all initially-human teammates surrender while allied bot still has buildings")
