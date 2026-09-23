extends SceneTree
## Render the six authored candidates together. Gameplay code is left untouched.
## Godot --path . --script res://tests/block_war_selection/render.gd --fixed-fps 30

const FPS := 30
const FRAMES := 90
const CLICK_FRAME := 18
const CLEAR_FRAME := 70
const OUTPUT := "res://artifacts/block_war_selection"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func _run() -> void:
	create_timer(90.0).timeout.connect(func(): quit(3))
	root.content_scale_size = Vector2i(1440, 1200)
	root.size = Vector2i(1440, 1200)
	root.use_taa = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	change_scene_to_file("res://tests/block_war_selection/review.tscn")
	await scene_changed
	var review: Node3D = current_scene
	var actors := review.get_node("Actors").get_children()
	var badge_transforms: Array[Transform3D] = []
	var pick_transforms: Array[Transform3D] = []
	for actor: Node3D in actors:
		badge_transforms.append(actor.building.get_node("PopulationBadge").global_transform)
		pick_transforms.append(actor.building.get_node("PickArea").global_transform)
		check(actor.preset.duration <= 0.75, "candidate completes within three quarters of a second")
	for frame: int in 8:
		await process_frame
	for frame: int in FRAMES:
		if frame == CLICK_FRAME:
			for actor: Node3D in actors:
				actor.play_motion()
		if frame == CLEAR_FRAME:
			for actor: Node3D in actors:
				actor.reset_motion()
		for index: int in actors.size():
			var actor: Node3D = actors[index]
			if frame > CLICK_FRAME:
				actor.advance(1.0 / FPS)
			var age := float(frame - CLICK_FRAME) / FPS
			var status: Label = review.get_node("Canvas/Status%d" % (index + 1))
			status.text = "等待点击" if frame < CLICK_FRAME or frame >= CLEAR_FRAME else ("● 点击" if age < 0.12 else ("回弹中" if age < actor.preset.duration else "已选中 · %.2f 秒收稳" % actor.preset.duration))
			status.modulate = Color(1, 0.83, 0.42) if age >= 0.0 and age < 0.12 else Color.WHITE
			if frame == 55:
				check(actor.body.transform.is_equal_approx(actor._body_rest), "candidate returns exactly to its original body transform")
				check(actor._upper.transform.is_equal_approx(actor._upper_rest), "upper component returns without cumulative drift")
				check(actor.building.get_node("PopulationBadge").global_transform.is_equal_approx(badge_transforms[index]), "population badge never participates in the model motion")
				check(actor.building.get_node("PickArea").global_transform.is_equal_approx(pick_transforms[index]), "click area stays stable through the selection gesture")
				check(actor.peak_displacement > 0.03, "each candidate produces a measurable motion")
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var error := root.get_texture().get_image().save_png(OUTPUT + "/frame_%03d.png" % frame)
			if error != OK:
				printerr("ERROR saving selection frame ", frame, ": ", error)
				quit(2)
				return
	review.queue_free()
	await process_frame
	print("BLOCK_WAR_SELECTION_PREVIEW checks=", checks, " failures=", failures.size(), " frames=", FRAMES)
	quit(0 if failures.is_empty() else 1)
