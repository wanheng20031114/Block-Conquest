extends SceneTree
## Native six-faction rendering and lifecycle checks on a private desktop.

const RESOLUTION := Vector2i(1600, 1000)
var review: Control
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL ENERGY_TOWER_VISUAL ", description)

func _settle(frames: int = 6) -> void:
	for frame: int in frames:
		await process_frame
	await RenderingServer.frame_post_draw

func _building(index: int) -> WarBuilding:
	return review.get_node("Faction%d/View/Viewport/Building" % index)

func _camera(index: int) -> Camera3D:
	return review.get_node("Faction%d/View/Viewport/Stage/Camera" % index)

func _lifecycle(building: WarBuilding) -> void:
	var orbit: AnimationPlayer = building.get_node("Visual/EnergyTower/OrbitAnimation")
	var pulse: AnimationPlayer = building.get_node("Visual/EnergyTower/CoreAnimation")
	var ring: Node3D = building.get_node("Visual/EnergyTower/RingA")
	var core: Node3D = building.get_node("Visual/EnergyTower/Core")
	var heraldry: MeshInstance3D = building.get_node("Visual/EnergyTower/Heraldry")
	var glow: MeshInstance3D = building.get_node("Visual/EnergyTower/Core/Glow")
	_check(building.kind == 3 and building.max_level == 1, "energy tower has one authored level")
	_check(building.capacity == 0.0 and building.production_rate == 0.0, "energy tower does not produce troops")
	for faction: int in 6:
		building.faction = faction
		building.refresh_visual()
		_check(heraldry.get_instance_shader_parameter("team_tint") == WarBuilding.FACTION_COLORS[faction], "capture immediately recolors faction %d band" % faction)
		_check(glow.get_instance_shader_parameter("team_tint") == WarBuilding.FACTION_COLORS[faction], "capture immediately recolors faction %d core" % faction)
		await physics_frame
		var known := faction % 2 == 0
		_check(building.get_node("PopulationLabel").visible == known and building.get_node("PopulationBadge").visible == known, "faction %d garrison visibility matches local knowledge" % faction)
		_check(building.get_node("PopulationLabel").text == ("36" if known else ""), "faction %d enemy garrison has no text or placeholder" % faction)
		_check(building.get_node("PickArea/BadgeCollisionShape3D").disabled == not known, "faction %d hidden badge is not pickable" % faction)
	building.faction = 0
	building.refresh_visual()
	var previous_angle := ring.rotation.y
	await _settle()
	_check(not is_equal_approx(ring.rotation.y, previous_angle), "native star rings advance")
	building.set_visual_paused(true)
	var frozen_angle := ring.rotation.y
	var frozen_core := core.scale
	await _settle()
	_check(is_equal_approx(ring.rotation.y, frozen_angle) and core.scale.is_equal_approx(frozen_core), "pause freezes rings and core without snapping")
	building.set_visual_paused(false)
	await _settle()
	_check(not is_equal_approx(ring.rotation.y, frozen_angle), "resume continues ring motion")
	building.begin_disruption(2.0)
	frozen_angle = ring.rotation.y
	frozen_core = core.scale
	await _settle()
	_check(is_equal_approx(ring.rotation.y, frozen_angle) and core.scale.is_equal_approx(frozen_core), "rabbit seal freezes rings and core")
	building.set_visual_paused(true)
	building.clear_disruption()
	_check(orbit.speed_scale == 0.0 and pulse.speed_scale == 0.0, "clearing seal while paused keeps energy motion frozen")
	building.set_visual_paused(false)
	_check(orbit.speed_scale == 1.0 and pulse.speed_scale == 1.0, "resume after seal restarts native animations")
	building.advance_disruption(1.0)
	_check(not building.get_node("Disruption/Seal").visible, "the match clock completes the seal release")
	building.begin_construction(0, 20)
	previous_angle = ring.rotation.y
	await _settle()
	_check(building.kind == 3 and not is_equal_approx(ring.rotation.y, previous_angle), "conversion keeps the existing energy tower moving until completion")
	building.advance_construction(10.0)
	_check(building.kind == 0 and not building.get_node("Visual/EnergyTower").visible, "completed conversion hides the energy model")
	_check(orbit.speed_scale == 0.0 and pulse.speed_scale == 0.0, "hidden energy model stops both animations")
	for kind: int in 4:
		building.kind = kind
		for target: int in 4:
			_check(building.can_convert_to(target) == (target != kind and (target != 3 or kind == 2)), "conversion matrix %d to %d" % [kind, target])
	building.kind = 2
	building.refresh_visual()
	building.begin_construction(3, 5)
	_check(orbit.speed_scale == 0.0, "smithy conversion keeps energy animation inactive until completion")
	building.advance_construction(10.0)
	_check(building.kind == 3 and orbit.speed_scale == 1.0 and pulse.speed_scale == 1.0, "completed energy tower starts both native animations")
	# Let the real completion feedback settle before the model comparison.
	await _settle(48)
	building.cancel_construction()

func _run() -> void:
	create_timer(50.0, true, false, true).timeout.connect(func(): quit(3))
	var output := OS.get_cmdline_user_args()[0]
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.size = RESOLUTION
	root.content_scale_size = RESOLUTION
	root.gui_disable_input = true
	change_scene_to_file("res://tests/block_war_energy_tower_review.tscn")
	await scene_changed
	review = current_scene
	for index: int in 6:
		var camera := _camera(index)
		camera.position = Vector3(8, 10, 14)
		camera.look_at(Vector3(0.15, 3.3, 0))
		camera.size = 10.0
	await _lifecycle(_building(0))
	# Align the authored animation poses for an honest side-by-side color comparison.
	for index: int in 6:
		var building := _building(index)
		building.get_node("Visual/EnergyTower/OrbitAnimation").seek(0.0, true)
		building.get_node("Visual/EnergyTower/CoreAnimation").seek(0.0, true)
	await _settle()
	_check(root.get_texture().get_image().save_png(output.path_join("energy_tower_factions.png")) == OK, "native six-faction close view saved")
	for index: int in 6:
		var camera := _camera(index)
		camera.position = Vector3(0, 60, 46.86)
		camera.look_at(Vector3(0.15, 2.4, 0))
		camera.size = 13.0
	review.get_node("Title").text = "能量塔 · 战场俯视对照"
	review.get_node("Subtitle").text = "战场视角 · 缩小比例 · 阵营色带与核心仍可辨识"
	await _settle()
	_check(root.get_texture().get_image().save_png(output.path_join("energy_tower_battle.png")) == OK, "native six-faction battle view saved")
	print("ENERGY_TOWER_VISUAL checks=", checks, " failures=", failures.size(), " output=", output)
	review.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
