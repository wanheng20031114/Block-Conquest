extends "res://tests/block_war_pig_visual.gd"
## Native rendering, snapshot pool replacement, faction transfer and pause.

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	assert(DirAccess.make_dir_recursive_absolute(output) == OK)
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	root.get_node("Session").block_war_map_id = "terraces"
	root.get_node("Session").block_war_commander = &"pig"
	await fresh()
	var home := own(15, 70.0)
	focus(home.global_position + Vector3(0, 2, 0), 22.0)
	assert(game.cast_skill(2, home))
	var effects: Node3D = game.world_effects.get_node("PigEffects")
	var slot: Node3D = effects.get_node("Airlifts/Airlift0")
	await advance(0.18)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 8)
	var early: Transform3D = slot.get_node("Soldiers").multimesh.get_instance_transform(0)
	assert(absf(early.origin.x) < 1.0 and absf(early.origin.z) < 0.5)
	assert(not slot.has_node("Marks") and not slot.has_node("Dust"))
	await capture("01_allied_descent")
	await advance(0.195)
	var entering: Transform3D = slot.get_node("Soldiers").multimesh.get_instance_transform(0)
	assert(is_equal_approx(early.origin.x, entering.origin.x) and is_equal_approx(early.origin.z, entering.origin.z))
	assert(entering.origin.y < early.origin.y)
	await capture("01b_through_roof")
	await advance(0.055)
	assert(slot.landed_batches == 1)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 8)
	await capture("02_touchdown_next_batch")
	var age: float = slot.age
	var pose: Transform3D = slot.get_node("Soldiers").multimesh.get_instance_transform(0)
	game.set_paused(true)
	await advance(0.8)
	assert(is_equal_approx(slot.age, age))
	assert(slot.get_node("Soldiers").multimesh.get_instance_transform(0).is_equal_approx(pose))
	assert(not slot._running)
	game.set_paused(false)
	await advance(1.60)
	assert(game.pig.airlifts[0].landed == 40)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 0)
	await capture("03_final_batch_entry")
	await advance(0.20)
	assert(game.pig.airlifts.is_empty() and not slot.active)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 0)
	await capture("04_cleared")
	# Restore only the unlanded batch; past contacts cannot replay as a burst.
	var states: Array = [{"id": 50, "faction": 1, "target": 15, "age": 1.3, "landed": 24}]
	effects.sync_airlifts(states, game.by_id)
	assert(slot.first_batch == 3 and slot.landed_batches == 3)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 8)
	await capture("05_restored_enemy_batch")
	states[0].faction = 0
	effects.sync_airlifts(states, game.by_id)
	var tint: Color = slot.get_node("Soldiers").multimesh.get_instance_custom_data(0)
	var expected: Color = WarMarches.FACTION_COLORS[0].srgb_to_linear()
	assert(slot.faction == 0 and Vector3(tint.r, tint.g, tint.b).distance_to(Vector3(expected.r, expected.g, expected.b)) < 0.001)
	# Six active old slots must all retire before six new ids are assigned.
	states.clear()
	for faction: int in 6:
		states.append({"id": 100 + faction, "faction": faction, "target": 10 + faction, "age": 0.2, "landed": 0})
	effects.sync_airlifts(states, game.by_id)
	for state: Dictionary in states: state.id += 100
	effects.sync_airlifts(states, game.by_id)
	for index: int in 6:
		var current: Node3D = effects.get_node("Airlifts").get_child(index)
		assert(current.airlift_id >= 200 and current.active)
		assert(current.get_node("Soldiers").multimesh.visible_instance_count == 8)
	focus(Vector3(0, 4, 0), 44)
	await capture("06_six_restored_casters")
	effects.sync_airlifts([], game.by_id)
	assert(effects.get_node("Airlifts").get_children().all(func(value: Node3D): return not value.active))
	# Verify all authored building kinds and upgrade heights on the same raised
	# site; geometry changes during a live cast must rebuild the roof once.
	game.hud.hide()
	var heights: Array[float] = []
	for kind: int in 4:
		home.kind = kind
		home.level = 1
		home.refresh_visual()
		var roof_points: PackedVector3Array = slot.entry_points_for(home)
		assert(roof_points.size() == 8)
		for point: Vector3 in roof_points:
			assert(point.y > 0.0 and absf(point.x) < 1.0 and absf(point.z) < 0.5)
		effects.sync_airlifts([{"id": 500 + kind, "faction": 0, "target": home.building_id, "age": 0.375, "landed": 0}], game.by_id)
		heights.append(slot._roof_height)
		focus(home.global_position + Vector3(0, slot._roof_height + 1.5, 0), 20)
		await capture("07_kind_%d_roof_entry" % kind)
		effects.sync_airlifts([], game.by_id)
	assert(heights.max() - heights.min() > 0.3, "Each model supplies its actual roof height.")
	home.kind = 0
	home.level = 1
	home.refresh_visual()
	effects.sync_airlifts([{"id": 700, "faction": 0, "target": home.building_id, "age": 0.23, "landed": 0}], game.by_id)
	var low_roof: float = slot._roof_height
	home.level = 4
	home.refresh_visual()
	effects.sync_airlifts([{"id": 700, "faction": 0, "target": home.building_id, "age": 0.375, "landed": 0}], game.by_id)
	assert(slot._roof_height > low_roof + 0.4 and slot._geometry_signature == Vector2i(0, 4))
	focus(home.global_position + Vector3(0, slot._roof_height + 1.5, 0), 22)
	await capture("08_upgrade_mid_airlift")
	effects.sync_airlifts([], game.by_id)
	# Higher cannon and house tiers must remain inside the native culling box.
	for kind: int in 4:
		home.kind = kind
		for level: int in range(1, (4 if kind in [0, 1] else 1) + 1):
			home.level = level
			home.refresh_visual()
			var points: PackedVector3Array = slot.entry_points_for(home)
			for point: Vector3 in points:
				assert(point.y > 0.0)
				assert(point.y + slot.DROP_HEIGHT + slot.SOLDIER.get_aabb().end.y * WarMarches.MODEL_SCALE < slot.get_node("Soldiers").multimesh.custom_aabb.end.y)
	await game.prepare_shutdown()
	print("PIG_AIRLIFT_VISUAL PASS captures=%d pause=true restored_batch=true transfer=true six_slot_replacement=true" % captures)
	quit()
