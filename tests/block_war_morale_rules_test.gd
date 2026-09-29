extends SceneTree
## Pure morale rules; no battle, transport, save, or rendering fixture required.

const Morale = preload("res://scripts/block_war/war_morale.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_levels_and_stars()
	_rewards()
	_idle_settlements()
	_activity_and_factions()
	_step_events()
	_step_boundaries()
	_partitioned_ticks()
	print("BLOCK_WAR_MORALE_RULES_RESULTS " + JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL ", label)

func fresh(value: float = 0.0, count: int = 1) -> RefCounted:
	var morale := Morale.new()
	morale.configure(count)
	if value != 0.0:
		morale.adjust(0, value)
	return morale

func _levels_and_stars() -> void:
	var thresholds := [0.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
	for whole: int in thresholds.size():
		var morale := fresh(thresholds[whole])
		check(morale.level(0) == whole and morale.stars(0) == float(whole), "threshold_enters_level_%d" % whole)
		check(is_equal_approx(morale.attack(0), 1.0 + 0.05 * whole), "attack_bonus_level_%d" % whole)
		check(is_equal_approx(morale.defense(0), 1.0 + 0.20 * whole), "defense_bonus_level_%d" % whole)
		check(is_equal_approx(morale.speed(0), 1.0 + 0.1 * whole), "speed_bonus_level_%d" % whole)
		if whole < thresholds.size() - 1:
			morale.adjust(0, (thresholds[whole + 1] - thresholds[whole]) * 0.5)
			check(is_equal_approx(morale.stars(0), whole + 0.5), "fraction_uses_adjacent_total_thresholds_%d" % whole)
			check(morale.level(0) == whole, "partial_star_does_not_grant_full_level_%d" % whole)
		if whole > 0:
			var below := fresh(thresholds[whole] - 0.001)
			check(below.level(0) == whole - 1, "below_threshold_retains_lower_bonus_%d" % whole)
			check(is_equal_approx(below.attack(0), 1.0 + 0.05 * (whole - 1)), "below_threshold_retains_lower_attack_%d" % whole)
			check(is_equal_approx(below.defense(0), 1.0 + 0.20 * (whole - 1)), "below_threshold_retains_lower_defense_%d" % whole)
			check(is_equal_approx(below.speed(0), 1.0 + 0.10 * (whole - 1)), "below_threshold_retains_lower_speed_%d" % whole)
	var capped := fresh(1000000.0)
	check(capped.points(0) == 8000.0 and capped.level(0) == 5 and capped.stars(0) == 5.0, "positive_events_cap_at_five_stars")
	capped.adjust(0, -1000000.0)
	check(capped.points(0) == 0.0 and capped.level(0) == 0, "negative_events_cannot_create_negative_morale")
	check(capped.attack(-1) == 1.0 and capped.defense(-1) == 1.0 and capped.speed(-1) == 1.0, "neutral_has_no_bonus")

func _rewards() -> void:
	var neutral_houses := [40, 100, 160, 220, 300]
	var neutral_towers := [80, 200, 320, 440]
	var enemy_houses := [100, 250, 400, 550, 750]
	var enemy_towers := [200, 500, 800, 1100]
	var lost_houses := [50, 120, 200, 280, 380]
	var lost_towers := [100, 250, 400, 550]
	for index: int in neutral_houses.size():
		check(Morale.capture_reward(0, index + 1, true) == neutral_houses[index], "neutral_house_reward_%d" % (index + 1))
		check(Morale.capture_reward(0, index + 1, false) == enemy_houses[index], "enemy_house_reward_%d" % (index + 1))
		check(Morale.loss_penalty(0, index + 1) == lost_houses[index], "lost_house_penalty_%d" % (index + 1))
	for index: int in neutral_towers.size():
		check(Morale.capture_reward(1, index + 1, true) == neutral_towers[index], "neutral_tower_reward_%d" % (index + 1))
		check(Morale.capture_reward(1, index + 1, false) == enemy_towers[index], "enemy_tower_reward_%d" % (index + 1))
		check(Morale.loss_penalty(1, index + 1) == lost_towers[index], "lost_tower_penalty_%d" % (index + 1))
	check(Morale.capture_reward(2, 1, true) == 200 and Morale.capture_reward(2, 1, false) == 300 and Morale.loss_penalty(2, 1) == 100, "smithy_rewards_and_loss")
	for completed_level: int in range(2, 6):
		check(Morale.upgrade_reward(0, completed_level) == [50, 100, 150, 200][completed_level - 2], "house_upgrade_uses_completed_upgrade_count_%d" % completed_level)
		check(Morale.upgrade_reward(1, completed_level) == [100, 200, 300, 400][completed_level - 2], "tower_upgrade_uses_completed_upgrade_count_%d" % completed_level)
	for kind: int in 3:
		check(Morale.upgrade_reward(kind, 1) == 0, "initial_or_converted_building_has_no_upgrade_reward_%d" % kind)
	check(Morale.KILL_REWARD == 10.0 and Morale.ATTACKER_LOSS_PENALTY == 10.0, "combat_point_values")

func _idle_settlements() -> void:
	var starts := [250.0, 750.0, 1500.0, 3000.0, 6000.0, 8000.0]
	var delays := [10.0, 9.0, 8.0, 7.0, 6.0, 5.0]
	var rates := [10.0, 20.0, 25.0, 50.0, 100.0, 200.0]
	for whole: int in starts.size():
		var morale := fresh(starts[whole])
		morale.tick(delays[whole] - 0.01)
		check(morale.points(0) == starts[whole], "no_decay_before_delay_%d" % whole)
		morale.tick(0.01)
		check(morale.points(0) == starts[whole] - rates[whole], "first_full_deduction_at_delay_%d" % whole)
		morale.tick(0.5)
		check(morale.points(0) == starts[whole] - rates[whole], "no_partial_deduction_between_settlements_%d" % whole)
	var maximum := fresh(8000.0)
	maximum.tick(5.0)
	check(maximum.points(0) == 7800.0 and maximum.level(0) == 4, "five_star_first_deduction_uses_200")
	maximum.tick(1.0)
	check(maximum.points(0) == 7700.0, "sixth_idle_second_uses_four_star_100")
	var boundary := fresh(1000.0)
	boundary.tick(8.0)
	check(boundary.points(0) == 975.0 and boundary.level(0) == 1, "two_star_boundary_deducts_old_level_rate")
	boundary.tick(1.0)
	check(boundary.points(0) == 955.0, "lower_level_delay_is_respected_after_crossing")
	var low := fresh(5.0)
	low.tick(10000.0)
	check(low.points(0) == 0.0 and low.stars(0) == 0.0, "long_idle_clamps_at_zero")

func _activity_and_factions() -> void:
	var morale := Morale.new()
	var notifications: Array[int] = []
	morale.changed.connect(func(faction: int): notifications.append(faction))
	morale.configure(3)
	check(notifications == [0, 1, 2], "configure_initializes_every_faction_observer")
	notifications.clear()
	morale.adjust(0, 8000.0)
	morale.adjust(1, 750.0)
	check(notifications == [0, 1], "adjust_only_notifies_changed_factions")
	morale.tick(4.0)
	morale.adjust(0, 10.0)
	check(morale.points(0) == 8000.0 and morale.idle_seconds(0) == 0.0, "capped_positive_event_still_resets_activity")
	morale.tick(4.0)
	check(morale.points(0) == 8000.0 and morale.points(1) == 750.0, "each_faction_has_independent_idle_clock")
	morale.tick(1.0)
	check(morale.points(0) == 7800.0 and morale.points(1) == 730.0, "independent_factions_settle_when_due")
	morale.adjust(0, -10.0)
	check(morale.points(0) == 7790.0 and morale.idle_seconds(0) == 0.0, "negative_event_also_resets_activity")
	morale.tick(5.0)
	check(morale.points(0) == 7790.0, "negative_event_restarts_current_level_delay")
	morale.adjust(0, 0.0)
	check(morale.idle_seconds(0) == 5.0, "zero_adjustment_is_not_an_activity_event")
	morale.tick(1.0)
	check(morale.points(0) == 7690.0, "zero_adjustment_does_not_postpone_decay")
	morale.adjust(2, -10.0)
	check(morale.points(2) == 0.0 and morale.idle_seconds(2) == 0.0, "zero_floor_penalty_still_resets_activity")
	morale.configure(2)
	check(morale.points(0) == 0.0 and morale.points(1) == 0.0 and morale.idle_seconds(0) == 0.0, "new_match_clears_points_and_clocks")

func _step_events() -> void:
	var morale := fresh(8000.0, 3)
	morale.adjust(1, 750.0)
	morale.tick(4.0)
	morale.begin_step()
	morale.adjust(0, 10.0)
	morale.adjust(2, -10.0)
	morale.end_step(5.0)
	check(morale.points(0) == 8000.0 and morale.idle_seconds(0) == 0.0,
		"in_step_capped_positive_event_does_not_age_by_preceding_time")
	check(morale.points(2) == 0.0 and morale.idle_seconds(2) == 0.0,
		"in_step_zero_floor_penalty_does_not_age_by_preceding_time")
	check(morale.points(1) == 730.0 and morale.idle_seconds(1) == 9.0,
		"faction_without_step_event_still_settles_due_decay")
	morale.begin_step()
	morale.adjust(0, 0.0)
	morale.end_step(5.0)
	check(morale.points(0) == 7800.0 and morale.idle_seconds(0) == 5.0,
		"zero_adjustment_does_not_mark_faction_active_in_step")
	var immediate := fresh(499.0)
	var updates: Array[int] = []
	immediate.changed.connect(func(faction: int): updates.append(faction))
	immediate.begin_step()
	immediate.adjust(0, 1.0)
	check(immediate.level(0) == 1 and is_equal_approx(immediate.attack(0), 1.05)
		and is_equal_approx(immediate.speed(0), 1.1) and updates == [0],
		"step_event_immediately_updates_level_bonuses_and_observers")
	immediate.end_step(30.0)
	check(immediate.points(0) == 500.0 and immediate.idle_seconds(0) == 0.0
		and immediate.step_limit() == 9.0, "long_step_cannot_retroactively_decay_new_event")
	immediate.begin_step()
	immediate.end_step(8.0)
	check(immediate.points(0) == 500.0 and immediate.step_limit() == 1.0,
		"next_step_clears_previous_activity_flags")
	immediate.tick(1.0)
	check(immediate.points(0) == 480.0, "standalone_tick_still_advances_after_completed_step")
	var ordinary := fresh(8000.0)
	var stepped := fresh(8000.0)
	ordinary.tick(100.0)
	stepped.begin_step()
	stepped.end_step(100.0)
	check(ordinary.points(0) == stepped.points(0) and ordinary.step_limit() == stepped.step_limit(),
		"event_free_step_matches_standalone_tick")
	stepped.begin_step()
	stepped.adjust(0, 15.0)
	stepped.adjust(0, -5.0)
	var after_events: float = stepped.points(0)
	stepped.end_step(2.0)
	check(stepped.points(0) == after_events and stepped.idle_seconds(0) == 0.0,
		"multiple_step_events_keep_latest_points_and_fresh_clock")

func _step_boundaries() -> void:
	var morale := fresh(0.0, 3)
	check(is_inf(morale.step_limit()), "empty_factions_have_no_decay_boundary")
	morale.adjust(0, 8000.0)
	morale.adjust(1, 1000.0)
	check(morale.step_limit() == 5.0, "step_limit_uses_earliest_faction_event")
	morale.tick(4.5)
	check(morale.step_limit() == 0.5, "step_limit_tracks_partial_elapsed_time")
	morale.tick(morale.step_limit())
	check(morale.points(0) == 7800.0 and morale.step_limit() == 1.0, "boundary_tick_settles_before_returning_positive_limit")
	morale.adjust(0, 10.0)
	check(morale.step_limit() == 3.0, "activity_reschedule_exposes_next_faction_boundary")
	morale.adjust(0, -10000.0)
	morale.adjust(1, -10000.0)
	check(is_inf(morale.step_limit()), "zeroed_factions_remove_scheduled_boundaries")
	var split := fresh(8000.0)
	var whole := fresh(8000.0)
	whole.tick(100.0)
	var remaining := 100.0
	var steps := 0
	while remaining > 0.0:
		var step := minf(remaining, split.step_limit())
		check(step > 0.0, "step_limit_never_stalls_after_settlement_%d" % steps)
		if step <= 0.0:
			break
		split.tick(step)
		remaining -= step
		steps += 1
	check(split.points(0) == whole.points(0), "simulation_splitting_at_boundaries_matches_one_tick")

func _partitioned_ticks() -> void:
	var starts := [1.0, 499.0, 500.0, 501.0, 999.0, 1000.0, 1001.0, 1999.0, 2000.0, 2001.0, 3999.0, 4000.0, 4001.0, 7999.0, 8000.0]
	var durations := [4.99, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 29.75, 60.0, 180.0]
	for start: float in starts:
		for duration: float in durations:
			var one := fresh(start)
			var many := fresh(start)
			one.tick(duration)
			var count := floori(duration / 0.07)
			for _index: int in count:
				many.tick(0.07)
			many.tick(maxf(0.0, duration - count * 0.07))
			check(one.points(0) == many.points(0) and one.level(0) == many.level(0), "large_and_small_ticks_agree_%s_at_%s" % [start, duration])
	var long_tick := fresh(8000.0)
	var short_ticks := fresh(8000.0)
	long_tick.tick(10000.0)
	for _index: int in 1000:
		short_ticks.tick(10.0)
	check(long_tick.points(0) == short_ticks.points(0) and long_tick.points(0) == 0.0, "long_tick_reaches_same_empty_state")
