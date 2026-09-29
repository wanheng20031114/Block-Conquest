extends SceneTree
## Captures ordinary 24 fps codex playback for video review. No simulation seek
## or substitute VFX: each image is a rendered frame of the actual guide.

const CATALOG := preload("res://scripts/codex/codex_catalog.gd")
const CLIPS := [
	{"hero": &"squirrel", "skill": 0, "name": "squirrel_q"},
	{"hero": &"squirrel", "skill": 1, "name": "squirrel_w"},
	{"hero": &"frog", "skill": 3, "name": "frog_r"},
]
const FPS := 24
const FRAME_COUNT := FPS * 8

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	var output := ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	root.size = Vector2i(1280, 720)
	var page: Control = load("res://scenes/codex/codex.tscn").instantiate()
	root.add_child(page)
	var demo: Control = page.get_node("%Demo")
	for clip: Dictionary in CLIPS:
		var folder: String = output.path_join(clip.name)
		DirAccess.make_dir_recursive_absolute(folder)
		var row := CATALOG.HEROES.find(clip.hero)
		page.get_node("%Entries").select(row)
		page._select_entry(row)
		page._select_skill(clip.skill, false)
		demo.set_playing(false)
		for frame: int in 16:
			await RenderingServer.frame_post_draw
		page._replay()
		for frame: int in FRAME_COUNT:
			await RenderingServer.frame_post_draw
			var saved := root.get_texture().get_image().save_png(folder.path_join("frame_%04d.png" % frame))
			assert(saved == OK)
		assert(demo.world.cast_succeeded and demo.world.cast_count == 1)
		print("CODEX_CAPTURE ", clip.name, " frames=", FRAME_COUNT, " fps=", FPS, " elapsed=", demo.world.elapsed)
	page.queue_free()
	await process_frame
	quit(0)
