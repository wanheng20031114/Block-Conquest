extends SceneTree
## GPU review of the saved sculptures. No combat entities or roster registration.
const OUTPUT := "res://.local/zombie-variants/"
var study: Node3D

func _initialize() -> void:
	run.call_deferred()

func capture() -> Image:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	return picture

func pose(clip: String, time: float) -> void:
	var model: UnitVisual = study.model
	model.locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.attack.stop()
	model.locomotion.play("idle")
	model.locomotion.seek(0, true)
	if clip in ["strike", "rally"]:
		model.attack.play(clip)
		model.attack.seek(time, true)
	else:
		model.locomotion.play(clip)
		model.locomotion.seek(time, true)

func run() -> void:
	create_timer(180, true, false, true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(20000, 20000))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(720, 800)
	root.content_scale_size = Vector2i(720, 800)
	change_scene_to_file("res://tests/fixtures/zombie_variants_study.tscn")
	await scene_changed
	study = current_scene
	await process_frame
	study.get_node("Overlay").hide()
	study.camera.size = 2.85
	var groups: Array = [[0,1,2],[3,4,5],[6,7]]
	var group_names: Array[String] = ["ranged", "tools", "special"]
	var contacts: Array[float] = [.45,.65,.35,.40,.50,.55,.35,.40]
	for group_index in groups.size():
		var indices: Array = groups[group_index]
		var gallery := Image.create(720 * indices.size(), 800, false, Image.FORMAT_RGBA8)
		var angles := Image.create(480 * 3, 540 * indices.size(), false, Image.FORMAT_RGBA8)
		var actions := Image.create(480 * 3, 540 * indices.size(), false, Image.FORMAT_RGBA8)
		var follow_through := Image.create(480 * 3, 540 * indices.size(), false, Image.FORMAT_RGBA8)
		for column in indices.size():
			var index: int = indices[column]
			study.select_model(index)
			study.get_node("Turntable").rotation.y = 0
			pose("idle", 0)
			root.size = Vector2i(720,800)
			root.content_scale_size = root.size
			gallery.blit_rect(await capture(), Rect2i(0,0,720,800), Vector2i(column * 720,0))
			root.size = Vector2i(480,540)
			root.content_scale_size = root.size
			for angle in 3:
				study.get_node("Turntable").rotation.y = deg_to_rad([90.0,180.0,270.0][angle])
				angles.blit_rect(await capture(), Rect2i(0,0,480,540), Vector2i(angle * 480,column * 540))
			study.get_node("Turntable").rotation.y = 0
			for step in 3:
				if step == 0: pose("walk", .86)
				elif index == 6: pose("rally", .45 if step == 1 else .98)
				else: pose("strike", contacts[index] * .6 if step == 1 else contacts[index] + .001)
				actions.blit_rect(await capture(), Rect2i(0,0,480,540), Vector2i(step * 480,column * 540))
			for step in 3:
				var samples: Array = [[.451,.95,1.35],[.651,1.65,1.92],[.351,.81,1.12],[.401,.58,.83],[.501,.65,.95],[.551,.68,.98],[.62,.80,1.16],[.401,.53,.82]]
				pose("rally" if index == 6 else "strike", samples[index][step])
				follow_through.blit_rect(await capture(), Rect2i(0,0,480,540), Vector2i(step * 480,column * 540))
		gallery.save_png(OUTPUT + group_names[group_index] + ".png")
		angles.save_png(OUTPUT + group_names[group_index] + "-angles.png")
		actions.save_png(OUTPUT + group_names[group_index] + "-actions.png")
		follow_through.save_png(OUTPUT + group_names[group_index] + "-follow.png")
	root.size = Vector2i(1600,900)
	root.content_scale_size = root.size
	study.get_node("Overlay").show()
	study.camera.size = 3.4
	study.select_model(6)
	pose("idle", 0)
	(await capture()).save_png(OUTPUT + "preview.png")
	print("ZOMBIE_VARIANTS_GPU_REVIEW_COMPLETE ", OUTPUT)
	study.queue_free()
	await process_frame
	quit()
