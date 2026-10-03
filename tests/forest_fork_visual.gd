extends SceneTree
## Capture actual saved geometry with the game's daylight and camera angle.

const OUTPUT := "res://artifacts/forest-fork-visual/"

func _initialize() -> void:
	_run.call_deferred()

func _capture(camera: Camera3D, point: Vector3, size: float, name: String) -> void:
	camera.position = point + Vector3(0, 85, 66.386)
	camera.rotation_degrees = Vector3(-52, 0, 0)
	camera.size = size
	for frame: int in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(OUTPUT + name + ".png") == OK)
	print("FOREST_CAPTURE ", name)

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = load("res://assets/block_war/environment/woodland_daylight.tres")
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-49, -38, 0)
	sun.light_color = Color(1, .955, .83)
	sun.light_energy = 1.06
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180
	sun.shadow_bias = .035
	sun.shadow_normal_bias = .7
	world.add_child(sun)
	var map: WarMap = load("res://scenes/block_war/maps/forest_fork.tscn").instantiate()
	world.add_child(map)
	map.set_visual_paused(true)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 230
	camera.current = true
	world.add_child(camera)
	await _capture(camera, Vector3(0, 0, 1), 84, "forest_fork_overview")
	await _capture(camera, Vector3(-26, 2, 21), 34, "forest_fork_ramp")
	await _capture(camera, Vector3(0, 6, 1), 41, "forest_fork_ridge")
	world.free()
	quit()
