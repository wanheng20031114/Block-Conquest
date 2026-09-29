extends SceneTree
## Real frog casts, representative battlefield frames, and effect lifecycle checks.

var game: Node3D
var output: String
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL FROG_VFX ", label)

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, label + " captures the real battlefield")

func _step(frames: int) -> void:
	for frame: int in frames:
		game.simulate(1.0 / 24.0)
		await process_frame

func _reset(center: Vector3) -> void:
	if game != null:
		await game.prepare_shutdown()
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
	# The review can inspect the outermost fort without the player's pan clamp.
	game.camera_rig.position = center
	game.camera.size = 20.0
	await process_frame

func _run() -> void:
	create_timer(75.0, true, false, true).timeout.connect(func(): quit(3))
	output = OS.get_cmdline_user_args()[0]
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	var session := root.get_node("Session")
	session.block_war_map_id = "rift"
	session.block_war_commander = &"frog"
	session.block_war_opponent_commander = &"frog"
	var center := Vector3(-23, 0, 4)
	for skill: int in [0, 1, 2]:
		await _reset(center)
		game.marches.send(0, 1, 0, 24, PackedVector3Array([center + Vector3(-3, 0, -1), center + Vector3(30, 0, -1)]))
		game.marches.send(1, 0, 1, 24, PackedVector3Array([center + Vector3(3, 0, 1), center + Vector3(-30, 0, 1)]))
		game.marches.tick(0.8)
		await _capture("frog_%d_before" % skill)
		_check(game.cast_ground_skill(skill, center), "ground skill %d casts through the real paid path" % skill)
		var effect: Node3D = game.world_effects.get_node("Frog")
		_check(effect.get_node("CastBlooms").multimesh.visible_instance_count == 1, "ground skill %d has a native release bloom" % skill)
		await _step(4)
		await _capture("frog_%d_release" % skill)
		await _step(12)
		await _capture("frog_%d_active" % skill)
		await _step(8)
		_check(effect.blooms.is_empty() and effect.get_node("CastBlooms").multimesh.visible_instance_count == 0, "ground skill %d release finishes independently of its lasting status" % skill)
		game.camera.size = 58.0
		await _step(1)
		await _capture("frog_%d_battle" % skill)
	await _reset(Vector3.ZERO)
	var target: WarBuilding = game.buildings[1]
	target.kind = 0
	target.level = 4
	target.population = 100.0
	target.faction = 1
	target.refresh_visual()
	game.camera_rig.position = target.global_position + Vector3(0, 0, 1)
	game.camera.size = 18.0
	await _capture("frog_r_before")
	var marching_count: int = game.marches._units.size()
	_check(game.cast_skill(3, target), "R casts through the real paid path")
	_check(target.level == 1 and is_equal_approx(target.population, 20.0), "R still downgrades and removes eighty percent in the same frame")
	_check(game.marches._units.size() == marching_count, "R visual casualties do not create combat soldiers")
	var effect: Node3D = game.world_effects.get_node("Frog")
	_check(effect.get_node("Cuts").multimesh.visible_instance_count == 2, "R renders both authored slash passes immediately")
	await _capture("frog_r_release")
	await _step(3)
	await _capture("frog_r_impact")
	game.set_paused(true)
	var frozen_time: float = effect.time
	var frozen_cut: float = effect.cuts[0].age
	game.simulate(0.4)
	await process_frame
	_check(effect.time == frozen_time and effect.cuts[0].age == frozen_cut, "pause freezes the slash simulation clock")
	for path: String in ["Puffs", "Flecks", "StrikeDust", "Rubble"]:
		_check(effect.get_node(path).speed_scale == 0.0, "pause freezes native " + path)
	game.set_paused(false)
	await _step(6)
	await _capture("frog_r_flight")
	await _step(9)
	await _capture("frog_r_landing")
	await _step(18)
	await _capture("frog_r_after")
	_check(effect.cuts.is_empty() and effect.get_node("Cuts").multimesh.visible_instance_count == 0, "the strike slash pool clears after its authored lifetime")
	_check(target.level == 1 and target.population >= 20.0, "visual aftermath never removes additional garrison")
	game.faction_skills[0].cooldowns[3] = 0.0
	game.energy = 100.0
	target.level = 4
	target.population = 100.0
	target.refresh_visual()
	game.camera.size = 58.0
	_check(game.cast_skill(3, target), "R recasts cleanly after refilling the review account")
	await _step(4)
	await _capture("frog_r_battle")
	await game.prepare_shutdown()
	print("FROG_VFX_REVIEW checks=", checks, " failures=", failures.size(), " output=", output)
	quit(0 if failures.is_empty() else 1)
