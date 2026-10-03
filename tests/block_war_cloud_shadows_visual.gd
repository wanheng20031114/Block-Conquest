extends SceneTree
## Actual battle rendering: moving world shadows, pause, and unchanged HUD.

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _capture(path: String) -> Image:
	for frame: int in 14:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image.save_png(path) == OK, "Cloud shadow capture saves")
	return image

func _difference(before: Image, after: Image, region: Rect2i) -> Dictionary:
	var darkened := 0
	var changed := 0
	var count := 0
	for y: int in range(region.position.y, region.end.y, 4):
		for x: int in range(region.position.x, region.end.x, 4):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var delta := (a.r + a.g + a.b - b.r - b.g - b.b) / 3.0
			darkened += int(delta > 0.035)
			changed += int(absf(delta) > 0.035)
			count += 1
	return {"darkened": float(darkened) / count, "changed": float(changed) / count}

func _capture_clip(game: Node3D, animation: AnimationPlayer, directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	root.size = Vector2i(1280, 720)
	game.get_node("HUD").hide()
	game.get_node("Orders").hide()
	game.camera.size = 61.0
	game.camera_rig.zoom_target = 61.0
	for frame: int in 241:
		animation.seek(float(frame) / 12.0, true)
		await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join("%04d.png" % frame)
		_check(root.get_texture().get_image().save_png(path) == OK, "Cloud drift video frame saves")
	print("CLOUD_SHADOW_CLIP ", directory, " frames=241 fps=12 duration=20")
	root.size = Vector2i(1600, 900)

func _run() -> void:
	var clip := "--clip" in OS.get_cmdline_user_args()
	create_timer(200.0 if clip else 100.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	var output := OS.get_cmdline_user_args()[0]
	var session := root.get_node("Session")
	for stage_index: int in 2:
		session.campaign_active_stage = stage_index
		session.block_war_map_id = session.CAMPAIGN_STAGES[stage_index].map_id
		session.block_war_opponent_commander = session.CAMPAIGN_STAGES[stage_index].opponent_commander
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.ai_enabled = false
		game.audio.muted = true
		game.camera.size = 67.0
		game.camera_rig.zoom_target = 67.0
		game.camera_rig.focus_at(Vector3.ZERO, true)
		var clouds: Node3D = game.get_node("CloudShadows")
		var animation: AnimationPlayer = clouds.get_node("AnimationPlayer")
		_check(clouds.find_children("*", "MeshInstance3D", true, false).all(
			func(mesh: MeshInstance3D): return mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		), "All native clouds cast shadows without showing sky geometry")
		game.set_paused(true)
		var pause_time := animation.current_animation_position
		for frame: int in 4:
			await process_frame
		_check(is_equal_approx(pause_time, animation.current_animation_position), "Pausing freezes clouds")
		game.set_paused(false)
		for frame: int in 4:
			await process_frame
		_check(animation.current_animation_position > pause_time, "Resuming continues cloud drift")
		animation.speed_scale = 0.0
		game.map.set_visual_paused(true)
		for building: Node3D in game.buildings:
			building.set_visual_paused(true)
		clouds.hide()
		var prefix: String = session.block_war_map_id
		var clear := await _capture(output.path_join(prefix + "-clear.png"))
		clouds.show()
		animation.seek(0.0, true)
		var zero := await _capture(output.path_join(prefix + "-clouds-00.png"))
		animation.seek(20.0, true)
		var twenty := await _capture(output.path_join(prefix + "-clouds-20.png"))
		animation.seek(80.0, true)
		var eighty := await _capture(output.path_join(prefix + "-clouds-80.png"))
		var world_region := Rect2i(160, 150, 1280, 500)
		var coverage := _difference(clear, zero, world_region)
		var motion := _difference(zero, twenty, world_region)
		var longer_motion := _difference(zero, eighty, world_region)
		var hud_motion := _difference(zero, eighty, Rect2i(410, 18, 780, 14))
		print("CLOUD_SHADOW_METRICS ", prefix, " coverage=", coverage,
			" motion_20s=", motion, " motion_80s=", longer_motion, " HUD=", hud_motion)
		_check(coverage.darkened > 0.035 and coverage.darkened < 0.5, "Dispersed shadows visibly shade part of the battlefield")
		_check(motion.changed > 0.018, "Cloud shadows move visibly after 20 seconds")
		_check(longer_motion.changed > motion.changed, "Longer drift changes more of the field")
		_check(hud_motion.changed < 0.001, "Cloud shadows do not darken HUD")
		var changed_roofs := 0
		for building: Node3D in game.buildings:
			var roof_pixel: Vector2i = Vector2i(game.camera.unproject_position(building.global_position + Vector3(0, 3, 0)))
			var roof_region := Rect2i(roof_pixel - Vector2i(12, 5), Vector2i(24, 10))
			if _difference(zero, eighty, roof_region).changed > 0.15:
				changed_roofs += 1
		_check(changed_roofs > 0, "Native cloud shadows also move across building roofs")
		if clip:
			await _capture_clip(game, animation, output.path_join(prefix + "-clip"))
		await game.prepare_shutdown()
	print("CLOUD_SHADOW_VISUAL_COMPLETE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
