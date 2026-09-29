extends SceneTree
const NETWORK := preload("res://scripts/network/war_network_match.gd")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var output := ""

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL BLAST ", label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "save " + label)

func _run() -> void:
	create_timer(55.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	root.size = Vector2i(1280, 720)
	root.get_node("Session").block_war_map_id = "rift"
	root.get_node("Session").block_war_commander = &"frog"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	game.hud.hide()
	game.get_node("Orders").hide()
	var target: WarBuilding = game.by_id[1]
	target.kind = 0; target.level = 4; target.population = 100.0; target.faction = 1
	target.refresh_visual()
	game.camera.size = 19.0
	game.camera_rig.position = target.global_position
	game.energy = 100.0
	var blast: MultiMeshInstance3D = game.world_effects.get_node("BlastCasualties")
	game.presentation_event.connect(func(kind: String, payload: Dictionary):
		if kind == "garrison_blast": events.append({"kind": kind, "payload": payload.duplicate(true)}))
	await capture("frog_before")
	check(game.cast_skill(3, target), "real frog strike accepts a defended upgraded house")
	check(target.population == 20.0 and target.level == 1, "strike still removes 80 and downgrades immediately")
	check(blast.bodies.size() == 8 and game.marches._units.is_empty(), "fixed visual casualties never become live troops")
	check(events.size() == 1 and not events[0].payload.has("population"), "replication sends one visual sample without a garrison count")
	for step: int in 6:
		game.world_effects.tick(0.05)
		game.world_effects.get_node("Frog").sync(game.marches, 0.05)
		await process_frame
	await capture("frog_airborne")
	var airborne := 0
	for index: int in blast.multimesh.visible_instance_count:
		if blast.multimesh.get_instance_transform(index).origin.y > target.global_position.y + 1.0: airborne += 1
	check(airborne >= 6, "explosion visibly throws most bodies above the roof base")
	game.world_effects.tick(0.47)
	game.world_effects.get_node("Frog").sync(game.marches, 0.47)
	await capture("frog_landing")
	game.world_effects.tick(0.50)
	check(blast.bodies.is_empty() and blast.multimesh.visible_instance_count == 0, "short ragdolls completely disappear after landing")
	check(target.population == 20.0, "visual lifetime does not apply extra damage")
	var receiver := NETWORK.new()
	receiver.game = game
	receiver._play_presentation(events[0])
	check(blast.bodies.size() == 8, "client replays the same visual burst")
	check(events.size() == 1 and target.population == 20.0, "client playback creates no authority events or gameplay changes")
	blast.clear()
	for bad: Dictionary in [{"count": 10000}, {"delay": -1.0}, {"faction": 8}, {"at": [INF, 0, 0]}]:
		var event: Dictionary = events[0].duplicate(true)
		event.payload.merge(bad, true)
		receiver._play_presentation(event)
	check(blast.bodies.is_empty(), "malformed visual packets cannot fill the instance pool")
	game.faction_skills[0].commander = &"fox"
	game.energy = 100; game.cooldowns.fill(0.0)
	target.population = 50.0
	check(game.cast_skill(0, target), "real fox bomb casts")
	check(target.population == 25.0, "fox casualties keep their existing instant rules")
	check(blast.multimesh.visible_instance_count == 0, "fox bodies wait for the visible bomb contact")
	blast.tick(0.17)
	check(blast.multimesh.visible_instance_count == 0, "no premature fox ejection")
	blast.tick(0.02)
	check(blast.multimesh.visible_instance_count == 8, "fox ejection starts with the 0.18 second impact")
	blast.clear()
	target.faction = -1; target.population = 1.0
	game.world_effects.garrison_blast(target, 0.5)
	check(blast.bodies.is_empty(), "fractional losses do not invent a whole dead soldier")
	game.world_effects.garrison_blast(target, 1.0)
	check(blast.bodies.size() == 1 and blast.bodies[0].faction == -1, "neutral garrisons have a valid neutral body tint")
	blast.clear()
	game.world_effects.casualty(target.global_position, Vector3.FORWARD, 0, Vector3(1, 1, 0), false)
	check(blast.bodies.size() == 1, "exposed troops hit by an upward blast also tumble")
	blast.tick(2.0)
	check(blast.bodies.is_empty(), "exposed blast bodies also expire")
	target.faction = 1
	for loss: float in [1.0, 4.0, 17.0, 80.0]:
		blast.clear()
		game.world_effects.garrison_blast(target, loss)
		check(blast.bodies.size() == 8 and events[-1].payload.count == 8, "enemy visual sample cannot reveal low garrisons from the casualty count")
	print("BLOCK_WAR_BLAST_CASUALTIES checks=%d failures=%d" % [checks, failures.size()])
	await game.prepare_shutdown()
	quit(0 if failures.is_empty() else 1)
