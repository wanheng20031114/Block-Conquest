extends SceneTree
## Ownership changes recolor only roof tiles, including a currently hidden kind.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(5.0).timeout.connect(func() -> void: quit(1))
	var scene := load("res://scenes/block_war/building.tscn") as PackedScene
	var building := scene.instantiate() as WarBuilding
	var neighbor := scene.instantiate() as WarBuilding
	neighbor.faction = 1
	neighbor.kind = 2
	root.add_child(building)
	root.add_child(neighbor)
	await process_frame
	for faction: int in [-1, 0, 1, 0]:
		building.faction = faction
		building.pulse_capture()
		var expected: Color = WarBuilding.NEUTRAL_COLOR if faction < 0 else WarBuilding.FACTION_COLORS[faction]
		for kind: int in [0, 2]:
			building.kind = kind
			building.refresh_visual()
			for roof_path: String in ["Visual/House/Roof", "Visual/Smithy/Roof"]:
				var roof := building.get_node(roof_path) as MeshInstance3D
				assert(roof.get_instance_shader_parameter("team_tint").is_equal_approx(expected))
				assert(roof.material_override.get_shader_parameter("tint_strength") == 1.0)
				assert(roof.material_override.get_shader_parameter("surface_roughness") == 0.88)
				assert(neighbor.get_node(roof_path).get_instance_shader_parameter("team_tint").is_equal_approx(WarBuilding.FACTION_COLORS[1]))
		for body_path: String in ["Visual/House/Stone", "Visual/House/Timber", "Visual/House/Metal", "Visual/Smithy/Stone"]:
			var body := building.get_node(body_path) as MeshInstance3D
			# An unset material value uses the surface shader's zero tint default.
			var body_tint: Variant = body.material_override.get_shader_parameter("tint_strength")
			assert(body_tint == null or body_tint == 0.0)
	var forge: Animation = building.get_node("Visual/Smithy/ForgeAnimation").get_animation("forge")
	for key: int in forge.track_get_key_count(0):
		assert(float(forge.track_get_key_value(0, key)) <= 0.8125)
	building.free()
	neighbor.free()
	print("WAR_ROOF_FACTIONS_PASS neutral/orange/mint roofs; capture and kind switches; neighboring instance and natural wall materials preserved; forge flicker limited")
	quit()
