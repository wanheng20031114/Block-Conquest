extends SceneTree
## Wire round-trip of real tower scenes, without deploying a relay.
const FIXTURE = preload("res://tests/network_game_fixture.tscn")
const RELAY = preload("res://scripts/network/relay_client.tscn")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ", label)
func state_for(snapshot: Dictionary, id: int) -> Dictionary:
	for state: Dictionary in snapshot.entities:
		if int(state.id) == id: return state
	return {}
func wire(snapshot: Dictionary) -> Dictionary:
	return NetworkProtocol.decode(NetworkProtocol.encode({"op":"snapshot", "payload":snapshot})).payload

func _run() -> void:
	create_timer(25, true, false, true).timeout.connect(func(): quit(3))
	var host: Node3D = FIXTURE.instantiate()
	root.add_child(host)
	host.is_authority = true
	var relay: RelayClient = RELAY.instantiate()
	host.add_child(relay)
	var sender: MatchReplication = host.get_node("MatchReplication")
	sender.configure(host, relay)
	var tower: BattleBuilding = host.spawn_building("cannon_tower", 0, Vector3.ZERO)
	var hidden: BattleBuilding = host.spawn_building("cannon_tower", 2, Vector3(40,0,40))
	var ally: BattleBuilding = host.spawn_building("cannon_tower", 1, Vector3(9,0,0), true)
	var target: BattleUnit = host.spawn_unit("war_elephant", 2, Vector3(0,0,-10))
	host.visible_ids.append(target.entity_id)
	host.elapsed = 2
	tower.weapons[0].last_fired = 1.8
	tower.artillery.guns[0].turret.rotation.y = .7
	tower.artillery.guns[0].elevation.rotation.x = -.12
	ally.construction_progress = .5
	target.receive_hit(DamageResolver.snapshot(tower._stats, 0, 0, 0), tower)
	var snapshot := wire(sender.build_snapshot(0))
	check(NetworkProtocol.VERSION == 18, "building battery contract increments protocol")
	check(state_for(snapshot, tower.entity_id).turrets[0].fired == 1.8, "release timestamp encoded without target identity")
	check(state_for(snapshot, hidden.entity_id).is_empty(), "hidden enemy tower is omitted")
	check(not state_for(snapshot, ally.entity_id).has("production"), "allied construction omits private queues")
	var client: Node3D = FIXTURE.instantiate()
	root.add_child(client)
	var client_relay: RelayClient = RELAY.instantiate()
	client.add_child(client_relay)
	var receiver: MatchReplication = client.get_node("MatchReplication")
	receiver.configure(client, client_relay)
	receiver.receive_snapshot(snapshot)
	check(receiver.last_received_tick == 0, "client accepts cannon building through actual snapshot decoder")
	var replica: BattleBuilding = client.entities_by_id[tower.entity_id]
	receiver.render(.1)
	check(is_equal_approx(replica.artillery.guns[0].turret.rotation.y,.7) and is_equal_approx(replica.artillery.guns[0].elevation.rotation.x,-.12), "client displays yaw and elevation on correct independent parts")
	check(replica.artillery.guns[0].animation.current_animation == "fire", "client samples saved recoil animation")
	check(replica.model_pivot.rotation.y == 0 and not replica.is_physics_processing(), "replica stone base fixed and combat disabled")
	var client_target: BattleUnit = client.entities_by_id[target.entity_id]
	var flight := ProjectileFlight.new()
	flight.initialize_visual(client, replica.get_projectile_origin(), client_target.position + Vector3.UP, "cannon", .3, .13, client_target)
	flight.advance(.4)
	flight.reset()
	check(client_target.hp == 315, "visual projectile never applies damage a second time")
	for invalid: Variant in [null, {}, {"yaw": NAN,"pitch":0,"fired":-1}, {"yaw":0,"pitch":2,"fired":-1}, {"yaw":0,"pitch":0,"fired":2.1}, {"yaw":0,"pitch":0,"fired":-.5}, {"yaw":0,"pitch":0,"fired":0,"target":target.entity_id}]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.tick = 1
		state_for(bad, tower.entity_id).turrets = [invalid]
		receiver.receive_snapshot(bad)
		check(receiver.last_received_tick == 0, "reject malformed turret state " + str(invalid))
	var bad_arrow: Dictionary = snapshot.duplicate(true)
	bad_arrow.tick = 1
	state_for(bad_arrow, tower.entity_id).kind = "defense_tower"
	check(not receiver._valid_snapshot(bad_arrow), "arrow tower cannot carry cannon presentation fields")
	var bad_unit: Dictionary = snapshot.duplicate(true)
	state_for(bad_unit,target.entity_id).turrets = state_for(snapshot,tower.entity_id).turrets
	check(not receiver._valid_snapshot(bad_unit), "unit cannot inject building weapon state")
	host.simulation_tick = 2
	host.elapsed = 3
	tower.artillery.guns[0].turret.rotation.y = -.8
	tower.weapons[0].last_fired = 2.9
	receiver.receive_snapshot(wire(sender.build_snapshot(0)))
	receiver.render(1.0)
	check(receiver.last_received_tick == 2 and is_equal_approx(replica.artillery.guns[0].turret.rotation.y,-.8), "later snapshots interpolate fresh turret direction")
	check(client_target.hp == 315, "subsequent snapshots preserve authoritative HP")
	client.queue_free(); host.queue_free()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://.local/defenses/cannon_tower")
	FileAccess.open("res://.local/defenses/cannon_tower/network.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "\t"))
	print("CANNON_TOWER_NETWORK ", checks, " checks; ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
