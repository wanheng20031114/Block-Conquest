class_name WarMorale
extends RefCounted
## Per-faction morale. Only actual morale events reset the idle clock.
## Idle decay settles in one-second steps: the first deduction happens exactly
## at the current level's delay, then at least one second after each settlement.
## A lower level's longer delay can postpone the next deduction. Processing
## each due settlement makes one long simulation tick agree with short ticks.

signal changed(faction: int)

const THRESHOLDS: Array[float] = [0.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
const IDLE_DELAYS: Array[float] = [10.0, 9.0, 8.0, 7.0, 6.0, 5.0]
const DECAY_PER_SECOND: Array[float] = [10.0, 20.0, 25.0, 50.0, 100.0, 200.0]
const MAX_POINTS := 8000.0
const KILL_REWARD := 10.0
const ATTACKER_LOSS_PENALTY := 10.0
# A nanosecond tolerance only absorbs floating-point clock accumulation. It
# never changes morale thresholds, levels, or the integer settlement times.
const CLOCK_TOLERANCE := 0.000000001

const NEUTRAL_HOUSE: Array[int] = [40, 100, 160, 220, 300]
const NEUTRAL_TOWER: Array[int] = [80, 200, 320, 440]
const ENEMY_HOUSE: Array[int] = [100, 250, 400, 550, 750]
const ENEMY_TOWER: Array[int] = [200, 500, 800, 1100]
const LOST_HOUSE: Array[int] = [50, 120, 200, 280, 380]
const LOST_TOWER: Array[int] = [100, 250, 400, 550]
const HOUSE_UPGRADE: Array[int] = [50, 100, 150, 200]
const TOWER_UPGRADE: Array[int] = [100, 200, 300, 400]

var _points := PackedFloat64Array()
var _idle_seconds := PackedFloat64Array()
var _next_decay_at := PackedFloat64Array()
var _in_step := false
var _active_in_step := PackedByteArray()

func configure(faction_count: int) -> void:
	assert(not _in_step)
	assert(faction_count > 0)
	_points.resize(faction_count)
	_points.fill(0.0)
	_idle_seconds.resize(faction_count)
	_idle_seconds.fill(0.0)
	_next_decay_at.resize(faction_count)
	_next_decay_at.fill(IDLE_DELAYS[0])
	_active_in_step.resize(faction_count)
	_active_in_step.fill(0)
	for faction: int in faction_count:
		changed.emit(faction)

func points(faction: int) -> float:
	assert(faction >= 0 and faction < _points.size())
	return _points[faction]

func idle_seconds(faction: int) -> float:
	assert(faction >= 0 and faction < _points.size())
	return _idle_seconds[faction]

func level(faction: int) -> int:
	return _level_for(points(faction))

func stars(faction: int) -> float:
	var value := points(faction)
	var whole := _level_for(value)
	if whole == THRESHOLDS.size() - 1:
		return float(whole)
	return whole + (value - THRESHOLDS[whole]) / (THRESHOLDS[whole + 1] - THRESHOLDS[whole])

func attack(faction: int) -> float:
	return 1.0 if faction < 0 else 1.0 + 0.05 * level(faction)

func defense(faction: int) -> float:
	return 1.0 if faction < 0 else 1.0 + 0.25 * level(faction)

func speed(faction: int) -> float:
	return 1.0 if faction < 0 else 1.0 + 0.1 * level(faction)

func step_limit() -> float:
	# tick() settles every due event before returning, so a scheduled event is
	# always strictly in the future. Zero-point seats have nothing to decay.
	var seconds := INF
	for faction: int in _points.size():
		if _points[faction] > 0.0:
			seconds = minf(seconds, _next_decay_at[faction] - _idle_seconds[faction])
	return seconds

func adjust(faction: int, amount: float) -> void:
	assert(faction >= 0 and faction < _points.size())
	assert(is_finite(amount))
	if amount == 0.0:
		return
	if _in_step:
		_active_in_step[faction] = 1
	var previous := _points[faction]
	_points[faction] = clampf(previous + amount, 0.0, MAX_POINTS)
	# An event at either cap is still activity, even if it cannot change points.
	_idle_seconds[faction] = 0.0
	_next_decay_at[faction] = IDLE_DELAYS[_level_for(_points[faction])]
	if _points[faction] != previous:
		changed.emit(faction)

func begin_step() -> void:
	assert(not _in_step, "Morale simulation steps cannot nest.")
	_in_step = true
	_active_in_step.fill(0)

func end_step(delta: float) -> void:
	assert(_in_step, "A morale simulation step must begin before it ends.")
	_in_step = false
	# Combat is resolved at the end of the enclosing simulation step. Its events
	# already update bonuses immediately, but must not age by the preceding time.
	_advance(delta, true)

func tick(delta: float) -> void:
	assert(not _in_step, "Use end_step() to complete an active simulation step.")
	_advance(delta, false)

func _advance(delta: float, skip_active: bool) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	if delta == 0.0:
		return
	for faction: int in _points.size():
		if skip_active and _active_in_step[faction] != 0:
			continue
		_idle_seconds[faction] += delta
		var previous := _points[faction]
		while _points[faction] > 0.0 and _idle_seconds[faction] + CLOCK_TOLERANCE >= _next_decay_at[faction]:
			var whole := _level_for(_points[faction])
			_points[faction] = maxf(0.0, _points[faction] - DECAY_PER_SECOND[whole])
			_next_decay_at[faction] = maxf(_next_decay_at[faction] + 1.0, IDLE_DELAYS[_level_for(_points[faction])])
		if _points[faction] != previous:
			changed.emit(faction)

static func capture_reward(kind: int, building_level: int, neutral: bool) -> int:
	assert(kind in [0, 1, 2, 3])
	if kind in [2, 3]:
		assert(building_level == 1)
		return 200 if neutral else 300
	var rewards: Array[int] = (NEUTRAL_HOUSE if neutral else ENEMY_HOUSE) if kind == 0 else (NEUTRAL_TOWER if neutral else ENEMY_TOWER)
	assert(building_level >= 1 and building_level <= rewards.size())
	return rewards[building_level - 1]

static func loss_penalty(kind: int, building_level: int) -> int:
	assert(kind in [0, 1, 2, 3])
	if kind in [2, 3]:
		assert(building_level == 1)
		return 100
	var penalties: Array[int] = LOST_HOUSE if kind == 0 else LOST_TOWER
	assert(building_level >= 1 and building_level <= penalties.size())
	return penalties[building_level - 1]

static func upgrade_reward(kind: int, completed_level: int) -> int:
	assert(kind in [0, 1, 2, 3])
	assert(completed_level >= 1)
	if kind in [2, 3] or completed_level == 1:
		return 0
	# Existing buildings start at level 1: their first completed upgrade to 2
	# corresponds to the reference's first upgrade, rather than its second.
	var rewards: Array[int] = HOUSE_UPGRADE if kind == 0 else TOWER_UPGRADE
	assert(completed_level <= rewards.size() + 1)
	return rewards[completed_level - 2]

static func _level_for(value: float) -> int:
	for whole: int in range(THRESHOLDS.size() - 1, 0, -1):
		if value >= THRESHOLDS[whole]:
			return whole
	return 0
