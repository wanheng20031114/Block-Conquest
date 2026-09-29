extends SceneTree
## Native tier-three / tier-four comparison and construction / muzzle validation.

var review: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL TOWER_FOUR_VISUAL ", description)

func _settle(frames: int = 8) -> void:
	for frame: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw

func _building(tier: int) -> WarBuilding:
	return review.get_node("Tier%d/View/Viewport/Building" % tier)

func _camera(tier: int) -> Camera3D:
	return review.get_node("Tier%d/View/Viewport/Stage/Camera" % tier)

func _run() -> void:
	create_timer(40.0, true, false, true).timeout.connect(func(): quit(3))
	var output := OS.get_cmdline_user_args()[0]
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = root.size
	root.gui_disable_input = true
	change_scene_to_file("res://tests/block_war_tower_four_review.tscn")
	await scene_changed
	review = current_scene
	for tier: int in [3, 4]:
		var building := _building(tier)
		building.get_node("PopulationLabel").hide()
		building.get_node("PopulationBadge").hide()
		building.get_node("AttackRange").hide()
		building.set_process(false)
		var camera := _camera(tier)
		camera.position = Vector3(8, 10, 14)
		camera.look_at(Vector3(0.15, 1.8, 0))
		camera.size = 7.7
	await _settle()
	_check(root.get_texture().get_image().save_png(output.path_join("tower_level_four_comparison.png")) == OK, "tier three and four comparison saved")
	for tier: int in [3, 4]:
		var camera := _camera(tier)
		camera.position = Vector3(0, 60, 46.86)
		camera.look_at(Vector3(0.15, 1.8, 0))
		camera.size = 10.5
	review.get_node("Title").text = "炮塔 · 战场俯视对照"
	review.get_node("Subtitle").text = "三级与四级 · 相同战场视角 · 更高塔身与加固炮架"
	await _settle()
	_check(root.get_texture().get_image().save_png(output.path_join("tower_level_four_battle.png")) == OK, "battlefield tier comparison saved")
	var tower := _building(3)
	var node_count := tower.find_children("*", "", true, false).size()
	var old_stone: ArrayMesh = tower.get_node("Visual/Tower/Stone").mesh
	_check(tower.max_level == 4 and tower.upgrade_cost == 90, "third tower upgrades to fourth for 90 troops")
	tower.begin_construction(-1, 90)
	_check(tower.construction_remaining == 10.0, "fourth-tier construction lasts ten seconds")
	tower.advance_construction(9.0)
	_check(tower.level == 3 and tower.get_node("Visual/Tower/Stone").mesh == old_stone, "unfinished upgrade preserves the third-tier model")
	tower.advance_construction(1.0)
	_check(tower.level == 4 and tower.upgrade_cost == 0, "fourth tier is the final authored upgrade")
	_check(tower.get_node("Visual/Tower/Stone").mesh.resource_path.ends_with("tower_4_stone.res"), "completed upgrade switches to the fourth-tier mesh")
	_check(tower.find_children("*", "", true, false).size() == node_count, "upgrade reuses the authored node hierarchy")
	_check(tower.get_node("Visual/Flag").get_instance_shader_parameter("building_level") == 4, "fourth tower has four rank marks")
	await _settle(18)
	var barrel_mesh: MeshInstance3D = tower.get_node("Visual/Tower/Gun/Barrel/BarrelMetal")
	var muzzle: RemoteTransform3D = tower.get_node("Visual/Tower/Gun/Barrel/Muzzle")
	_check(absf(muzzle.position.z - barrel_mesh.mesh.get_aabb().position.z) < 0.005, "fourth-tier muzzle sits on the actual cannon mouth")
	var stone_pose: Transform3D = tower.get_node("Visual/Tower/Stone").transform
	for direction: Vector3 in [Vector3(1, 0, -1), Vector3(-1, 0, -1), Vector3(0, 0, 1)]:
		tower.fire_at(tower.global_position + direction * 20.0)
		_check(tower.muzzle_position().is_equal_approx(tower.get_node("ProjectileOrigin").global_position), "fourth-tier muzzle updates the projectile marker immediately")
		await _settle(2)
		tower.set_visual_paused(true)
		var recoil: Vector3 = tower.get_node("Visual/Tower/Gun/Barrel").position
		await _settle(3)
		_check(tower.get_node("Visual/Tower/Gun/Barrel").position == recoil, "pause freezes fourth-tier recoil")
		tower.set_visual_paused(false)
		await _settle(12)
		_check(is_zero_approx(tower.get_node("Visual/Tower/Gun/Barrel").position.z), "fourth-tier recoil returns to its rest position")
	_check(tower.get_node("Visual/Tower/Stone").transform == stone_pose, "aim and recoil preserve the stationary stone tower")
	print("TOWER_FOUR_VISUAL checks=", checks, " failures=", failures.size(), " output=", output)
	review.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
