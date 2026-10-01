extends SceneTree
## Actual Q/W/R casts with authored native VFX, rendered on the private desktop.
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const EFFECTS: Array[String] = ["LockGrounds", "LockChains", "LockSeals", "LockShackles", "HostileGrounds", "Fractures", "Wards", "Orbs", "OrbBands"]
var game: Node3D
var output := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL BEAR_REWORK_VISUAL ", label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func step(seconds: float) -> void:
	for frame: int in ceili(seconds * 24.0):
		game.simulate(1.0 / 24.0)
		await process_frame

func reset_game(map_id: String = "rift") -> void:
	if game != null: await game.prepare_shutdown()
	var session: Node = root.get_node("Session")
	session.block_war_map_id = map_id
	session.block_war_commander = &"bear"
	session.block_war_opponent_commander = &"bear"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.select_building(null)
	game.hud.hide()
	await process_frame

func configure(target: WarBuilding, kind: int, faction: int) -> void:
	target.kind = kind
	target.level = 1
	target.faction = faction
	target.population = 80
	target.refresh_visual()
	game.sync_environment_bonuses()

func focus(target: WarBuilding, zoom := 16.0) -> void:
	game.camera.size = zoom
	game.camera_rig.global_position = target.global_position

func count(path: String) -> int:
	return game.world_effects.get_node("Bear/" + path).multimesh.visible_instance_count

func state() -> Array:
	var effects: Node3D = game.world_effects.get_node("Bear")
	var result: Array = [effects.time]
	for path: String in EFFECTS:
		var mesh: MultiMesh = effects.get_node(path).multimesh
		result.append([mesh.visible_instance_count, mesh.buffer])
	return result

func check_pause(label: String) -> void:
	game.set_paused(true)
	game.hud.hide()
	var before := state()
	game.simulate(0.7)
	await process_frame
	check(state() == before, label + " native visual state paused")
	game.set_paused(false)
	game.hud.hide()

func upgrade_review(kind: int) -> void:
	await reset_game()
	var target: WarBuilding = game.buildings[0]
	configure(target, kind, 0)
	focus(target)
	var population := target.population
	if target.max_level == 1:
		check(not game.cast_skill(0, target), "Q rejects max-level utility building %d" % kind)
		check(count("UpgradeSweeps") == 0, "Q rejected cast has no sweep")
		return
	check(game.cast_skill(0, target), "Q kind %d cast" % kind)
	check(target.level == 2 and target.population == population, "Q kind %d immediate free level" % kind)
	await step(0.29)
	check(count("UpgradeSweeps") == 1, "Q one upward completion sweep")
	await capture("q_%d_build" % kind)
	await step(0.25)
	await capture("q_%d_lift" % kind)
	await step(0.85)
	check(count("UpgradeSweeps") == 0, "Q sweep clears")
	await capture("q_%d_complete" % kind)

func lock_review(kind: int, elevated := false) -> void:
	await reset_game("terraces" if elevated else "rift")
	var target: WarBuilding = game.buildings[6]
	configure(target, kind, 1)
	focus(target)
	var destination: WarBuilding = game.buildings[0]
	check(game.issue_order(target, destination, 50, 1) > 0, "W starts pending dispatch")
	game.marches.tick(0.05)
	check(game.cast_skill(1, target), "W kind %d cast" % kind)
	check(target.queued_population == 0, "W cancels pending soldiers")
	await step(0.4)
	check(count("LockChains") == 48 and count("LockSeals") == 1 and count("LockShackles") == 1, "W complete chain and lock")
	check(count("Wards") == 0, "W no shield")
	await capture("w_%d_%s_locked" % [kind, "elevated" if elevated else "flat"])
	await check_pause("W")
	var chains: MultiMesh = game.world_effects.get_node("Bear/LockChains").multimesh
	var above_ground := true
	for index: int in chains.visible_instance_count:
		var at := chains.get_instance_transform(index).origin
		above_ground = above_ground and at.y > game.map.definition.surface_height(Vector2(at.x, at.z))
	check(above_ground, "W chains stay above authored terrain")
	await step(RULES.BEAR_DURATIONS[1])
	check(count("LockChains") == 0 and count("LockSeals") == 0 and count("LockGrounds") == 0, "W all lock visuals expire")
	await capture("w_%d_released" % kind)

