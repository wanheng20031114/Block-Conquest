extends SceneTree
## Selection motion must coexist with real match transitions and independent recoil.

var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func step(tween: Tween, seconds: float) -> void:
	tween.pause()
	tween.custom_step(seconds)

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	var home: WarBuilding = game.by_id[0]
	var body: Node3D = home.get_node("Visual")
	var badge: Node3D = home.get_node("PopulationBadge")
	var label: Node3D = home.get_node("PopulationLabel")
	var pick: Node3D = home.get_node("PickArea")
	var ring: Node3D = home.get_node("SelectionRing")
	var rest := body.transform
	var badge_rest := badge.global_transform
	var label_rest := label.global_transform
	var pick_rest := pick.global_transform
	var root_rest := home.global_transform
	var node_count := home.find_children("*", "", true, false).size()
	for kind: int in [0, 1, 2]:
		home.kind = kind
		for tier: int in range(1, home.max_level + 1):
			home.level = tier
			home.refresh_visual()
			game.select_building(home)
			var motion := home._selection_body_tween
			var lowest := 1.0
			var highest := 1.0
			var stable := true
			var volume_error := 0.0
			for frame: int in 40:
				if motion.is_valid():
					step(motion, 1.0 / 60.0)
				lowest = minf(lowest, body.scale.y)
				highest = maxf(highest, body.scale.y)
				volume_error = maxf(volume_error, absf(body.basis.determinant() - rest.basis.determinant()))
				stable = stable and badge.global_transform.is_equal_approx(badge_rest) and label.global_transform.is_equal_approx(label_rest) and pick.global_transform.is_equal_approx(pick_rest) and home.global_transform.is_equal_approx(root_rest) and body.position.is_equal_approx(rest.origin)
			check(lowest < 0.91 and highest > 1.06, "each authored building tier compresses and rebounds visibly")
			check(volume_error < 0.0001, "rebound preserves building volume")
			check(body.transform.is_equal_approx(rest), "each tier settles exactly to its authored transform")
			check(stable, "feet, population badge, number, pick area and building position stay fixed throughout motion")
			check(home.find_children("*", "", true, false).size() == node_count, "selection reuses the authored scene")
	# Rapid clicks replace the previous tween without snapping or compounding scale.
	game.select_building(home)
	step(home._selection_body_tween, 0.18)
	var prior_motion := home._selection_body_tween
	var prior_pose := body.transform
	game.select_building(home)
	step(home._selection_body_tween, 0.0)
	check(not prior_motion.is_valid() and body.transform.is_equal_approx(prior_pose), "re-click starts continuously from the current pose")
	var bounded := true
	for click: int in 30:
		game.select_building(home)
		step(home._selection_body_tween, 1.0 / 120.0)
		bounded = bounded and body.scale.y >= 0.895 and body.scale.y <= 1.075
	check(bounded, "rapid repeated clicks cannot accumulate deformation")
	prior_pose = body.transform
	game.select_building(null)
	check(not ring.visible and body.transform.is_equal_approx(prior_pose), "deselect hides the marker without popping the building")
	step(home._selection_body_tween, 1.0)
	check(body.transform.is_equal_approx(rest), "deselected building finishes settling")
	# Pause uses the actual match pause path and native Tween processing.
	game.select_building(home)
	step(home._selection_body_tween, 0.08)
	step(home._selection_tween, 0.08)
	game.set_paused(true)
	prior_pose = body.transform
	var ring_pose := ring.transform
	for frame: int in 12:
		await process_frame
	check(body.transform.is_equal_approx(prior_pose) and ring.transform.is_equal_approx(ring_pose), "pause freezes both body and selection ring")
	game.set_paused(false)
	for frame: int in 45:
		await process_frame
	check(body.transform.is_equal_approx(rest) and ring.scale.is_equal_approx(Vector3.ONE), "resume finishes the same native tweens")
	game.set_paused(true)
	game.select_building(home)
	for frame: int in 6:
		await process_frame
	check(body.transform.is_equal_approx(rest) and not home._selection_body_tween.is_running(), "a selection created while paused starts paused")
	game.set_paused(false)
	# Upgrade and conversion completion take over a moving selection seamlessly.
	home.kind = 0
	home.level = 1
	home.population = 200.0
	home.refresh_visual()
	for conversion: bool in [false, true]:
		game.select_building(home)
		step(home._selection_body_tween, 0.18)
		prior_pose = body.transform
		prior_motion = home._selection_body_tween
		if conversion:
			game.convert_selected(1)
		else:
			game.upgrade_selected()
		check(home.advance_construction(10.0), "actual construction completes after its ten-second duration")
		check(not prior_motion.is_valid() and body.transform.is_equal_approx(prior_pose), "completion replaces rebound without resetting its current pose")
		check((home.kind == 1 and home.level == 1) if conversion else (home.kind == 0 and home.level == 2), "completion changes to the intended model")
		var completion := home._capture_tween
		step(completion, 0.1)
		game.select_building(home)
		check(home._capture_tween == completion and not home._selection_body_tween.is_valid(), "clicking during completion does not stack another body tween")
		step(completion, 1.0)
		await process_frame
		check(body.transform.is_equal_approx(rest), "completion settles to the original scale")
	# Actual capture cancels construction, drops one tier and owns the animation.
	home.level = 3
	home.refresh_visual()
	game.select_building(home)
	step(home._selection_body_tween, 0.08)
	home.begin_construction(2)
	prior_pose = body.transform
	game._on_unit_arrived(home.building_id, 1, 1000.0)
	check(home.faction == 1 and home.level == 2 and not home.is_constructing, "capture still switches faction, downgrades and cancels work")
	check(not home._selection_body_tween.is_valid() and body.transform.is_equal_approx(prior_pose), "capture takes over from the current selection pose")
	step(home._capture_tween, 1.0)
	await process_frame
	# Recoil controls its own child transform while selection moves the full model.
	game.select_building(home)
	step(home._selection_body_tween, 0.08)
	home.fire_at(home.global_position + Vector3(8, 0, -5))
	step(home._recoil_tween, 0.04)
	var barrel: Node3D = home.get_node("Visual/Tower/Gun/Barrel")
	var gun: Node3D = home.get_node("Visual/Tower/Gun")
	var barrel_pose := barrel.transform
	var aim := gun.rotation
	check(barrel.position.z > 0.05 and body.scale.y < 0.95, "cannon recoil and selection rebound are visible together (recoil=%.4f, height=%.4f)" % [barrel.position.z, body.scale.y])
	step(home._selection_body_tween, 1.0)
	check(barrel.transform.is_equal_approx(barrel_pose) and gun.rotation.is_equal_approx(aim), "selection cannot overwrite cannon aim or recoil")
	check(home.muzzle_position().is_equal_approx(home.get_node("Visual/Tower/Gun/Barrel/Muzzle").global_position), "projectile origin follows the transformed muzzle")
	step(home._recoil_tween, 1.0)
	check(body.transform.is_equal_approx(rest) and is_zero_approx(barrel.position.z), "body and barrel settle independently")
	game.select_building(home)
	var pending_motion := home._selection_body_tween
	await game.prepare_shutdown()
	game.queue_free()
	await process_frame
	check(not pending_motion.is_valid(), "leaving the match kills its bound selection tween")
	print("BLOCK_WAR_SELECTION_MOTION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
