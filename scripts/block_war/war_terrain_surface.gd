class_name WarTerrainSurface
extends Resource
## One baked ground shared by rendered triangles, marching, effects and picking.
## Each cell is split from its (x + 1, z) corner to its (x, z + 1) corner.

@export var origin := Vector2.ZERO
@export var cell_size := 0.5
@export var width := 0
@export var depth := 0
@export var heights := PackedFloat32Array()
@export var height_texture: Texture2D
@export var preview_texture: Texture2D
@export var ramp_guides := PackedVector4Array()
@export var label_positions := PackedVector3Array()
@export var max_height := 0.0

const HEIGHT_EPSILON := 0.0001
const RATIO_EPSILON := 0.00000001

func bounds() -> Rect2:
	return Rect2(origin, Vector2(width - 1, depth - 1) * cell_size)

func _inside_grid(point: Vector2) -> bool:
	return point.x >= 0.0 and point.y >= 0.0 and point.x <= width - 1 and point.y <= depth - 1

func sample(point: Vector2) -> float:
	var grid := (point - origin) / cell_size
	if not _inside_grid(grid):
		return 0.0
	var x := mini(floori(grid.x), width - 2)
	var z := mini(floori(grid.y), depth - 2)
	var u := grid.x - x
	var v := grid.y - z
	var index := z * width + x
	var b := heights[index + 1]
	var c := heights[index + width]
	if u + v <= 1.0:
		return heights[index] * (1.0 - u - v) + b * u + c * v
	return b * (1.0 - v) + c * (1.0 - u) + heights[index + width + 1] * (u + v - 1.0)

func gradient_at(point: Vector2) -> Vector2:
	var grid := (point - origin) / cell_size
	if not _inside_grid(grid):
		return Vector2.ZERO
	var x := mini(floori(grid.x), width - 2)
	var z := mini(floori(grid.y), depth - 2)
	var index := z * width + x
	var b := heights[index + 1]
	var c := heights[index + width]
	if grid.x - x + grid.y - z <= 1.0:
		var a := heights[index]
		return Vector2(b - a, c - a) / cell_size
	var d := heights[index + width + 1]
	return Vector2(d - c, d - b) / cell_size

func breakpoints(from: Vector2, to: Vector2) -> PackedFloat32Array:
	# Grid crossings bound each interval to one cell; its diagonal supplies the
	# remaining plane boundary. No fixed-distance probe can miss a narrow face.
	var start := (from - origin) / cell_size
	var finish := (to - origin) / cell_size
	var span := finish - start
	var cuts: Array[float] = [0.0, 1.0]
	if absf(span.x) > RATIO_EPSILON:
		for x: int in range(maxi(0, ceili(minf(start.x, finish.x))), mini(width - 1, floori(maxf(start.x, finish.x))) + 1):
			var ratio := (x - start.x) / span.x
			if ratio > 0.0 and ratio < 1.0:
				cuts.append(ratio)
	if absf(span.y) > RATIO_EPSILON:
		for z: int in range(maxi(0, ceili(minf(start.y, finish.y))), mini(depth - 1, floori(maxf(start.y, finish.y))) + 1):
			var ratio := (z - start.y) / span.y
			if ratio > 0.0 and ratio < 1.0:
				cuts.append(ratio)
	cuts.sort()
	var diagonal_span := span.x + span.y
	var diagonals: Array[float] = []
	if absf(diagonal_span) > RATIO_EPSILON:
		for index: int in range(1, cuts.size()):
			var middle := start.lerp(finish, (cuts[index - 1] + cuts[index]) * 0.5)
			if not _inside_grid(middle):
				continue
			var x := mini(floori(middle.x), width - 2)
			var z := mini(floori(middle.y), depth - 2)
			var ratio := (x + z + 1.0 - start.x - start.y) / diagonal_span
			if ratio > cuts[index - 1] and ratio < cuts[index]:
				diagonals.append(ratio)
	cuts.append_array(diagonals)
	cuts.sort()
	var unique := PackedFloat32Array([0.0])
	# Deduplicate after conversion too: adjacent double-precision ratios can
	# round onto one Float32 boundary and must not create a zero-length face.
	var packed := PackedFloat32Array(cuts)
	for ratio: float in packed:
		if ratio - unique[-1] > RATIO_EPSILON:
			unique.append(ratio)
	if unique[-1] < 1.0:
		unique.append(1.0)
	return unique

