extends SceneTree
## Grass review under the saved match lighting. Run with -- lake rift for a
## quick iteration; without arguments capture all six native battlefields.
## This isolates the terrain from HUD/gameplay while preserving its shadows.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const OUTPUT := "res://artifacts/grass_refinement/after/"
const DETAIL_FOCUS := {
	"rift": Vector3(-23, 0, 8),
	"lake": Vector3(23, 0, -10),
	"rivers": Vector3(37, 0, 15),
	"ridges": Vector3(24, 0, 8),
	"islands": Vector3(56, 0, 12),
	"highland": Vector3(42, 0, 10),
}
var camera: Camera3D

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-20000, -20000))
	_run.call_deferred()

func capture(label: String, focus: Vector3, zoom: float) -> void:
	camera.global_position = focus + Vector3(0, 60, 46.86)
	camera.look_at(focus)
	camera.size = zoom
	camera.reset_physics_interpolation()
	for frame: int in 45:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + label + ".png") == OK)
	print("MEADOW_CAPTURE ", label, " size=", camera.size)

func _run() -> void:
	create_timer(120.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size = Vector2i(1600, 900)
	root.gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	change_scene_to_file("res://tests/block_war_nature_review.tscn")
	await scene_changed
	var gallery := current_scene
	camera = gallery.get_node("Camera")
	var requested := OS.get_cmdline_user_args()
	for definition: Resource in CATALOG.MAPS:
		if not requested.is_empty() and definition.map_id not in requested:
			continue
		var map: WarMap = load(definition.scene_path).instantiate()
		gallery.add_child(map)
		for building: Node3D in map.get_node("Buildings").get_children():
			building.get_node("PopulationBadge").hide()
			for label: Label3D in building.find_children("*", "Label3D", true, false):
				label.hide()
		map.set_visual_paused(true)
		await capture(definition.map_id + "_overview", Vector3.ZERO,
			maxf(58.0, definition.half_size.y * 1.85))
		var samples: Array[float] = []
		for frame: int in 90:
			await process_frame
			samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		samples.sort()
		print("MEADOW_GPU_MS ", definition.map_id, " median=", samples[45], " p95=", samples[85])
		await capture(definition.map_id + "_ground", DETAIL_FOCUS[definition.map_id], 20.0)
		if definition.map_id == "lake":
			# Same ground at the normal zoom and after a sub-metre pan, then again
			# without movement. Inspect AA, texture anchoring and TAA convergence.
			await capture("lake_tactical", DETAIL_FOCUS["lake"], 58.0)
			await capture("lake_shift", DETAIL_FOCUS["lake"] + Vector3(0.35, 0, 0.22), 58.0)
			await capture("lake_shift_still", DETAIL_FOCUS["lake"] + Vector3(0.35, 0, 0.22), 58.0)
		map.queue_free()
		await process_frame
	quit()
