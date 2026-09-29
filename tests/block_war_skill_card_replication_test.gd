extends "res://tests/block_war_replication_test.gd"
## Private skill accounts must be installed before the real HUD observes a view.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var light_changes: Array[int] = [0, 0, 0, 0]
var glow_changes: Array[int] = [0, 0, 0, 0]
var energy_changes: Array[float] = []
var cooldown_observations: Array[float] = []

func configuration() -> Dictionary:
	var config := super.configuration()
	config.slots[2].commander = "pig"
	return config

func _visibility_changed(index: int, glow: bool) -> void:
	if glow: glow_changes[index] += 1
	else: light_changes[index] += 1

func _counts() -> Array:
	return [light_changes.duplicate(), glow_changes.duplicate()]

func _hud(expected_energy: float, ready: Array, label: String) -> void:
	check(is_equal_approx(replica.hud.get_node("%EnergyBar").value, expected_energy), label + " HUD energy is authoritative")
	check(is_equal_approx(replica.faction_skills[2].energy, expected_energy), label + " local account agrees with HUD")
	for index: int in 4:
		var button: Button = replica.hud.get_node("UI/Skills/Row/Skill%d" % index)
		check(button.disabled == not ready[index] and button.get_node("ReadyLight").visible == ready[index], label + " QWER readiness %d" % index)
		check(button.get_node("Cooldown").visible == (replica.faction_skills[2].cooldowns[index] > 0.0), label + " cooldown overlay %d" % index)

func _publish(delta: float = 0.0) -> void:
	authority._tick += 1
	authority._publish_step(delta)
	flush()

