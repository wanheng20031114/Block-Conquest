extends SceneTree
## Encoded host snapshots, native client clips and launch-time penetration.
const FIXTURE = preload("res://tests/network_game_fixture.tscn")
const RELAY = preload("res://scripts/network/relay_client.tscn")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ",label)
func state_for(snapshot: Dictionary,id: int) -> Dictionary:
	for state: Dictionary in snapshot.entities:
		if int(state.id) == id: return state
	return {}
func wire(snapshot: Dictionary) -> Dictionary:
	return NetworkProtocol.decode(NetworkProtocol.encode({"op":"snapshot","payload":snapshot})).payload
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.local/musketeer-20260914"))
	var host: Node3D = FIXTURE.instantiate()
	root.add_child(host)
	host.is_authority = true
	var host_relay: RelayClient = RELAY.instantiate()
	host.add_child(host_relay)
	var sender: MatchReplication = host.get_node("MatchReplication")
	sender.configure(host,host_relay)
	var shooter: BattleUnit = host.spawn_unit("musketeer",0,Vector3.ZERO)
	var target: BattleUnit = host.spawn_unit("shield_guard",2,Vector3(0,0,-5))
	var hidden: BattleUnit = host.spawn_unit("musketeer",2,Vector3(30,0,30))
	host.visible_ids.assign([target.entity_id])
	var barracks: BattleBuilding = host.spawn_building("barracks",0,Vector3(10,0,10))
	check(barracks.production.recruit("musketeer").ok,"musketeer queued in host barracks")
	shooter._model.strike()
	shooter._model.prepare_attack_release(.35)
	var flight := ProjectileFlight.new()
	flight.initialize(host,shooter,target,DamageResolver.snapshot(shooter._stats,0,0,0),"bullet")
	check(flight._start.distance_to(shooter.get_projectile_origin())<.0001,"host samples authored muzzle")
	flight.advance(1)
	check(target.hp == 127 and host.effects == 1,"host applies one penetrative bullet")
	shooter._model.attack.seek(.56,true)
	host.elapsed = 1
	var snapshot := wire(sender.build_snapshot(0))
	check(NetworkProtocol.VERSION == 16 and not snapshot.is_empty(),"versioned primitive wire round trip")
	check(state_for(snapshot,hidden.entity_id).is_empty(),"unseen musketeer omitted")
	check(state_for(snapshot,shooter.entity_id).anim == "strike","host publishes reload action")
	var client: Node3D = FIXTURE.instantiate()
	root.add_child(client)
	var client_relay: RelayClient = RELAY.instantiate()
	client.add_child(client_relay)
	var receiver: MatchReplication = client.get_node("MatchReplication")
	receiver.configure(client,client_relay)
	receiver.receive_snapshot(snapshot)
	check(receiver.last_received_tick == 0,"client accepts musketeer state")
	var replica: BattleUnit = client.entities_by_id[shooter.entity_id]
	var target_replica: BattleUnit = client.entities_by_id[target.entity_id]
	receiver.render(.1)
	check(replica._model.attack.current_animation == "strike" and is_equal_approx(replica._model.attack.current_animation_position,.56),"native reload sampled at host phase")
	check(not replica.is_physics_processing() and target_replica.hp == 127,"replica cannot autonomously attack")
	var cosmetic := ProjectileFlight.new()
	cosmetic.initialize_visual(client,flight._start,flight._end,"bullet",.1,0,target_replica)
	cosmetic.advance(1)
	check(target_replica.hp == 127,"client bullet presentation never deals damage")
	check(state_for(snapshot,barracks.entity_id).production.training[0].kind == "musketeer","recruit queue transmitted")
	for invalid: Dictionary in [{"kind":"missing_unit"},{"anim":"repair"},{"anim":"heal"},{"anim":"build"},{"anim":"gather"},{"phase":NAN},{"attack_range":8}]:
		var bad := snapshot.duplicate(true)
		bad.tick = 1
		state_for(bad,shooter.entity_id).merge(invalid,true)
		receiver.receive_snapshot(bad)
		check(receiver.last_received_tick == 0,"reject mismatched musketeer state "+str(invalid))
	# An already launched bullet retains its penetration after the shooter is gone.
	var after_death := ProjectileFlight.new()
	after_death.initialize(host,shooter,target,DamageResolver.snapshot(shooter._stats,0,0,0),"bullet")
	shooter.queue_free()
	await process_frame
	after_death.advance(1)
	check(target.hp == 109,"source deletion leaves launch snapshot valid")
	client.queue_free()
	host.queue_free()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://.local/musketeer-20260914")
	FileAccess.open("res://.local/musketeer-20260914/network-results.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("MUSKETEER_NETWORK ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
