extends SceneTree
## Native ten-model review; screenshots stay in the system temporary directory.

const BUILDING_NAMES: Array[String] = ["House", "Tower", "Smithy", "House2", "Tower2", "Smithy2", "House3", "Tower3", "Smithy3", "House4"]
var review: Node3D
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _capture(label: String) -> void:
	for frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("TEMP").path_join("block_war_architecture_" + label + ".png")
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("WAR_ARCHITECTURE_CAPTURE ", path)

func _run() -> void:
	create_timer(40.0).timeout.connect(func(): quit(3))
	change_scene_to_file("res://tests/block_war_architecture_review.tscn")
	await scene_changed
	review = current_scene
	camera = review.get_node("Camera")
	root.use_taa = false
	for node_name: String in BUILDING_NAMES:
		var building: WarBuilding = review.get_node(node_name)
		building.get_node("PopulationBadge").hide()
		building.get_node("PopulationLabel").hide()
		var label: Label3D = building.get_node("KindLabel")
		label.text = "%s · %d级" % [WarBuilding.KIND_NAMES[building.kind], building.level]
		label.modulate = Color("f4efd8")
		label.show()
	camera.position = Vector3(0, 43, 49)
	camera.look_at(Vector3(0, 1.8, 15))
	camera.size = 34.0
	await create_timer(0.8).timeout
	await _capture("levels_all")
	for kind: int in 3:
		for node_name: String in BUILDING_NAMES:
			var building: WarBuilding = review.get_node(node_name)
			building.visible = building.kind == kind
			if building.visible:
				building.position = Vector3((building.level - (2.5 if kind == 0 else 2.0)) * 6.4, 0, 0)
				building.get_node("KindLabel").pixel_size = 0.010
				building.get_node("Visual/Smithy/Smoke").restart()
		camera.position = Vector3(1, 16, 24)
		camera.look_at(Vector3(1, 2.0, 0))
		camera.size = 15.6 if kind == 0 else 12.2
		await _capture(["house_levels", "tower_levels", "smithy_levels"][kind])
	for node_name: String in BUILDING_NAMES:
		var building: WarBuilding = review.get_node(node_name)
		building.visible = true
		building.position = Vector3((building.kind - 1) * 7, 0, (building.level - 1) * 10)
		building.get_node("KindLabel").pixel_size = 0.023
		building.faction = [-1, 0, 1][(building.level - 1) % 3]
		building.refresh_visual()
		building.get_node("Visual/Smithy/Smoke").restart()
	camera.position = Vector3(0, 43, 49)
	camera.look_at(Vector3(0, 1.8, 15))
	camera.size = 34.0
	await _capture("levels_factions")
	# Each cannon keeps a fixed base and moving muzzle through aim and recoil.
	for node_name: String in ["Tower", "Tower2", "Tower3"]:
		var tower: WarBuilding = review.get_node(node_name)
		var stationary: Transform3D = tower.get_node("Visual/Tower/Stone").global_transform
		var direction := Vector3(12, 0, 7).normalized()
		tower.fire_at(tower.global_position + direction * 20.0)
		var muzzle: Node3D = tower.get_node("Visual/Tower/Gun/Barrel/Muzzle")
		assert(tower.muzzle_position().distance_to(muzzle.global_position) < 0.001)
		var heading: Vector3 = -tower.get_node("Visual/Tower/Gun").global_basis.z
		heading.y = 0.0
		assert(heading.normalized().dot(direction) > 0.999)
		await create_timer(0.04).timeout
		tower.set_visual_paused(true)
		var recoil: Vector3 = tower.get_node("Visual/Tower/Gun/Barrel").position
		await create_timer(0.10).timeout
		assert(tower.get_node("Visual/Tower/Gun/Barrel").position == recoil)
		tower.set_visual_paused(false)
		await create_timer(0.40).timeout
		assert(is_zero_approx(tower.get_node("Visual/Tower/Gun/Barrel").position.z))
		assert(tower.get_node("Visual/Tower/Stone").global_transform == stationary)
	for node_name: String in ["Smithy", "Smithy2", "Smithy3"]:
		var smithy: WarBuilding = review.get_node(node_name)
		smithy.set_visual_paused(true)
		var visual_time: float = smithy._visual_time
		await create_timer(0.10).timeout
		assert(smithy._visual_time == visual_time)
		assert(smithy.get_node("Visual/Smithy/Smoke").speed_scale == 0.0)
		assert(smithy.get_node("Visual/Smithy/ForgeAnimation").speed_scale == 0.0)
	print("WAR_ARCHITECTURE_VISUAL ten models captured; every cannon aim/recoil/pause and forge visual pause passed")
	review.queue_free()
	await process_frame
	quit()