func _stable_cycle(expected_energy: float, ready: Array, label: String, damage: bool = false) -> void:
	var before := _counts()
	var cooldown: float = replica.faction_skills[2].cooldowns[0]
	energy_changes.clear()
	cooldown_observations.clear()
	if damage: host.by_id[5].population -= 1.0
	_publish(Coordinator.ANCHOR_INTERVAL)
	_hud(expected_energy, ready, label + " after flush")
	# The normal 10 Hz HUD refresh must not create another ready transition.
	replica.update_hud()
	_hud(expected_energy, ready, label + " after HUD refresh")
	check(_counts() == before, label + " no ReadyLight or ReadyGlow visibility transitions")
	check(energy_changes.all(func(value: float): return is_equal_approx(value, expected_energy)), label + " no transient public zero energy")
	check(not cooldown_observations.is_empty() and cooldown_observations.all(func(value: float): return is_equal_approx(value, cooldown)), label + " every rendered Q hint retains the private cooldown")

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	root.get_node("Session").block_war_map_id = "highland"
	host = make_game(105)
	replica = make_game(102)
	host.faction_skills[2].energy = 50.0
	host_wire = make_wire(105)
	client_wire = make_wire(102)
	authority = Coordinator.new()
	client = Coordinator.new()
	authority.setup(host, host_wire)
	client.setup(replica, client_wire)
	flush()
	client.process(0.0)
	_hud(50.0, [true, true, true, false], "initial snapshot")
	# Finish legitimate initial reveal/ready tweens before counting new pulses.
	replica.update_hud()
	await create_timer(0.7, true, false, true).timeout
	for index: int in 4:
		var button: Button = replica.hud.get_node("UI/Skills/Row/Skill%d" % index)
		button.get_node("ReadyLight").visibility_changed.connect(_visibility_changed.bind(index, false))
		button.get_node("ReadyGlow").visibility_changed.connect(_visibility_changed.bind(index, true))
	replica.hud.get_node("%EnergyBar").value_changed.connect(func(value: float): energy_changes.append(value))
	replica.hud.get_node("UI/Skills/Row/Skill0").hint_changed.connect(func(): cooldown_observations.append(replica.faction_skills[2].cooldowns[0]))
	check(replica.faction_skills[2].commander == RULES.PIG, "client uses the actual pig QWER cards")
	check(float(client._mirror.factions["2"][1]) == 0.0 and float(client._account[1]) == 50.0, "fixture separates redacted public facts from private energy")
	for index: int in 4:
		_stable_cycle(50.0, [true, true, true, false], "ordinary sync %d" % index, index % 2 == 1)

	var before := _counts()
	check(client.submit({"type": "skill_building", "skill": 0, "target": 2}).accepted, "client submits a real pig Q")
	deliver(client_wire, authority)
	authority._drain_commands()
	_publish()
	_hud(35.0, [false, true, true, false], "Q consumes energy and starts cooldown")
	check(host.pig.ready.has(2) and replica.faction_skills[2].cooldowns[0] == RULES.PIG_COOLDOWNS[0], "accepted cast replicates actual preparation and cooldown")
	check(light_changes[0] == before[0][0] + 1 and light_changes.slice(1) == before[0].slice(1), "real Q cast disables Q exactly once without blinking WER")
	replica.update_hud()
	_stable_cycle(35.0, [false, true, true, false], "cooling Q with unrelated event", true)
	before = _counts()
	host.simulate(RULES.PIG_COOLDOWNS[0])
	_publish(Coordinator.ANCHOR_INTERVAL)
	_hud(53.0, [true, true, true, false], "Q cooldown naturally expires")
	check(light_changes[0] == before[0][0] + 1 and glow_changes[0] == before[1][0] + 1, "real cooldown completion readies and pulses Q once")
	_stable_cycle(53.0, [true, true, true, false], "after cooldown expiry")

	# A private packet can overtake the public transaction it depends on.
	host.faction_skills[2].energy = 80.0
	host.by_id[5].population -= 1.0
	authority._tick += 1
	authority._publish_step(0.0)
	var held: Array[Dictionary] = host_wire.sent
	host_wire.sent = []
	for packet: Dictionary in held:
		if packet.kind == "events" and packet.payload.has("account") and int(packet.target) == 102:
			client._on_message(105, "events", packet.payload)
	check(client._account_base > client._applied, "future private account awaits its reliable base")
	_hud(53.0, [true, true, true, false], "future account cannot enable R early")
	before = _counts()
	client._view_dirty = true
	flush()
	_hud(53.0, [true, true, true, false], "public reinstall while future account waits")
	replica.update_hud()
	check(_counts() == before, "pending private account does not erase the last applied HUD account")
	host_wire.sent = held
	flush()
	_hud(80.0, [true, true, true, true], "account applies after its base arrives")
	host.faction_skills[2].energy = 50.0
	_publish()
	_hud(50.0, [true, true, true, false], "lower real energy disables R again")
	replica.update_hud()

	check(host.set_match_paused(true, 2).accepted, "participant pauses the match")
	_publish()
	_hud(50.0, [false, false, false, false], "pause disables all skills without changing energy")
	_stable_cycle(50.0, [false, false, false, false], "paused public refresh", true)
	check(host.set_match_paused(false, 2).accepted, "participant resumes the match")
	_publish()
	_hud(50.0, [true, true, true, false], "resume restores only affordable skills")
	replica.update_hud()
	_stable_cycle(50.0, [true, true, true, false], "resumed public refresh")

	# Interrupt recovery before a baseline arrives, retaining the private account.
	client._last_resync_ms = -10000
	client._request_resync("skill_card_regression")
	client_wire.sent.clear()
	replica.update_hud()
	# Recovery gates commands in the coordinator; these cards retain the last
	# account readiness while the separate synchronization status is displayed.
	_hud(50.0, [true, true, true, false], "interrupted recovery retains the private account")
	check(not client.submit({"type": "skill_building", "skill": 0, "target": 2}).accepted, "recovery still blocks skill commands")
	before = _counts()
	client.process(0.0)
	replica.update_hud()
	check(_counts() == before and client._snapshot_loading, "waiting for recovery causes no readiness pulses")
	authority._snapshot_sent_at.clear()
	authority._send_snapshot(102)
	flush()
	client.process(0.0)
	_hud(50.0, [true, true, true, false], "public recovery restores private HUD atomically")
	check(not client._snapshot_loading and not client._recovery_waiting, "fresh snapshot completes interrupted recovery")
	replica.update_hud()
	_stable_cycle(50.0, [true, true, true, false], "post recovery refresh", true)
	check(Codec.digest(client._mirror) == Codec.digest(authority._published), "HUD account installation leaves the public mirror checksum unchanged")
	print("SKILL_CARD_REPLICATION checks=", checks, " failures=", failures.size())
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free(); replica.free(); host_wire.free(); client_wire.free()
	quit(0 if failures.is_empty() else 1)
