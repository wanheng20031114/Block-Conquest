extends SceneTree
## Real processes + native DTLS. The private-desktop job owns every child process.
## Fixture-only population/energy grants shorten visual review; all orders and
## spells still travel through each player's normal command submission path.

const PROTOCOL := preload("res://scripts/network/war_protocol.gd")
const SNAPSHOT := preload("res://scripts/network/war_snapshot.gd")
var role := "host"
var output := ""
var session: Node
var online: Node
var game: Node3D
var server: Node
var children: Array[int] = []
var checks := 0
var failures: Array[String] = []
var observed_visuals: Array[String] = []
var observed_cursors: Array[int] = []
var _cursor_clock := 0.0
var _last_phase := ""
var _last_capture := ""
var _finishing := false
var _public_mode := false
var _skip_captures := false
var _controls_mode := false
var _leave_controls := false
var _left_battle := false
var _pack_path := ""
var _external_script := ""
var _empty_project := ""
var _forward_options := PackedStringArray()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("VISUAL_CHECK ", role, " ", condition, " ", label)
	if not condition:
		failures.append(label)
		push_error("%s: %s" % [role, label])

func until(predicate: Callable, label: String, seconds := 18.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = predicate.call()
	check(passed, label)
	return passed

func pause(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func write_json(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(name + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))

func read_json(name: String) -> Dictionary:
	var path := output.path_join(name + ".json")
	if not FileAccess.file_exists(path): return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK: return {}
	return parser.data if parser.data is Dictionary else {}

func capture(label: String) -> void:
	if _skip_captures or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(role + "_" + label + ".png")) == OK, "capture " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	output = args[0]
	var positional := PackedStringArray()
	for argument: String in args.slice(1):
		if argument.begins_with("--"):
			_forward_options.append(argument)
			if argument == "--public": _public_mode = true
			elif argument == "--skip-captures": _skip_captures = true
			elif argument == "--controls": _controls_mode = true
			elif argument == "--leave-controls":
				_controls_mode = true
				_leave_controls = true
			elif argument.begins_with("--pack="): _pack_path = argument.trim_prefix("--pack=")
			elif argument.begins_with("--external-script="): _external_script = argument.trim_prefix("--external-script=")
			elif argument.begins_with("--empty-project="): _empty_project = argument.trim_prefix("--empty-project=")
		else: positional.append(argument)
	if not positional.is_empty(): role = positional[0]
	if role == "relay":
		await _relay_run()
		return
	create_timer(215.0 if _public_mode else 155.0, true, false, true).timeout.connect(func():
		check(false, "visual session deadline")
		await _finish())
	root.size = Vector2i(1280, 720)
	root.gui_embed_subwindows = true
	Engine.max_fps = 30
	session = root.get_node("Session")
	online = session.online
	if _public_mode:
		check(online.content_hash == PROTOCOL.content_hash() and online.content_hash.length() == 64, "public client uses packaged content manifest hash")
		check(online.certificate_path == online.CERTIFICATE_PATH and FileAccess.file_exists(online.certificate_path), "public client trusts packaged production certificate")
		if not _pack_path.is_empty():
			check(not _empty_project.is_empty() and not _external_script.is_empty(), "packaged test declares isolated project and external harness")
			check(not ResourceLoader.exists("res://server/war_relay_server.gd") and not ResourceLoader.exists("res://tests/block_war_multiplayer_visual.gd"), "formal pack excludes server and test resources; no source fallback")
		print("RELEASE_VALIDATION ", JSON.stringify({"role":role,"version":ProjectSettings.get_setting("application/config/version"),"content_hash":online.content_hash,"certificate_hash":FileAccess.get_sha256(online.certificate_path),"pack":_pack_path,"pack_hash":FileAccess.get_sha256(_pack_path) if not _pack_path.is_empty() else "","resource_root":ProjectSettings.globalize_path("res://"),"isolated_project":_empty_project,"executable":OS.get_executable_path(),"relay":online.DEFAULT_ADDRESS,"port":PROTOCOL.PORT}))
	else:
		online.content_hash = "native-visual-v1"
		online.certificate_path = output.path_join("relay.crt")
	if not failures.is_empty():
		await _finish()
		return
	online.match_message.connect(_message)
	online.cursor_received.connect(func(sender: int, _payload: Dictionary): observed_cursors.append(sender))
	if role == "host":
		await _host_setup()
	else:
		await _guest_setup(int(positional[1]), positional[2])
	if not failures.is_empty():
		await _finish()
		return
	if not await until(func(): return current_scene != null and current_scene.scene_file_path == session.BATTLE_SCENE and current_scene._match_ready, "native Session loads battle", 45):
		await _finish()
		return
	game = current_scene
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.camera_rig.set_process(false)
	game.camera.size = 50.0
	game.audio.muted = true
	game.get_node("TeammateCursors")._send_clock = -1000000.0
	if not await until(func(): return online.connection_state == "match" and not game.network_match._snapshot_loading and not game.simulation_paused, "all peers install authority baseline", 45):
		await _finish()
		return
	while session.transition.busy: await process_frame
	check(game.local_faction == {"host": 5, "ally": 3, "enemy": 2}[role], "local faction matches nonzero authored seat")
	_check_garrison_visibility("baseline")
	if role == "host":
		await _host_review()
	else:
		await _guest_review()
	await _finish()

func _host_setup() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for filename: String in DirAccess.get_files_at(output):
		if filename.ends_with(".json"):
			DirAccess.remove_absolute(output.path_join(filename))
	var port: int = PROTOCOL.PORT
	if not _public_mode:
		_spawn("relay", 0, "")
		if not await until(func(): return read_json("relay_ready").has("port"), "independent headless relay ready"): return
		port = int(read_json("relay_ready").port)
	check(online.connect_relay(online.DEFAULT_ADDRESS if _public_mode else "127.0.0.1", port) == OK, "host public DTLS begins" if _public_mode else "host DTLS begins")
	if not await until(func(): return online.connection_state == "connected", "host DTLS ready"): return
	online.create_room("islands", "持盾熊 · 房主")
	if not await until(func(): return not online.room.is_empty(), "room created"): return
	online.move_to_slot(5)
	online.choose_commander("bear")
	for index: int in [0, 1, 4]: online.set_slot(index, "bot", "frog" if index == 1 else "squirrel")
	if not await until(func(): return online.local_faction == 5 and online.room.slots[4].kind == "bot" and online.room.slots[5].commander == "bear", "host seat five and bot roster"): return
	session.start_online()
	_spawn("ally", port, str(online.room.code))
	if not await until(func(): return online.room.slots[3].kind == "human", "ally chooses seat three"): return
	_spawn("enemy", port, str(online.room.code))
	if not await until(func(): return online.room.slots[2].kind == "human", "enemy chooses seat two"): return
	while session.transition.busy: await process_frame
	await pause(0.4)
	await capture("room")
	if not await until(func(): return online.room.slots[2].ready and online.room.slots[3].ready, "guests ready after all edits"): return
	online.set_ready(true)
	if not await until(func(): return online.room.slots[5].ready, "host ready"): return
	online.start_match()

func _relay_run() -> void:
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(key, "CN=%s,O=Local Visual Test,C=JP" % PROTOCOL.TLS_NAME, "20240101000000", "20400101000000")
	check(key.save(output.path_join("relay.key")) == OK and cert.save(output.path_join("relay.crt")) == OK, "isolated test DTLS identity")
	# Server source is deliberately excluded from the formal PCK. Only the local
	# fixture loads it; public release verification uses the deployed Relay.
	server = load("res://server/war_relay_server.gd").new()
	server.model.content_hash = "native-visual-v1"
	root.add_child(server)
	check(server.start("127.0.0.1", 0, output.path_join("relay.key"), output.path_join("relay.crt")) == OK, "private local relay")
	var port: int = server.connection.get_local_port()
	write_json("relay_ready", {"port": port})
	await pause(165.0)
	server.stop()
	quit()

func _spawn(kind: String, port: int, code: String) -> void:
	var project_path := ProjectSettings.globalize_path("res://") if _pack_path.is_empty() else _empty_project
	var harness_path := "res://tests/block_war_multiplayer_visual.gd" if _pack_path.is_empty() else _external_script
	var arguments := PackedStringArray(["--path", project_path])
	if not _pack_path.is_empty(): arguments.append_array(["--main-pack", _pack_path])
	arguments.append_array(["--audio-driver", "Dummy", "--rendering-method", "forward_plus", "--resolution", "1280x720", "--max-fps", "30", "--log-file", output.path_join(kind + ".log"), "--script", harness_path, "--", output, kind, str(port), code])
	arguments.append_array(_forward_options)
	if kind in ["enemy", "relay"] or _skip_captures: arguments.insert(0, "--headless")
	var process := OS.create_process(OS.get_executable_path(), arguments)
	check(process > 0, "spawn independent " + kind)
	children.append(process)

func _guest_setup(port: int, code: String) -> void:
	check(online.connect_relay(online.DEFAULT_ADDRESS if _public_mode else "127.0.0.1", port) == OK, "guest public DTLS begins" if _public_mode else "guest DTLS begins")
	if not await until(func(): return online.connection_state == "connected", "guest DTLS ready"): return
	online.join_room(code, "迅猛兔 · 队友" if role == "ally" else "松鼠 · 对手")
	if not await until(func(): return not online.room.is_empty(), "joined room"): return
	if role == "ally": online.move_to_slot(3)
	online.choose_commander("rabbit" if role == "ally" else "squirrel")
	session.start_online()
	if not await until(func(): return online.local_faction == (3 if role == "ally" else 2), "guest fixed seat confirmed"): return
	while online.connection_state == "room":
		online.set_ready(true)
		await pause(0.3)

func _source(faction: int) -> Node3D:
	for building: Node3D in game.buildings:
		if building.faction == faction and building.kind == 0: return building
	return null

func _host_review() -> void:
	game.ai_enabled = false
	var bear_source := _source(5)
	var rabbit_source := _source(3)
	var enemy_source: Node3D = game.by_id[11]
	# Fixed authored neighbours exercise link radius and incoming orb projectiles.
	enemy_source.faction = 2
	enemy_source.population = 70
	game.by_id[17].faction = 5
	game.by_id[17].population = 40
	bear_source.population = 70
	rabbit_source.population = 70
	for state in game.faction_skills: state.energy = 100.0
	await pause(0.7)
	_phase("march", {"rabbit_source": rabbit_source.building_id, "enemy_source": enemy_source.building_id, "bear_source": bear_source.building_id})
	game.network_match.submit({"type": "upgrade", "building": bear_source.building_id})
	await pause(0.8)
	_phase("rush", {})
	check(game.network_match.submit({"type": "skill_building", "skill": 0, "target": bear_source.building_id}).accepted, "bear Q command submitted to authority")
	await pause(0.3)
	_focus(rabbit_source.global_position + Vector3(-5, 0, 0))
	await _take("rush")
	_phase("bear", {})
	check(game.network_match.submit({"type": "skill_building", "skill": 2, "target": bear_source.building_id}).accepted, "bear E command submitted to authority")
	await pause(0.4)
	game.faction_skills[5].energy = 100.0
	check(game.network_match.submit({"type": "skill_building", "skill": 3, "target": bear_source.building_id}).accepted, "bear R command submitted to authority")
	if not await until(func(): return game.faction_skills[5].cooldowns[3] > 0.0, "bear R authority executes before the W fixture grant"): return
	# Each skill is verified independently: R costs 90, so grant W its own test
	# energy after the queued R command has actually settled on the authority.
	game.faction_skills[5].energy = 100.0
	check(game.network_match.submit({"type": "skill_building", "skill": 1, "target": enemy_source.building_id}).accepted, "bear W enemy-building command submitted to authority")
	await pause(0.8)
	check(game.bear.is_locked(enemy_source.building_id) and game.bear.locks[enemy_source.building_id].faction == 5 and game.bear.locks[enemy_source.building_id].remaining > 0.0, "bear W authority installs the host faction's active enemy-building lock")
	_focus(bear_source.global_position + Vector3(-5, 0, -5))
	await _take("bear_ward")
	game.faction_skills[3].energy = 100.0
	_phase("recall", {})
	await pause(0.3)
	_focus(rabbit_source.global_position + Vector3(-7, 0, 0))
	await _take("recall")
	await pause(0.6)
	game.faction_skills[3].energy = 100.0
	rabbit_source.population = 70
	_phase("burrow", {})
	await pause(0.9)
	_focus(rabbit_source.global_position)
	await _take("burrow_dig")
	await pause(3.0)
	_focus(game.by_id[0].global_position + Vector3(3, 0, 0))
	await _take("burrow_exit")
	check(game.faction_skills[3].cooldowns[0] > 0.0 and game.faction_skills[3].cooldowns[2] > 0.0 and game.faction_skills[3].cooldowns[3] > 0.0, "remote rabbit Q E R authority executed")
	check(game.faction_skills[5].cooldowns.all(func(value: float): return value > 0.0), "all bear skills authority executed")
	check(observed_cursors.any(func(sender: int): return sender == int(online.room.slots[3].player_id)), "host receives ally cursor through relay")
	check(not observed_cursors.has(int(online.room.slots[2].player_id)), "host never receives enemy cursor")
	await _host_recovery()
	_check_garrison_visibility("recovered")
	if _controls_mode:
		await _host_match_controls()
	# Stop only authority processing; clients continue draining in-flight reliable facts.
	game.set_process(false)
	var flush_started := Time.get_ticks_msec()
	var last_flush := flush_started
	while not game.network_match._outbox.is_empty() and Time.get_ticks_msec() - flush_started < 10000:
		await process_frame
		var now := Time.get_ticks_msec()
		game.network_match._flush_outbox(float(now - last_flush) / 1000.0)
		last_flush = now
	check(game.network_match._outbox.is_empty(), "final throttled state transfer queue drains")
	write_json("expected", {"seq": game.network_match._seq, "digest": SNAPSHOT.digest(game.network_match._published)})
	await until(func(): return read_json("ally_done").has("failures") and read_json("enemy_done").has("failures"), "departed ally reaches lobby and remaining peer verifies committed state" if _leave_controls else "both clients verify final committed state", 15)
	for peer: String in ["ally", "enemy"]:
		var result := read_json(peer + "_done")
		check(int(result.get("failures", 1)) == 0, peer + " visual/state checks pass")

func _host_recovery() -> void:
	var before: float = game.elapsed
	_phase("guest_short_recovery", {})
	if not await until(func(): return read_json("ally_short_recovered").has("ready"), "guest restores full battle after short native disconnect", 18): return
	check(game.elapsed > before and online.room.slots[3].controller == "human", "guest short outage preserves authority clock and returns human control")
	before = game.elapsed
	_phase("guest_long_recovery", {})
	if not await until(func(): return online.room.slots[3].controller == "bot", "real ten-second grace hands disconnected seat to bot", 23): return
	check(3 in game._bot_factions and not game.simulation_paused and game.elapsed > before + 9.0, "Host game installs bot controller while battle keeps advancing")
	write_json("reconnect_ally", {"ready": true})
	if not await until(func(): return read_json("ally_long_recovered").has("ready"), "original token restores battle after bot takeover", 18): return
	check(3 not in game._bot_factions and online.room.slots[3].controller == "human", "authority removes bot only after recovery acknowledgement")
	_phase("host_recovery", {})
	var original_scene := game.get_instance_id()
	before = game.elapsed
	online.auto_reconnect = false
	online._lost(Time.get_ticks_msec())
	if not await until(func(): return read_json("ally_host_paused").has("ready") and read_json("enemy_host_paused").has("ready"), "both clients observe Host loss and stable paused clocks", 12): return
	check(is_equal_approx(game.elapsed, before) and game.simulation_paused, "disconnected Host accrues no simulation time")
	online.auto_reconnect = true
	check(online._open() == OK, "same Host process reconnects with original room token")
	if not await until(func(): return online.connection_state == "match" and online.room.slots[3].controller == "human" and online.room.slots[2].controller == "human", "Host recovery re-baselines both guests before human control", 18): return
	if not await until(func(): return read_json("ally_host_recovered").has("ready") and read_json("enemy_host_recovered").has("ready"), "both guests install restored Host baseline", 12): return
	check(game.get_instance_id() == original_scene and current_scene == game, "Host recovery retains original battle scene")
	var resumed: float = game.elapsed
	var resumed_at := Time.get_ticks_msec()
	await pause(0.7)
	var wall_seconds := float(Time.get_ticks_msec() - resumed_at) / 1000.0
	check(game.elapsed > resumed and game.elapsed - resumed <= wall_seconds + 0.15, "recovered Host advances in real time without catch-up debt")

func _tap_key(code: int) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = down
		root.push_input(event, true)

func _rule_sample() -> String:
	return SNAPSHOT.digest(SNAPSHOT.new().capture(game, 0))

func _confirm_surrender() -> void:
	if not game._local_menu: _tap_key(KEY_ESCAPE)
	game.hud.get_node("%Surrender").pressed.emit()
	check(game.hud.get_node("%OnlineConfirm").visible, "native menu opens surrender confirmation")
	game.hud.get_node("%OnlineConfirm").get_node("Center/Card/Column/Actions/Confirm").pressed.emit()

func _host_match_controls() -> void:
	var running_before: float = game.elapsed
	_tap_key(KEY_ESCAPE)
	await pause(0.35)
	check(game._local_menu and not game.match_paused and game.elapsed > running_before, "Esc leaves authority simulation running behind local menu")
	_tap_key(KEY_ESCAPE)
	var source := _source(5)
	check(game.network_match.submit({"type":"dispatch", "source":source.building_id, "target":0, "percent":25}).accepted, "Host launches live soldiers for surrender transfer")
	await pause(0.3)
	_phase("manual_pause", {})
	if not await until(func(): return game.match_paused, "ally native F3 pauses authoritative battle", 10): return
	if not await until(func(): return read_json("ally_manual_paused").has("ready") and read_json("enemy_manual_paused").has("ready"), "both clients freeze rules during global pause", 10): return
	check(game.pause_faction == 3, "pause identifies requesting non-Host faction")
	var frozen := _rule_sample()
	_phase("paused_reconnect", {})
	if not await until(func(): return read_json("ally_paused_recovered").has("ready"), "guest reconnects while manual pause remains active", 18): return
	check(game.match_paused and _rule_sample() == frozen, "recovery never resumes or advances globally paused rules")
	await _take("global_pause")
	_phase("manual_resume", {})
	if not await until(func(): return not game.match_paused, "opposing active human resumes through native F3", 10): return
	running_before = game.elapsed
	await pause(0.4)
	check(game.elapsed > running_before, "global resume advances authority normally")
	_tap_key(KEY_F3)
	if not await until(func(): return game.match_paused, "Host pauses before deterministic asset handover", 10): return
	var garrisons := {}
	for building: Node3D in game.buildings:
		if building.faction == 5: garrisons[building.building_id] = building.population
	var soldiers: Array[int] = []
	for unit in game.marches._units:
		if unit.order.faction == 5 and unit.is_exposed(): soldiers.append(unit.unit_id)
	check(not garrisons.is_empty() and not soldiers.is_empty(), "surrender fixture contains real buildings and departed soldiers")
	_confirm_surrender()
	if not await until(func(): return 5 in game.surrendered_factions, "Host surrender commits through ordinary command path", 10): return
	var handover := true
	for id: int in garrisons:
		handover = handover and game.by_id[id].faction == 3 and is_equal_approx(game.by_id[id].population, float(garrisons[id]) * 0.6)
	check(handover, "all Host buildings transfer to surviving human ally with exact forty percent garrison loss")
	var retained := 0
	for unit in game.marches._units:
		if unit.unit_id in soldiers and unit.order.faction == 3: retained += 1
	check(retained == soldiers.size(), "departed soldiers transfer intact without recreation or loss")
	check(online.is_host and game.is_authority() and not game.finished and game.match_paused, "surrendered Host keeps authority and existing manual pause")
	check(game.hud.get_node("%Surrender").disabled and game.hud.get_node("%MatchPause").disabled, "Host becomes spectator with match controls disabled")
	check(not game.network_match.submit({"type":"pause", "paused":false}).accepted, "spectator Host cannot bypass UI to resume")
	if game._local_menu: _tap_key(KEY_ESCAPE)
	_phase("spectator_resume", {})
	if not await until(func(): return not game.match_paused and read_json("ally_host_spectating").has("ready"), "surviving ally resumes while Host observes", 10): return
	running_before = game.elapsed
	await pause(0.4)
	check(game.elapsed > running_before, "surrendered Host continues simulating other players")
	await _take("host_spectating")
	_phase("team_leave" if _leave_controls else "team_surrender", {})
	if not await until(func(): return game.finished, "last allied human voluntary leave resolves team defeat while paused" if _leave_controls else "last allied human surrender resolves team defeat", 12): return
	check(game.winner_team == 0 and 3 in game.surrendered_factions and 5 in game.surrendered_factions, "remaining allied bots cannot prolong a fully surrendered human team")
	check(not game.hud.get_node("%MatchStatus").visible and not game.hud.get_node("%OnlineConfirm").visible, "match result clears spectator banner and confirmation")
	if _leave_controls:
		check(game.match_paused and game.pause_faction == 3, "reliable voluntary leave is processed even while global simulation is paused")
		await until(func(): return online.room.slots[3].surrendered and not online.room.slots[3].forfeit_requested and online.room.slots[3].player_id == -1, "Relay retains forfeit until Host commits surrender then releases departed identity", 8)
		check(online.room.slots[3].controller == "spectator" and 3 not in game._bot_factions, "voluntary departure cannot resurrect surrendered army under bot control")

func _phase(name: String, extra: Dictionary) -> void:
	var previous := read_json("phase")
	previous.merge(extra, true)
	previous.phase = name
	write_json("phase", previous)

func _take(name: String) -> void:
	var position: Vector3 = game.camera_rig.position
	write_json("capture", {"name": name, "x": position.x, "z": position.z})
	await pause(0.18)
	await capture(name)

func _focus(at: Vector3) -> void:
	game.camera_rig.focus_at(at, true)
	game.camera.size = 50.0

func _guest_review() -> void:
	while not read_json("expected").has("seq"):
		var phase := read_json("phase")
		if not phase.is_empty() and str(phase.phase) != _last_phase:
			_last_phase = str(phase.phase)
			await _guest_phase(phase)
			if _left_battle: return
		var request := read_json("capture")
		if not request.is_empty() and str(request.name) != _last_capture:
			_last_capture = str(request.name)
			_focus(Vector3(float(request.x), 0, float(request.z)))
			await pause(0.18)
			await capture(_last_capture)
		_cursor_clock += 1.0 / 30.0
		if _cursor_clock >= 0.15:
			_cursor_clock = 0.0
			game.get_node("TeammateCursors")._publish(Vector2(55, 0), true, true)
		await process_frame
	var expected := read_json("expected")
	await until(func(): return game.network_match._applied == int(expected.seq), "client receives final event sequence", 10)
	check(SNAPSHOT.digest(game.network_match._mirror) == str(expected.digest), "independent peer committed-state digest agrees")
	if _controls_mode:
		check(game.finished and game.winner_team == 0, "final surrender result is identical on this peer")
		check(not game.hud.get_node("%OnlineConfirm").visible, "final result dismisses any local surrender confirmation")
	if role == "ally":
		check(observed_visuals.has("skill"), "client receives replicated skill presentation events")
	else:
		check(observed_cursors.is_empty(), "enemy transport receives zero allied cursor packets")
	_write_peer_metrics(_peer_metrics())

func _peer_metrics() -> Dictionary:
	return {"resyncs": game.network_match.resync_count, "resync_reasons": game.network_match.resync_reasons,
		"received_rule_bytes": game.network_match.received_rule_bytes, "sent_rule_bytes": game.network_match.sent_rule_bytes,
		"received_transport_bytes": online.received_bytes, "sent_transport_bytes": online.sent_bytes, "visual_events": observed_visuals.size()}

func _write_peer_metrics(metrics: Dictionary) -> void:
	metrics.merge({"checks": checks, "failures": failures.size(), "messages": failures})
	print("PEER_METRICS ", JSON.stringify(metrics))
	write_json(role + "_done", metrics)

func _guest_voluntary_leave() -> void:
	_tap_key(KEY_F3)
	if not await until(func(): return game.match_paused, "last active ally pauses before voluntary leave", 10): return
	if not game._local_menu: _tap_key(KEY_ESCAPE)
	game.hud.get_node("%PauseExit").pressed.emit()
	var confirmation: Control = game.hud.get_node("%OnlineConfirm")
	check(confirmation.visible and confirmation.get_node("Center/Card/Column/Detail").text.contains("离开即视为投降"), "native leave confirmation explains voluntary forfeit")
	await pause(0.35)
	await capture("leave_confirm")
	var metrics := _peer_metrics()
	var old_battle: WeakRef = weakref(game)
	confirmation.get_node("Center/Card/Column/Actions/Confirm").pressed.emit()
	await until(func(): return current_scene != null and current_scene.scene_file_path == session.LOBBY_SCENE and not session.transition.busy, "confirmed guest leave returns through native Session to main menu", 10)
	check(old_battle.get_ref() == null and online.room.is_empty() and online.match_config.is_empty(), "leaving releases old battle and clears local match identity")
	await until(func(): return online._closing.is_empty(), "native reliable LEAVE transport drains before leaving client shuts down", 5)
	check(observed_visuals.has("skill"), "departed client had received replicated skill presentation events")
	_left_battle = true
	_write_peer_metrics(metrics)

func _check_garrison_visibility(stage: String) -> void:
	var local_viewer := true
	var badges_correct := true
	var badge_picking_correct := true
	var enemy_bodies_pickable := true
	var categories := {"own":0, "ally":0, "enemy":0, "neutral":0}
	for building: Node3D in game.buildings:
		var owner: int = building.faction
		var known: bool = owner < 0 or owner % 2 == game.local_faction % 2
		var category := "neutral" if owner < 0 else ("own" if owner == game.local_faction else ("ally" if known else "enemy"))
		categories[category] += 1
		local_viewer = local_viewer and building.viewer_faction == game.local_faction
		var label: Label3D = building.get_node("PopulationLabel")
		var badge: MeshInstance3D = building.get_node("PopulationBadge")
		var badge_collision: CollisionShape3D = building.get_node("PickArea/BadgeCollisionShape3D")
		var expected := str(maxi(0, floori(building.population))) if known else ""
		badges_correct = badges_correct and building.is_population_visible() == known and label.text == expected and label.visible == known and badge.visible == known
		badge_picking_correct = badge_picking_correct and badge_collision.disabled == (not known)
		if not known:
			var body_collision: CollisionShape3D = building.get_node("PickArea/CollisionShape3D")
			var body_screen: Vector2 = game.camera.unproject_position(body_collision.global_position)
			enemy_bodies_pickable = enemy_bodies_pickable and not body_collision.disabled and game.pick_building(body_screen) == building
	check(local_viewer, stage + " all buildings retain this client's nonzero viewer faction")
	check(badges_correct, stage + " own ally neutral show counts while enemy labels are empty and both population visuals are hidden")
	check(badge_picking_correct, stage + " only visible population badges retain their pick collision")
	check(enemy_bodies_pickable, stage + " enemy building bodies remain natively pickable without population badges")
	check(categories.values().all(func(amount: int): return amount > 0), stage + " real match covers own allied enemy and neutral buildings")
	print("GARRISON_VISIBILITY ", JSON.stringify({"role":role,"stage":stage,"viewer":game.local_faction,"categories":categories}))

func _guest_phase(phase: Dictionary) -> void:
	if _last_phase == "host_recovery":
		if not await until(func(): return online.room.get("phase") == "host_lost", "guest observes paused Host-loss room", 12): return
		var paused_at: float = game.elapsed
		await pause(0.7)
		check(is_equal_approx(game.elapsed, paused_at) and game.simulation_paused, "guest display clock stays frozen while Host is absent")
		write_json(role + "_host_paused", {"ready": true})
		if not await until(func(): return _human_restored(), "guest installs full snapshot after Host returns", 18): return
		_check_garrison_visibility("recovered")
		write_json(role + "_host_recovered", {"ready": true})
	elif _last_phase == "manual_pause":
		if role == "ally": _tap_key(KEY_F3)
		if not await until(func(): return game.match_paused, "peer receives global pause from ally F3", 10): return
		await pause(0.3)
		var frozen := _rule_sample()
		await pause(0.55)
		check(_rule_sample() == frozen, "global pause freezes complete replicated rule state")
		check(game.hud.get_node("%MatchStatus").visible and game.hud.get_node("%MatchPause").text.begins_with("继续对局"), "peer HUD reflects global pause with resume action")
		write_json(role + "_manual_paused", {"ready": true})
	elif _last_phase == "paused_reconnect" and role == "ally":
		await _guest_recovery(false)
		check(game.match_paused, "snapshot recovery retains manually paused battle")
		write_json("ally_paused_recovered", {"ready": true})
	elif _last_phase == "manual_resume" and role == "enemy":
		_tap_key(KEY_F3)
	elif _last_phase == "spectator_resume" and role == "ally":
		if not await until(func(): return 5 in game.surrendered_factions and game.match_paused, "ally receives Host surrender while paused", 10): return
		_tap_key(KEY_F3)
		if not await until(func(): return not game.match_paused, "active ally resumes surrendered Host's paused match", 10): return
		check(game.get_node("TeammateCursors")._peers.values().all(func(peer: Dictionary): return int(peer.faction) != 5 or not peer.visible), "surrendered Host no longer presents a teammate cursor")
		write_json("ally_host_spectating", {"ready": true})
	elif _last_phase == "team_surrender" and role == "ally":
		_confirm_surrender()
		await until(func(): return game.finished, "last human surrender receives finished battle", 10)
	elif _last_phase == "team_leave" and role == "ally":
		await _guest_voluntary_leave()
	elif role == "ally" and _last_phase in ["guest_short_recovery", "guest_long_recovery"]:
		await _guest_recovery(_last_phase == "guest_long_recovery")
	elif _last_phase == "march":
		var source: int = int(phase.rabbit_source if role == "ally" else phase.enemy_source)
		var target: int = 0 if role == "ally" else int(phase.bear_source)
		check(game.network_match.submit({"type": "dispatch", "source": source, "target": target, "percent": 100}).accepted, "remote dispatch submitted")
	elif role == "ally":
		if _last_phase in ["rush", "recall"]:
			var exposed: Array = game.marches.get_units()
			for unit: Dictionary in exposed:
				if int(unit.faction) == 3:
					game.network_match.submit({"type": "skill_ground", "skill": 0 if _last_phase == "rush" else 2, "x": unit.position.x, "z": unit.position.z})
					break
		elif _last_phase == "burrow":
			var source := int(phase.rabbit_source)
			game.network_match.submit({"type": "skill_building", "skill": 3, "target": source})
			if await until(func(): return game.by_id[source].burrow_remaining > 0, "replicated burrow-ready visual", 4):
				game.network_match.submit({"type": "dispatch", "source": source, "target": 0, "percent": 100})

func _human_restored() -> bool:
	return online.connection_state == "match" and not game.network_match._snapshot_loading and not game.network_match._recovery_waiting and (not game.simulation_paused or game.match_paused) and online.room.slots[online.local_faction].controller == "human"

func _guest_recovery(long_outage: bool) -> void:
	var original_scene := game.get_instance_id()
	var original_player: int = online.player_id
	var original_match: String = online.match_config.match_id
	var original_epoch: int = online.room.slots[3].control_epoch
	var applied_before: int = game.network_match._applied
	online.auto_reconnect = not long_outage
	online._lost(Time.get_ticks_msec())
	check(game.simulation_paused and not online._token.is_empty(), "disconnected guest freezes display and keeps recovery credential")
	if long_outage:
		if not await until(func(): return read_json("reconnect_ally").has("ready"), "guest stays offline through actual bot grace", 24): return
		online.auto_reconnect = true
		check(online._open() == OK, "guest opens native transport with retained original token")
	if not await until(func(): return _human_restored() and int(online.room.slots[3].control_epoch) > original_epoch, "guest catches up before regaining input", 18): return
	check(game.get_instance_id() == original_scene and current_scene == game and online.player_id == original_player and online.match_config.match_id == original_match, "guest restores same player and existing battle scene")
	check(game.network_match._applied >= applied_before, "recovered mirror never rolls back reliable fact sequence")
	write_json("ally_long_recovered" if long_outage else "ally_short_recovered", {"ready": true})

func _message(_sender: int, kind: String, payload: Dictionary) -> void:
	if kind == "events":
		for event: Dictionary in payload.get("visuals", []): observed_visuals.append(str(event.kind))

func _finish() -> void:
	if _finishing: return
	_finishing = true
	if is_instance_valid(game):
		await game.prepare_shutdown()
	online.disconnect_relay()
	if _public_mode:
		# Keep servicing the native reliable LEAVE handshake before shutting down
		# our test clients, so the public Relay can close this test room promptly.
		var disconnect_deadline := Time.get_ticks_msec() + 3200
		while not online._closing.is_empty() and Time.get_ticks_msec() < disconnect_deadline:
			await process_frame
	if role == "host":
		for process: int in children:
			if OS.is_process_running(process): OS.kill(process)
		if server != null: server.stop()
	print("MULTIPLAYER_VISUAL role=%s checks=%d failures=%d" % [role, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
