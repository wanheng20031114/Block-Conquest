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
	await capture("01_allied_descent")
	await advance(0.25)
	assert(slot.landed_batches == 1)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 16)
	await capture("02_touchdown_next_batch")
	var age: float = slot.age
	var pose: Transform3D = slot.get_node("Soldiers").multimesh.get_instance_transform(0)
	game.set_paused(true)
	await advance(0.8)
	assert(is_equal_approx(slot.age, age))
	assert(slot.get_node("Soldiers").multimesh.get_instance_transform(0).is_equal_approx(pose))
	assert(slot.get_node("Dust").speed_scale == 0.0)
	game.set_paused(false)
	await advance(1.60)
	assert(game.pig.airlifts[0].landed == 40)
	assert(slot.get_node("Soldiers").multimesh.visible_instance_count == 8)
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
	await game.prepare_shutdown()
	print("PIG_AIRLIFT_VISUAL PASS captures=%d pause=true restored_batch=true transfer=true six_slot_replacement=true" % captures)
	quit()
