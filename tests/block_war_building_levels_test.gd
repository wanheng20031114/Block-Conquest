extends SceneTree
## Saved tier meshes must switch without changing ownership, scene structure or picking.

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	create_timer(10.0).timeout.connect(func() -> void: quit(3))
	var packed := load("res://scenes/block_war/building.tscn") as PackedScene
	var building := packed.instantiate() as WarBuilding
	var neighbor := packed.instantiate() as WarBuilding
	neighbor.faction = 1
	root.add_child(building)
	root.add_child(neighbor)
	await process_frame
	building.set_process(false)
	neighbor.set_process(false)
	var label: Label3D = building.get_node("PopulationLabel")
	var badge: MeshInstance3D = building.get_node("PopulationBadge")
	building.population = 99
	building.refresh_visual()
	var two_digit_size := label.font_size
	for population: int in [100, 128, 999, 1000, 99]:
		building.population = population
		building.refresh_visual()
		var text_width := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x * label.pixel_size
		check(text_width <= 2.2 * badge.scale.x + 0.001, "population %d fits within the badge's clear center" % population)
		if population >= 100 and population <= 999:
			check(label.font_size < two_digit_size and badge.scale.is_equal_approx(Vector3.ONE), "three digits use smaller type in the unchanged white badge")
	check(label.font_size == two_digit_size, "population returning below 100 restores the larger digits")
	var authored_count := building.find_children("*", "", true, false).size()
	var original_pick: Shape3D = building.get_node("PickArea/CollisionShape3D").shape
	var original_badge_pick: Shape3D = building.get_node("PickArea/BadgeCollisionShape3D").shape
	var original_door := building.door_position()
	var original_population := building.population
	var neighbor_meshes: Dictionary = {}
	for path: String in WarBuilding.LEVEL_MESHES:
		neighbor_meshes[path] = neighbor.get_node("Visual/" + path).mesh
	var kind_paths: Array[String] = ["House", "Tower", "Smithy"]
	for kind: int in 3:
		building.kind = kind
		var signatures: Array[String] = []
		var tiers: Array = [[1, 2, 3, 4, 3, 2, 1], [1, 2, 3, 2, 1], [1]][kind]
		for tier: int in tiers:
			building.level = tier
			var original_capacity := building.capacity
			building.refresh_visual()
			var body: Node3D = building.get_node("Visual/" + kind_paths[kind])
			check(body.visible, "%s level %d activates its authored kind" % [body.name, tier])
			var stone: MeshInstance3D = body.get_node("Stone")
			var bounds := stone.mesh.get_aabb()
			check(stone.mesh is ArrayMesh and bounds.position.y <= -0.075 and bounds.position.y > -0.10,
				"%s level %d has a baked grounded footing" % [body.name, tier])
			var identity := stone.mesh.resource_path
			if signatures.size() < building.max_level:
				check(identity not in signatures, "%s tiers have distinct saved geometry" % body.name)
				signatures.append(identity)
			check(building.find_children("*", "", true, false).size() == authored_count,
				"tier switches preserve the authored node count")
			check(building.get_node("PickArea/CollisionShape3D").shape == original_pick and
				building.get_node("PickArea/BadgeCollisionShape3D").shape == original_badge_pick and
				building.door_position() == original_door, "tier switches preserve picking and the door")
			check(building.population == original_population and building.capacity == original_capacity,
				"refreshing a model does not alter gameplay state")
			for path: String in neighbor_meshes:
				check(neighbor.get_node("Visual/" + path).mesh == neighbor_meshes[path],
					"upgrading one building preserves its neighbor's " + path)
			for faction: int in [-1, 0, 1]:
				building.faction = faction
				building.refresh_visual()
				var dye: Color = WarBuilding.NEUTRAL_COLOR if faction < 0 else WarBuilding.FACTION_COLORS[faction]
				for roof_path: String in ["Visual/House/Roof", "Visual/Smithy/Roof"]:
					var roof: MeshInstance3D = building.get_node(roof_path)
					check(roof.get_instance_shader_parameter("team_tint").is_equal_approx(dye),
						"each saved tier retains neutral/orange/mint roof dye")
					check(neighbor.get_node(roof_path).get_instance_shader_parameter("team_tint").is_equal_approx(WarBuilding.FACTION_COLORS[1]),
						"roof ownership remains per instance")
			if kind == 1:
				var barrel: MeshInstance3D = building.get_node("Visual/Tower/Gun/Barrel/BarrelMetal")
				var muzzle: RemoteTransform3D = building.get_node("Visual/Tower/Gun/Barrel/Muzzle")
				check(absf(muzzle.position.z - barrel.mesh.get_aabb().position.z) < 0.005,
					"tier %d muzzle marker sits on the actual cannon mouth" % tier)
				building.fire_at(Vector3(8, 0, -11))
				check(building.muzzle_position().is_equal_approx(building.get_node("ProjectileOrigin").global_position),
					"the stable muzzle API updates the legacy projectile marker in the same frame")
			if kind == 2:
				var smoke: GPUParticles3D = body.get_node("Smoke")
				var chimney_top := maxf(bounds.end.y, body.get_node("Metal").mesh.get_aabb().end.y)
				check(smoke.emitting and smoke.position.y > chimney_top and smoke.position.y - chimney_top < 0.04,
					"tier %d smoke begins at its chimney opening" % tier)
	# A conversion at the same level still refreshes the newly active kind.
	building.kind = 0
	building.level = 4
	building.refresh_visual()
	check(building.get_node("Visual/House/Stone").mesh.resource_path.ends_with("house_4_stone.res"), "fourth house uses its own baked model")
	check(building.get_node("Visual/Flag").get_instance_shader_parameter("building_level") == 4, "fourth house shows four rank marks")
	building.level = 1
	building.kind = 1
	building.refresh_visual()
	building.kind = 0
	building.refresh_visual()
	check(building.get_node("Visual/House/Stone").mesh.resource_path.ends_with("house_stone.res"), "same-level conversion restores the correct house model")
	# A capture downgrade updates both mesh resources and team tint immediately.
	building.kind = 0
	building.level = 3
	building.faction = 0
	building.refresh_visual()
	building.level = 2
	building.faction = 1
	building.pulse_capture()
	check(building.get_node("Visual/House/Stone").mesh.resource_path.ends_with("house_2_stone.res") and
		building.get_node("Visual/House/Roof").get_instance_shader_parameter("team_tint").is_equal_approx(WarBuilding.FACTION_COLORS[1]),
		"capture downgrade changes the model and ownership together")
	building.kind = 2
	building.level = 1
	building.refresh_visual()
	building.set_visual_paused(true)
	var before_time := building._visual_time
	var animation: AnimationPlayer = building.get_node("Visual/Smithy/ForgeAnimation")
	var before_animation := animation.current_animation_position
	building._process(0.5)
	await create_timer(0.08).timeout
	check(building._visual_time == before_time and animation.current_animation_position == before_animation and
		building.get_node("Visual/Smithy/Smoke").speed_scale == 0.0,
		"paused forge freezes shader time, native animation and smoke")
	building.set_visual_paused(false)
	building._process(0.5)
	check(building._visual_time > before_time and animation.speed_scale == 1.0 and
		building.get_node("Visual/Smithy/Smoke").speed_scale == 1.0,
		"resume restarts all forge presentation clocks")
	building.free()
	neighbor.free()
	print("BLOCK_WAR_BUILDING_LEVELS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
