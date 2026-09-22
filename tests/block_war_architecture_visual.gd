extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	change_scene_to_file("res://tests/block_war_architecture_review.tscn")
	await scene_changed
	var review: Node3D = current_scene
	for name: String in ["House", "Tower", "Smithy"]:
		var building: Node3D = review.get_node(name)
		building.get_node("PopulationBadge").hide()
		building.get_node("PopulationLabel").hide()
		building.get_node("KindLabel").hide()
	var camera: Camera3D = review.get_node("Camera")
	camera.look_at(Vector3(0, 1.8, 0))
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/block_war_architecture_all.png")
	for name: String in ["House", "Tower", "Smithy"]:
		var building: Node3D = review.get_node(name)
		building.kind = 0
		building.refresh_visual()
		building.get_node("PopulationBadge").show()
		building.get_node("PopulationLabel").show()
	await create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/block_war_architecture_roof_factions.png")
	review.get_node("Tower").kind = 1
	review.get_node("Smithy").kind = 2
	for name: String in ["House", "Tower", "Smithy"]:
		var building: Node3D = review.get_node(name)
		building.refresh_visual()
		building.get_node("PopulationBadge").hide()
		building.get_node("PopulationLabel").hide()
	for name: String in ["House", "Tower", "Smithy"]:
		var building: Node3D = review.get_node(name)
		camera.position = building.position + Vector3(7, 13, 11)
		camera.look_at(building.position + Vector3(0, 2.0, 0))
		camera.size = 8.4
		await create_timer(0.12).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/block_war_architecture_" + name.to_lower() + ".png")
	var smithy: Node3D = review.get_node("Smithy")
	smithy.set_visual_paused(true)
	var time: float = smithy._visual_time
	await create_timer(0.1).timeout
	assert(smithy._visual_time == time)
	assert(smithy.get_node("Visual/Smithy/Smoke").speed_scale == 0.0)
	assert(smithy.get_node("Visual/Smithy/ForgeAnimation").speed_scale == 0.0)
	var tower: Node3D = review.get_node("Tower")
	var stationary: Transform3D = tower.get_node("Visual/Tower/Stone").global_transform
	tower.fire_at(Vector3(12, 0, 7))
	var muzzle: Node3D = tower.get_node("Visual/Tower/Gun/Barrel/Muzzle")
	assert(tower.get_node("ProjectileOrigin").global_position.distance_to(muzzle.global_position) < 0.001)
	var heading: Vector3 = -tower.get_node("Visual/Tower/Gun").global_basis.z
	heading.y = 0.0
	assert(heading.normalized().dot(Vector3(12, 0, 7).normalized()) > 0.999)
	await create_timer(0.04).timeout
	tower.set_visual_paused(true)
	var recoil: Vector3 = tower.get_node("Visual/Tower/Gun/Barrel").position
	await create_timer(0.10).timeout
	assert(tower.get_node("Visual/Tower/Gun/Barrel").position == recoil)
	tower.set_visual_paused(false)
	await create_timer(0.40).timeout
	assert(is_zero_approx(tower.get_node("Visual/Tower/Gun/Barrel").position.z))
	assert(tower.get_node("Visual/Tower/Stone").global_transform == stationary)
	print("WAR_ARCHITECTURE_VISUAL captured three buildings, ownership roofs and ivory badges; visual pause, muzzle follow, aim and recoil passed")
	review.queue_free()
	await process_frame
	quit()
