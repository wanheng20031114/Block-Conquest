extends RefCounted
## Authoritative fire has no node, particle pool slot, viewport or quality setting.

const EXPANSION_TIME := 0.28
const IGNITION_RADIUS := 0.45
const EMISSION_TIME := 1.65
const BURN_TIME := 2.15
const LIFETIME := 3.0

var effect_id := 0
var global_position := Vector3.ZERO
var radius := 4.5
var faction := 0
var age := 0.0
var hit_buildings: Dictionary = {}

static func radius_at(reach: float, at_age: float) -> float:
	if is_equal_approx(at_age, EXPANSION_TIME):
		return reach
	return lerpf(minf(IGNITION_RADIUS, reach), reach, clampf(at_age / EXPANSION_TIME, 0.0, 1.0))

func front(at_age: float) -> float:
	return radius_at(radius, at_age)

func segment(delta: float) -> Dictionary:
	return {"center": global_position, "from_radius": front(age), "to_radius": front(age + delta),
		"active_fraction": minf(1.0, (BURN_TIME - age) / delta), "faction": faction}
