extends "res://tests/block_war_replication_test.gd"
## A 4096-soldier restore while reliable combat facts overtake bulk data.
var cpu_stages: Dictionary = {}

func boundary(delta: float = Coordinator.STEP, loss: bool = false) -> void:
	var begun := Time.get_ticks_usec()
	authority.process(delta)
	_record_cpu("host_simulate_publish", begun)
	begun = Time.get_ticks_usec()
	deliver(host_wire, client, false, loss)
	_record_cpu("client_receive", begun)
	begun = Time.get_ticks_usec()
	client.process(delta)
	_record_cpu("client_present", begun)
	begun = Time.get_ticks_usec()
	deliver(client_wire, authority)
	_record_cpu("host_receive", begun)

func _record_cpu(stage: String, begun: int) -> void:
	var milliseconds := float(Time.get_ticks_usec() - begun) / 1000.0
	if not cpu_stages.has(stage): cpu_stages[stage] = [0.0, 0.0]
	cpu_stages[stage][0] += milliseconds
	cpu_stages[stage][1] = maxf(cpu_stages[stage][1], milliseconds)

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	host.marches.send(0, 1, 0, 4096, PackedVector3Array([Vector3.ZERO, Vector3(500, 0, 0)]))
	# Spread ranks along the road so all soldiers participate in rendering/motion.
	for i: int in host.marches._units.size():
		var unit: WarMarches.MarchUnit = host.marches._units[i]
		unit.distance = 0.1 + float(i / 4) * 0.35
		host.marches._update_pose(unit)
	var begun := Time.get_ticks_usec()
	authority._publish_step(0.0)
	# The large first transaction now waits on stream 5. Later small reliable
	# building changes arrive first; clients must not install partial armies.
	for i: int in 4:
		host.by_id[2].population -= 1.0
		host.elapsed += Coordinator.STEP
		authority._tick += 1
		authority._publish_step(Coordinator.STEP)
	deliver(host_wire, client, true)
	check(client._pending.size() >= 4 and replica.marches._units.is_empty(), "later facts wait for the large missing army transaction")
	flush()
	var recovery_ms := float(Time.get_ticks_usec() - begun) / 1000.0
	check(replica.marches._units.size() == 4096, "chunked restore installs all 4096 stable soldiers")
	check(client._pending.is_empty() and Codec.digest(client._mirror) == Codec.digest(authority._published), "bulk interleaving catches up exactly once")
	check(replica.by_id[2].population < 57.0, "damage arriving during restore is not rolled back")

	host_wire.sent.clear()
	var current := Codec.for_player(authority.codec.capture(host, authority._tick), -1)
	authority._send_anchors(current)
	while not authority._anchor_outbox.is_empty(): authority._flush_anchors(0.1)
	var wire_bytes := 0
	var packets := 0
	var largest := 0
	for packet: Dictionary in host_wire.sent:
		if packet.kind != "anchors": continue
		packets += 1
		var size: int = Protocol.encode(packet).size() + 100 # full relay envelope allowance
		wire_bytes += size
		largest = maxi(largest, size)
	check(largest <= 1200, "every optional movement packet stays under a conservative DTLS MTU")
	check(packets * 2 < 330 and wire_bytes * 2 < 300000, "4096-soldier anchors fit relay packet and bandwidth budgets")
	var canonical: String = Codec.digest(client._mirror)
	# Lose every third optional packet, reverse the rest and replay duplicates.
	var outgoing := host_wire.sent.duplicate(true)
	for i: int in range(outgoing.size() - 1, -1, -1):
		if i % 3 == 0: continue
		var packet: Dictionary = outgoing[i]
		client._on_message(105, packet.kind, packet.payload)
		client._on_message(105, packet.kind, packet.payload)
	client._apply_view()
	check(Codec.digest(client._mirror) == canonical, "loss, reordering and duplicate anchors cannot change rules")
	check(client._anchor_versions.size() <= 4096 + host.buildings.size() + 6, "optional revision cache remains bounded by live records")

	# Measure the real simulation + diff + JSON path, not just a serialization loop.
	host_wire.sent.clear()
	var elapsed_cpu := 0.0
	var max_cpu := 0.0
	for frame: int in 30:
		begun = Time.get_ticks_usec()
		boundary(Coordinator.STEP, frame % 2 == 0)
		var cpu := float(Time.get_ticks_usec() - begun) / 1000.0
		elapsed_cpu += cpu
		max_cpu = maxf(max_cpu, cpu)
	flush()
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "4096 moving soldiers preserve canonical agreement across actual simulation")
	check(host_wire.invalid_packets == 0 and client_wire.invalid_packets == 0, "large battle never emits an oversized or invalid message")
	print("REPLICATION_LOAD checks=", checks, " failures=", failures.size(), " soldiers=4096 recovery_ms=", recovery_ms, " pair_cpu_mean_ms=", elapsed_cpu / 30.0, " pair_cpu_max_ms=", max_cpu, " anchor_bytes_per_second=", wire_bytes * 2, " anchor_packets_per_second=", packets * 2, " largest_datagram=", largest)
	for stage: String in cpu_stages:
		print("REPLICATION_CPU stage=", stage, " mean_ms=", cpu_stages[stage][0] / 30.0, " max_ms=", cpu_stages[stage][1])
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	host_wire.free()
	client_wire.free()
	quit(0 if failures.is_empty() else 1)
