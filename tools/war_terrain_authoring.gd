extends Resource
## Editor-authored closed outlines and open ramp splines, baked offline.
## Curve2D points and tangent handles remain editable in the native Inspector.
@export var plateaus: Array[Curve2D] = []
@export var plateau_heights := PackedFloat32Array()
@export var cliff_widths := PackedFloat32Array()
@export var basins: Array[Curve2D] = []
@export var basin_heights := PackedFloat32Array()
@export var ramps: Array[Curve2D] = []
@export var ramp_levels := PackedVector2Array()
@export var ramp_widths := PackedVector2Array()
@export var building_heights := PackedFloat32Array()
@export var labels := PackedVector3Array()
