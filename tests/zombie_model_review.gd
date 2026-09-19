extends SceneTree
## Native model/animation review only. Does not spawn a BattleUnit or add a roster entry.
const OUTPUT := "res://.local/zombie-review/"
var checks := 0
var failures: Array[String] = []
var study: Node3D
var model: UnitVisual

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ZOMBIE_FAIL ", label)

func capture() -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func pose(clip: String, time: float) -> void:
	model.attack.stop()
	model.locomotion.play("idle")
	model.locomotion.seek(0, true)
	if clip == "strike":
		model.attack.play(clip)
		model.attack.seek(time, true)
	else:
		model.locomotion.play(clip)
		model.locomotion.seek(time, true)

func foot_minimum(side: String) -> float:
	var mesh: MeshInstance3D = model.get_node("Rig/Action/Step" + side + "/Leg" + side)
	var minimum := INF
	for vertex: Vector3 in mesh.mesh.get_faces():
		minimum = minf(minimum, (mesh.global_transform * vertex).y)
	return minimum

func run() -> void:
	create_timer(90, true, false, true).timeout.connect(func(): quit(3))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(20000, 20000))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1280, 900)
	root.content_scale_size = Vector2i(1280, 900)
	change_scene_to_file("res://tests/fixtures/zombie_model_study.tscn")
	await scene_changed
	study = current_scene
	model = study.model
	for i in 6: await process_frame
	model.locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model._refresh_animation_visibility()
	pose("idle", 0)
	(await capture()).save_png(OUTPUT + "preview.png")

	var definition: UnitDefinition = load("res://data/prototypes/monsters/zombie.tres")
	check(definition.hp == 100 and definition.damage == 10, "requested life and attack")
	check(definition.melee_armor == 0 and definition.ranged_armor == 0, "no armor")
	check(definition.damage_channel == CombatDefinition.DamageChannel.MELEE and definition.projectile.is_empty(), "unarmed melee definition")
	check(definition.validation_errors().is_empty(), "valid standalone definition")
	check(not BalanceCatalog.UNITS.has("zombie"), "not registered in live balance catalog")
	check(not FileAccess.get_file_as_string("res://scenes/model_previews.tscn").contains("zombie"), "not registered in codex portraits")
	check(not FileAccess.get_file_as_string("res://scenes/sandbox_model_previews.tscn").contains("zombie"), "not registered in sandbox portraits")
	var meshes := model.get_node("Rig").find_children("*", "MeshInstance3D", true, false)
	var triangles := 0
	var marked_parts: Array[String] = []
	for mesh: MeshInstance3D in meshes:
		triangles += mesh.mesh.get_faces().size() / 3
		var colors: PackedColorArray = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var marked := false
		for color: Color in colors:
			if color.a > .75: marked = true
		check(colors.size() > 0, mesh.name + " has authored vertex paint")
		if marked: marked_parts.append(mesh.name)
	check(meshes.size() == 8 and triangles <= 3000, "eight rigid parts within triangle budget")
	check(marked_parts == ["ArmLeft"], "team marking limited to left armband")
	for player: AnimationPlayer in [model.locomotion, model.attack]:
		for clip_name: StringName in player.get_animation_list():
			var clip := player.get_animation(clip_name)
			for track: int in clip.get_track_count():
				check(model.has_node(clip.track_get_path(track)), "saved animation path resolves: " + str(clip.track_get_path(track)))
	for index in 49:
		pose("walk", 1.08 * index / 48.0)
		check(foot_minimum("Left") >= -.008 and foot_minimum("Right") >= -.008, "walking feet stay above ground " + str(index))
	var left: MeshInstance3D = model.get_node("Rig/Action/StepLeft/LegLeft")
	pose("walk", 1.08 * .10)
	var stance_start: float = (left.global_transform * Vector3(0, -.65, -.06)).z
	pose("walk", 1.08 * .42)
	check((left.global_transform * Vector3(0, -.65, -.06)).z > stance_start + .1, "planted foot moves backward")
	pose("walk", 1.08 * .66)
	var swing_start: float = (left.global_transform * Vector3(0, -.65, -.06)).z
	pose("walk", 1.08 * .91)
	check((left.global_transform * Vector3(0, -.65, -.06)).z < swing_start - .1, "lifted foot returns forward")
	pose("strike", 0)
	var hand_start: Vector3 = model.get_projectile_origin()
	pose("strike", .30)
	check(model.get_projectile_origin().z < hand_start.z - .15, "open hand reaches forward at 0.30s contact")
	pose("strike", .82)
	check(model.get_projectile_origin().distance_to(hand_start) < .0001, "strike returns to rest pose")

	study.get_node("Overlay").hide()
	root.size = Vector2i(600, 600)
	root.content_scale_size = Vector2i(600, 600)
	study.camera.size = 2.65
	pose("idle", 0)
	var gallery := Image.create(1800, 1200, false, Image.FORMAT_RGBA8)
	var index := 0
	for angle: float in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
		study.get_node("Turntable").rotation.y = deg_to_rad(angle)
		var picture := await capture()
		picture.convert(Image.FORMAT_RGBA8)
		gallery.blit_rect(picture, Rect2i(0, 0, 600, 600), Vector2i(index % 3, index / 3) * 600)
		index += 1
	gallery.save_png(OUTPUT + "angles.png")
	study.get_node("Turntable").rotation.y = 0
	var actions := Image.create(2400, 1200, false, Image.FORMAT_RGBA8)
	index = 0
	for entry: Array in [["walk", .08], ["walk", .34], ["walk", .63], ["walk", .90], ["strike", 0.0], ["strike", .14], ["strike", .30], ["strike", .58]]:
		pose(entry[0], entry[1])
		var picture := await capture()
		picture.convert(Image.FORMAT_RGBA8)
		actions.blit_rect(picture, Rect2i(0, 0, 600, 600), Vector2i(index % 4, index / 4) * 600)
		index += 1
	actions.save_png(OUTPUT + "actions.png")
	pose("idle", 0)
	var teams := Image.create(1800, 600, false, Image.FORMAT_RGBA8)
	for owner in 3:
		model.set_team(owner)
		var picture := await capture()
		picture.convert(Image.FORMAT_RGBA8)
		teams.blit_rect(picture, Rect2i(0, 0, 600, 600), Vector2i(owner * 600, 0))
	teams.save_png(OUTPUT + "teams.png")
	FileAccess.open(OUTPUT + "results.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "triangles": triangles, "failures": failures}, "\t"))
	study.queue_free()
	await process_frame
	print("ZOMBIE_REVIEW ", checks, " checks, ", failures.size(), " failures, ", triangles, " triangles")
	quit(0 if failures.is_empty() else 1)
