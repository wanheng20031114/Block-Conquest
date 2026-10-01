extends "res://tests/block_war_frog_test.gd"
## Mist weakens exposed enemies permanently, but buildings only while covered.

func _mist(at: Vector3, caster: int = 0, remaining: float = 3.0) -> void:
	game.marches.apply_frog_field(0, caster, at)
	game.marches.weak_zones[caster].remaining = remaining

func _arrival_at(target: WarBuilding, seconds: float) -> void:
	var at := target.global_position
	game.marches.send(0, target.building_id, 0, 1, PackedVector3Array([at + Vector3(WarMarches.SPEED * seconds, 0, 0), at]))

func _run() -> void:
	create_timer(100.0, true, false, true).timeout.connect(func(): quit(3))
	await reset("highland")
	var target: WarBuilding = game.buildings[1]
	target.faction = 1
	var center := target.global_position
	check(game.marches._units.is_empty(), "building-only mist fixture contains no exposed troops")
	check(game.cast_ground_skill(0, center), "mist can be cast directly over an enemy building without marching units")
	near(game.energy, 80.0, "building-only mist pays twenty energy")
	near(game.skill_defense_bonus(target), -0.25, "enemy building receives twenty-five percentage points less skill defense")
	near(game.combat_multiplier(0, target), 1.0 / 0.75, "building penalty enters the skill defense coefficient")
	for owner: int in [0, 2, 4, -1]:
		target.faction = owner
		near(game.skill_defense_bonus(target), 0.0, "mist protects own, allied and neutral building owner %d" % owner)
	for owner: int in [1, 3, 5]:
		target.faction = owner
		near(game.skill_defense_bonus(target), -0.25, "mist affects hostile building owner %d" % owner)
	target.faction = 1
	target.global_position = center + Vector3(RULES.FROG_RADII[0], 6.0, 0)
	near(game.skill_defense_bonus(target), -0.25, "exact horizontal radius includes elevated buildings")
	target.global_position.x += 0.01
	near(game.skill_defense_bonus(target), 0.0, "building just outside the radius keeps its defense")
	target.global_position = center
	_mist(center, 2, 1.0)
	near(game.skill_defense_bonus(target), -0.25, "two allied mist casters cannot double the building debuff")
	game.marches.tick(1.0)
	near(game.skill_defense_bonus(target), -0.25, "one remaining cloud keeps the full single penalty")
	game.marches.tick(2.0)
	near(game.skill_defense_bonus(target), 0.0, "the final cloud's expiry immediately restores building defense")
	_mist(center)
	game.faction_skills[2].commander = RULES.BEAR
	check(game.cast_skill(3, target, 2), "allied bear can curse the mist-covered enemy building")
	near(game.skill_defense_bonus(target), -0.55, "mist and hostile fireball bonuses add within the skill group")
	game.shields[target.building_id] = 8.0
	near(game.skill_defense_bonus(target), -0.30, "squirrel shield offsets part of the combined penalties")
	game.shields.clear()
	game._on_unit_arrived(target.building_id, 0, 9.0)
	near(target.population, 80.0, "real combat resolves nine attackers as twenty casualties under the combined penalties")
	game.marches.tick(3.0)
	near(game.skill_defense_bonus(target), -0.30, "mist expiry leaves the independent bear curse intact")
	game.bear.clear_building(game, target.building_id)
	_mist(center)
	game._on_unit_arrived(target.building_id, 0, 200.0)
	check(target.faction == 0, "real combat captures the mist-covered enemy building")
	near(game.skill_defense_bonus(target), 0.0, "capture by the caster's team removes the building debuff immediately")
	game._on_unit_arrived(target.building_id, 1, 400.0)
	check(target.faction == 1, "opposing troops recapture the same building while mist remains")
	near(game.skill_defense_bonus(target), -0.25, "hostile recapture restores coverage without a stale building status")
	await reset()
	target = game.buildings[1]
	target.faction = 1
	center = target.global_position
	target.population = 10.0
	var rate: float = target.production_rate
	_mist(center)
	game.simulate(0.5)
	near(target.population, 10.0 + rate * 0.5, "mist does not stop ordinary garrison production")
	target.begin_construction(-1, 30)
	var construction: float = target.construction_remaining
	game.simulate(0.5)
	near(target.construction_remaining, construction - 0.5, "mist does not stop a building upgrade")
	var remaining: float = game.marches.weak_zones[0].remaining
	game.set_paused(true)
	game.simulate(5.0)
	near(game.marches.weak_zones[0].remaining, remaining, "global pause preserves the remaining fog duration")
	near(game.skill_defense_bonus(target), -0.25, "paused cloud retains the same building penalty")
	game.set_paused(false)
	game.simulate(remaining)
	near(game.skill_defense_bonus(target), 0.0, "resuming and completing the remaining duration removes the penalty")
	for simulated: bool in [false, true]:
		for short_steps: bool in [false, true]:
			await reset()
			target = game.buildings[1]
			target.faction = 1
			_mist(target.global_position)
			_arrival_at(target, 2.98)
			_arrival_at(target, 3.02)
			for step: int in (72 if short_steps else 1):
				if simulated:
					game.simulate(0.05 if short_steps else 3.6)
				else:
					game.marches.tick(0.05 if short_steps else 3.6)
			near(target.population, 100.0 - 1.0 / 0.75 - 1.0, "arrivals before and after fog expiry use their own contact time; simulate=%s short=%s" % [simulated, short_steps])
			check(game.marches.weak_zones.is_empty(), "all stepping modes remove the expired cloud")
	# The expanding fire ring hits buildings after march movement in the same
	# simulation span. Keep mist defense until both kinds of damage have settled.
	for contact_time: float in [0.019, 0.031]:
		for short_steps: bool in [false, true]:
			await reset()
			target = game.buildings[1]
			target.faction = 1
			_mist(target.global_position, 0, 0.025)
			var radius := 4.5
			var distance: float = game.FIRE_STATE.radius_at(radius, contact_time)
			var fire: RefCounted = game.start_fire(target.global_position + Vector3(distance, 0, 0), radius, 0)
			check(not fire.hit_buildings.has(target.building_id), "fire boundary fixture begins before the expanding front reaches the building")
			for step: int in (20 if short_steps else 1):
				game.simulate(0.005 if short_steps else 0.1)
			var divisor := 0.75 if contact_time < 0.025 else 1.0
			near(target.population, 100.0 - game.IMPACT_DAMAGE / divisor, "real fire contact samples mist before/after expiry; contact=%.3f short=%s" % [contact_time, short_steps])
			check(fire.hit_buildings.has(target.building_id) and game.marches.weak_zones.is_empty(), "fire records one building hit and mist expires at its own boundary")
	# A long march tick now splits at mist expiry; splitting must retain the
	# original fire expansion and fire expiry, without replaying either half.
	await reset()
	_mist(Vector3(-20, 0, 0), 0, 0.5)
	var burned := soldier(0, Vector3(0, 0, 0), 0, 20)
	var survivor := soldier(0, Vector3(8, 0, 0), 0, 20)
	var fires: Array[Dictionary] = [{"center": Vector3.ZERO, "from_radius": 0.1, "to_radius": 20.0, "active_fraction": 0.25, "faction": 1}]
	game.marches.tick(2.0, fires)
	check(not burned.alive, "fire before the mist boundary still burns the nearby soldier")
	check(survivor.alive, "expired fire does not restart when the long tick crosses mist expiry")
	await game.prepare_shutdown()
	print("FROG_MIST_BUILDING checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
