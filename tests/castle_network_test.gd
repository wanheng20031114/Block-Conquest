extends SceneTree
## Three authored guns round-trip through the actual protocol and replica path.
const FIXTURE = preload("res://tests/network_game_fixture.tscn")
const RELAY = preload("res://scripts/network/relay_client.tscn")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL ",label)
func state_for(snapshot: Dictionary,id: int) -> Dictionary:
	for state: Dictionary in snapshot.entities:
		if int(state.id) == id: return state
	return {}
func wire(snapshot: Dictionary) -> Dictionary:
	return NetworkProtocol.decode(NetworkProtocol.encode({"op":"snapshot","payload":snapshot})).payload
func _run() -> void:
	create_timer(25,true,false,true).timeout.connect(func(): quit(3))
	var host: Node3D = FIXTURE.instantiate()
	root.add_child(host)
	host.is_authority = true
	var relay: RelayClient = RELAY.instantiate()
	host.add_child(relay)
	var sender: MatchReplication = host.get_node("MatchReplication")
	sender.configure(host,relay)
	var castle: BattleBuilding = host.spawn_building("castle",0,Vector3.ZERO)
	var hidden: BattleBuilding = host.spawn_building("castle",2,Vector3(40,0,40))
	var ally: BattleBuilding = host.spawn_building("castle",1,Vector3(12,0,0),true)
	var target: BattleUnit = host.spawn_unit("war_elephant",2,Vector3(0,0,-12))
	host.visible_ids.append(target.entity_id)
	host.elapsed = 2
	for i: int in 3:
		castle.weapons[i].last_fired = [1.2,1.5,1.8][i]
		castle.artillery.guns[i].turret.rotation.y = [-.7,.6,1.1][i]
		castle.artillery.guns[i].elevation.rotation.x = [-.12,.0,.2][i]
	ally.construction_progress = .5
	for i: int in 3: target.receive_hit(DamageResolver.snapshot(castle._stats,0,0,0),castle)
	var snapshot := wire(sender.build_snapshot(0))
	var state := state_for(snapshot,castle.entity_id)
	check(NetworkProtocol.VERSION == 18,"battery array contract has explicit protocol version")
	check(state.turrets.size() == 3,"exactly three public gun states")
	for i: int in 3:
		check(state.turrets[i].size() == 3 and state.turrets[i].fired == castle.weapons[i].last_fired,"gun release time survives wire without target or cooldown: %d" % i)
	check(state_for(snapshot,hidden.entity_id).is_empty(),"hidden enemy castle omitted")
	check(not state_for(snapshot,ally.entity_id).has("production"),"allied castle omits private construction data")
	var client: Node3D = FIXTURE.instantiate()
	root.add_child(client)
	var client_relay: RelayClient = RELAY.instantiate()
	client.add_child(client_relay)
	var receiver: MatchReplication = client.get_node("MatchReplication")
	receiver.configure(client,client_relay)
	receiver.receive_snapshot(snapshot)
	check(receiver.last_received_tick == 0,"client accepts real castle through snapshot decoder")
	var replica: BattleBuilding = client.entities_by_id[castle.entity_id]
	var client_target: BattleUnit = client.entities_by_id[target.entity_id]
	receiver.render(.1)
	for i: int in 3:
		var gun := replica.artillery.guns[i]
		check(is_equal_approx(gun.turret.rotation.y,castle.artillery.guns[i].turret.rotation.y) and is_equal_approx(gun.elevation.rotation.x,castle.artillery.guns[i].elevation.rotation.x),"replica gun independently aims: %d" % i)
		check(is_equal_approx(gun.animation.current_animation_position,receiver._playback_time-castle.weapons[i].last_fired),"replica independently samples release phase on interpolated clock: %d" % i)
		check(replica.get_projectile_origin(i).distance_to(gun.muzzle.global_position)<.0001,"indexed origin follows replica recoil: %d" % i)
		var flight := ProjectileFlight.new()
		flight.initialize_visual(client,replica.get_projectile_origin(i),client_target.position+Vector3.UP,"cannon",.3,.13,client_target)
		flight.advance(.4); flight.reset()
	check(client_target.hp == 285,"three client projectiles cannot duplicate authority damage")
	check(not replica.is_physics_processing() and replica.model_pivot.rotation == Vector3.ZERO,"replica base fixed and attack authority disabled")
	var invalid_arrays: Array = [null,{},[],[state.turrets[0]],state.turrets+[state.turrets[0]]]
	for invalid: Variant in invalid_arrays:
		var bad := snapshot.duplicate(true)
		bad.tick = 1
		state_for(bad,castle.entity_id).turrets = invalid
		receiver.receive_snapshot(bad)
		check(receiver.last_received_tick == 0,"wrong battery type/count rejected: "+str(invalid))
	for invalid: Variant in [null,{},{"yaw":NAN,"pitch":0,"fired":-1},{"yaw":0,"pitch":1,"fired":-1},{"yaw":0,"pitch":0,"fired":2.1},{"yaw":0,"pitch":0,"fired":-.5},{"yaw":0,"pitch":0,"fired":0,"target":1}]:
		var bad := snapshot.duplicate(true)
		state_for(bad,castle.entity_id).turrets[2] = invalid
		check(not receiver._valid_snapshot(bad),"each gun is validated, including the last: "+str(invalid))
	var bad_kind := snapshot.duplicate(true)
	state_for(bad_kind,castle.entity_id).kind = "cannon_tower"
	check(not receiver._valid_snapshot(bad_kind),"single cannon tower cannot accept three gun states")
	var bad_unit := snapshot.duplicate(true)
	state_for(bad_unit,target.entity_id).turrets = state.turrets
	check(not receiver._valid_snapshot(bad_unit),"unit cannot inject building battery fields")
	host.simulation_tick = 2; host.elapsed = 3
	castle.weapons[0].last_fired = 2.9
	castle.artillery.guns[0].turret.rotation.y = -.9
	receiver.receive_snapshot(wire(sender.build_snapshot(0)))
	receiver.render(1.0)
	check(is_equal_approx(replica.artillery.guns[0].animation.current_animation_position,.1),"fresh first-gun release starts only its recoil")
	check(is_equal_approx(replica.artillery.guns[1].animation.current_animation_position,.9) and is_equal_approx(replica.artillery.guns[2].animation.current_animation_position,.9),"other guns return to rest independently")
	check(client_target.hp == 285,"later snapshots preserve authority HP")
	client.queue_free(); host.queue_free()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://.local/defenses/castle")
	FileAccess.open("res://.local/defenses/castle/network.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CASTLE_NETWORK ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
