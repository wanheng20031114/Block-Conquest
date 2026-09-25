extends SceneTree
## Render the saved maps and native selection screen for visual review.
## Append -- rivers highland to capture only those maps during iteration.
## With no filter, capture all six overviews and all three selection pages.

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const OUTPUT := "res://artifacts/block_war_maps/"
const GAMEPLAY_ZOOM := 58.0
const DETAIL_FOCUS := {
	"rivers": Vector3(-14, 0, 0),
	"highland": Vector3.ZERO,
	"ridges": Vector3(0, 0, -11),
	"islands": Vector3(-18, 0, -21),
}
const DETAIL_NAMES := {
	"rivers": "bridgehead",
	"highland": "central_platform",
	"ridges": "mountain_pass",
	"islands": "water_junction",
}

func _initialize() -> void:
	_run.call_deferred()

func _capture(name: String, settle_frames: int = 12) -> void:
	for frame: int in settle_frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var output := root.get_texture().get_image()
	assert(output.save_png(OUTPUT + name + ".png") == OK)
	print("MAP_CAPTURE ", name)

func _capture_gameplay_detail(game: Node3D, map_id: String) -> void:
	if not DETAIL_FOCUS.has(map_id):
		return
	# Freeze water and foliage before fixing the camera.  Any bridge-surface
	# variation between these stills cannot be attributed to animated nature.
	game.map.set_visual_paused(true)
	game.camera.size = GAMEPLAY_ZOOM
	game.camera_rig.zoom_target = GAMEPLAY_ZOOM
	var focus: Vector3 = DETAIL_FOCUS[map_id]
	game.camera_rig.focus_at(focus, true)
	var prefix := "%s_%s" % [map_id, DETAIL_NAMES[map_id]]
	await _capture(prefix)
	if map_id == "rivers" or map_id == "highland":
		# At least 36 rendered process frames separate the fixed-camera images.
		await _capture(prefix + "_still_36", 36)
		# A sub-metre camera move exposes competing depth surfaces while keeping
		# the same bridge/platform and the normal gameplay zoom in view.
		game.camera_rig.focus_at(focus + Vector3(0.35, 0, 0.22), true)
		await _capture(prefix + "_camera_shift")

func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.gui_disable_input = true
	var requested := OS.get_cmdline_user_args()
	var map_ids := PackedStringArray()
	for definition: Resource in CATALOG.MAPS:
		map_ids.append(definition.map_id)
	for map_id: String in requested:
		if map_id not in map_ids:
			printerr("Unknown map filter: ", map_id, ". Expected: ", ", ".join(map_ids))
			quit(2)
			return
	var session := root.get_node("Session")
	var previous_map_id: String = session.block_war_map_id
	for definition: Resource in CATALOG.MAPS:
		if not requested.is_empty() and definition.map_id not in requested:
			continue
		session.block_war_map_id = definition.map_id
		change_scene_to_file("res://scenes/block_war/block_war.tscn")
		await scene_changed
		var game := current_scene
		game.set_process(false)
		game.camera_rig.set_process(false)
		game.camera_rig.edge_scroll = false
		game.ai_enabled = false
		game.audio.muted = true
		game.camera_rig.focus_at(Vector3.ZERO, true)
		game.camera.size = maxf(58.0, definition.half_size.y * 1.85)
		game.camera_rig.zoom_target = game.camera.size
		await _capture(definition.map_id)
		await _capture_gameplay_detail(game, definition.map_id)
		await game.prepare_shutdown()
	if requested.is_empty():
		change_scene_to_file("res://scenes/block_war/map_select.tscn")
		await scene_changed
		for size_class: int in 3:
			current_scene.get_node("%%Size%d" % size_class).pressed.emit()
			await _capture("selection_%d" % size_class)
	session.block_war_map_id = previous_map_id
	quit()