func ward_review(hostile: bool, kind: int) -> void:
	await reset_game()
	var target: WarBuilding = game.buildings[6] if hostile else game.buildings[0]
	configure(target, kind, 1 if hostile else 0)
	focus(target)
	var center := target.global_position
	game.marches.send(target.building_id, game.buildings[0].building_id, 1, 80, PackedVector3Array([center + Vector3(9, 0, 4), center + Vector3(-20, 0, 4)]))
	game.marches.tick(0.5)
	check(game.cast_skill(3, target), "R %s kind %d cast" % [hostile, kind])
	await step(0.65)
	check(count("Wards") == (0 if hostile else 1), "R shield only allies")
	check(count("Fractures") == (1 if hostile else 0) and count("HostileGrounds") == (1 if hostile else 0), "R fractures only enemies")
	check(count("Orbs") == 1 and count("OrbBands") == 1, "R persistent overhead fireball")
	var label := "r_%s_%d" % ["hostile" if hostile else "friendly", kind]
	await capture(label + "_close")
	await check_pause(label)
	focus(target, 45.0)
	game.hud.show()
	game.update_hud()
	await capture(label + "_normal")
	game.hud.hide()
	await step(RULES.BEAR_DURATIONS[3])
	check(count("Wards") == 0 and count("Orbs") == 0 and count("Fractures") == 0 and count("HostileGrounds") == 0, "R all sustained visuals clear")

func pool_review() -> void:
	await reset_game()
	var effects: Node3D = game.world_effects.get_node("Bear")
	# A replicated match may display all six casters together, or retain expired
	# rows until their reliable removal arrives. Exercise that presentation state.
	for faction: int in 6:
		var target: WarBuilding = game.buildings[faction]
		var id := target.building_id
		game.bear.locks[id] = {"faction": faction, "remaining": 5.5}
		game.bear.wards[id] = {"faction": faction, "remaining": 5.5, "pulse": 0.25, "hostile": faction % 2 == 1}
		effects.toolbox(faction, target.global_position)
	effects.sync(game.bear, game.marches, game.by_id, 0.5)
	check(count("LockChains") == 288 and count("LockSeals") == 6, "six lock casters fit authored pools")
	check(count("Wards") == 3 and count("Fractures") == 3 and count("Orbs") == 6, "mixed ward relationships have separate native pools")
	check(count("UpgradeSweeps") == 6, "six simultaneous upgrades fit authored pool")
	for locked: Dictionary in game.bear.locks.values(): locked.remaining = 0.0
	for ward: Dictionary in game.bear.wards.values(): ward.remaining = 0.0
	effects.sync(game.bear, game.marches, game.by_id, 1.0)
	for path: String in EFFECTS:
		check(count(path) == 0, "stale expired replica row hides " + path)
	check(count("UpgradeSweeps") == 0, "all transient upgrade sweeps finish")

func _run() -> void:
	create_timer(220.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	if OS.get_cmdline_user_args().has("--hud-only"):
		await reset_game()
		game.hud.show()
		game.update_hud()
		await create_timer(0.8).timeout
		await capture("bear_rework_hud")
		await game.prepare_shutdown()
		print("BEAR_REWORK_HUD_COMPLETE")
		quit()
		return
	for kind: int in 4:
		await upgrade_review(kind)
		await lock_review(kind, kind == 3)
		await ward_review(kind % 2 == 1, kind)
	await pool_review()
	await game.prepare_shutdown()
	print("BEAR_REWORK_VISUAL_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