func segment_walkable(from: Vector2, to: Vector2, max_gradient: float = 0.5) -> bool:
	if from.is_equal_approx(to):
		return gradient_at(from).length() <= max_gradient + HEIGHT_EPSILON
	var cuts := breakpoints(from, to)
	var previous_height := sample(from)
	for index: int in range(1, cuts.size()):
		var start := from.lerp(to, cuts[index - 1])
		var finish := from.lerp(to, cuts[index])
		var middle := start.lerp(finish, 0.5)
		var gradient := gradient_at(middle)
		if gradient.length() > max_gradient + HEIGHT_EPSILON:
			return false
		var height := sample(middle)
		var start_height := height + (start - middle).dot(gradient)
		var finish_height := height + (finish - middle).dot(gradient)
		# Authored fields join y=0 at their outer border. Reject malformed seams
		# rather than allowing an implicit drop where the finite grid ends.
		if absf(start_height - previous_height) > HEIGHT_EPSILON or absf(finish_height - sample(finish)) > HEIGHT_EPSILON:
			return false
		previous_height = finish_height
	return true

func ray_ground(ray_origin: Vector3, direction: Vector3) -> Vector3:
	if not ray_origin.is_finite() or not direction.is_finite() or direction.length_squared() < 0.000000000001:
		return Vector3.INF
	var start_xz := Vector2(ray_origin.x, ray_origin.z)
	var direction_xz := Vector2(direction.x, direction.z)
	if direction_xz.length_squared() < 0.000000000001:
		if absf(direction.y) < RATIO_EPSILON:
			return Vector3.INF
		var distance := (sample(start_xz) - ray_origin.y) / direction.y
		return ray_origin + direction * distance if distance >= 0.0 else Vector3.INF
	var nearest := Vector3.INF
	var nearest_distance := INF
	# Outside the authored field, the surrounding floor retains its y=0 plane.
	var base: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, direction)
	if base != null and not _inside_grid((Vector2(base.x, base.z) - origin) / cell_size):
		nearest = base
		nearest_distance = ray_origin.distance_squared_to(base)
	var interval := _ray_grid_interval(start_xz, direction_xz)
	if not interval.is_finite():
		return nearest
	var rect := bounds()
	var from := (start_xz + direction_xz * interval.x).clamp(rect.position, rect.end)
	var to := (start_xz + direction_xz * interval.y).clamp(rect.position, rect.end)
	var cuts := breakpoints(from, to)
	for index: int in range(1, cuts.size()):
		var first_distance := lerpf(interval.x, interval.y, cuts[index - 1])
		var last_distance := lerpf(interval.x, interval.y, cuts[index])
		var first := ray_origin + direction * first_distance
		var last := ray_origin + direction * last_distance
		var first_gap := first.y - sample(from.lerp(to, cuts[index - 1]))
		var last_gap := last.y - sample(from.lerp(to, cuts[index]))
		var ratio := -1.0
		if absf(first_gap) <= HEIGHT_EPSILON:
			ratio = 0.0
		elif first_gap * last_gap <= 0.0:
			ratio = first_gap / (first_gap - last_gap)
		if ratio < 0.0:
			continue
		var hit := first.lerp(last, ratio)
		if ray_origin.distance_squared_to(hit) < nearest_distance:
			return hit
		return nearest
	return nearest

func _ray_grid_interval(from: Vector2, direction: Vector2) -> Vector2:
	var rect := bounds()
	var enter := 0.0
	var leave := INF
	for axis: int in 2:
		if absf(direction[axis]) < RATIO_EPSILON:
			if from[axis] < rect.position[axis] or from[axis] > rect.end[axis]:
				return Vector2.INF
			continue
		var first := (rect.position[axis] - from[axis]) / direction[axis]
		var last := (rect.end[axis] - from[axis]) / direction[axis]
		enter = maxf(enter, minf(first, last))
		leave = minf(leave, maxf(first, last))
		if enter > leave:
			return Vector2.INF
	return Vector2(enter, leave)
