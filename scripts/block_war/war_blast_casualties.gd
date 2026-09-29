extends MultiMeshInstance3D
## Short visual ragdolls use the real militia mesh and its tagged limb pivots.
## They never enter the marching army or participate in casualty accounting.
const MAX_BODIES := 384
const MAX_BURST := 18
const FACTION_BURST := 8
const SETTLE_TIME := 0.32
var bodies: Array[Dictionary] = []
var map_definition := WarMapDefinition.new()

func _ready() -> void:
	multimesh.instance_count = MAX_BODIES
	multimesh.visible_instance_count = 0

func burst(at: Vector3, faction: int, count: int, delay: float = 0.0) -> void:
	for index: int in count:
		var angle := index * 2.399963 + 0.37
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_add(at + direction * 1.3, direction, faction, index, delay)
	_render()

func soldier(at: Vector3, heading: Vector3, faction: int, impulse: Vector3) -> void:
	var direction := Vector3(impulse.x, 0, impulse.z).normalized()
	if direction.is_zero_approx(): direction = heading
	_add(at + Vector3.UP * 0.25, direction, faction, bodies.size() % MAX_BURST, 0.0)
	# A mass impact can remove thousands of exposed marchers in one rule step.
	# Upload once in tick, like ordinary casualties, instead of once per victim.

func _add(at: Vector3, direction: Vector3, faction: int, index: int, delay: float) -> void:
	if bodies.size() == MAX_BODIES: bodies.pop_front()
	var landing := map_definition.surface_point(at + direction * (3.4 + (index % 5) * 0.55)) + Vector3.UP * 0.16
	bodies.append({"at": at, "landing": landing, "direction": direction, "faction": faction,
		"age": -delay, "flight": 0.57 + (index % 4) * 0.05,
		"arc": 1.8 + (index % 3) * 0.28, "spin": -1.0 if index % 2 else 1.0})

func tick(delta: float) -> void:
	for index: int in range(bodies.size() - 1, -1, -1):
		bodies[index].age += delta
		if bodies[index].age >= bodies[index].flight + SETTLE_TIME:
			bodies.remove_at(index)
	_render()

func clear() -> void:
	bodies.clear()
	multimesh.visible_instance_count = 0

func _render() -> void:
	var slot := 0
	for body: Dictionary in bodies:
		if body.age < 0.0: continue
		var flight := clampf(float(body.age) / float(body.flight), 0.0, 1.0)
		var grounded := maxf(0.0, float(body.age) - float(body.flight))
		var direction: Vector3 = body.direction
		var at: Vector3 = body.at.lerp(body.landing, flight)
		at.y += 4.0 * float(body.arc) * flight * (1.0 - flight)
		# Finish on the side, then skid briefly instead of sinking through terrain.
		at += direction * (1.0 - exp(-grounded * 16.0)) * 0.23
		at.y += sin(minf(1.0, grounded / 0.13) * PI) * 0.08
		var pitch: float = (TAU + PI * 0.5) * flight * float(body.spin)
		var basis := Basis(Vector3.UP, atan2(-direction.x, -direction.z)) * Basis(Vector3.RIGHT, pitch)
		basis = basis.scaled(Vector3.ONE * WarMarches.MODEL_SCALE)
		# Rotate around the torso so the landing silhouette remains above ground.
		var pivot := Vector3.UP * 0.66
		multimesh.set_instance_transform(slot, Transform3D(basis, at - basis * pivot))
		var color := Color("aaa48b") if body.faction < 0 else WarMarches.FACTION_COLORS[body.faction]
		color = color.srgb_to_linear()
		color.a = flight * 0.7 + clampf(grounded / SETTLE_TIME, 0.0, 1.0) * 0.3
		multimesh.set_instance_custom_data(slot, color)
		slot += 1
	multimesh.visible_instance_count = slot
