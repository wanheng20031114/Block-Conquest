extends Node3D
## All transformations are relative to the building's authored foot origin.
## Only the Visual moves; population badges, pick areas and world position stay fixed.

@export var preset: WarSelectionMotionPreset
@onready var building: WarBuilding = $Building
@onready var body: Node3D = $Building/Visual
var motion: Tween
var _upper: Node3D
var _upper_rest: Transform3D
var _body_rest: Transform3D
var peak_displacement := 0.0

func _ready() -> void:
	_body_rest = body.transform
	_upper = building.get_node(["Visual/House/Roof", "Visual/Tower/Gun", "Visual/Smithy/Roof"][building.kind])
	_upper_rest = _upper.transform
	# Ambient motion is held for fair, seamless comparison of the click itself.
	building.set_visual_paused(true)

func play_motion() -> void:
	if motion != null:
		motion.kill()
	body.transform = _body_rest
	_upper.transform = _upper_rest
	building.set_selected(false)
	building.set_selected(true)
	building.get_node("KindLabel").hide()
	building._selection_tween.pause()
	motion = create_tween()
	motion.tween_method(sample_motion, 0.0, 1.0, preset.duration).set_trans(Tween.TRANS_LINEAR)
	motion.pause()

func advance(delta: float) -> void:
	if motion != null and motion.is_valid():
		motion.custom_step(delta)
	if building._selection_tween != null and building._selection_tween.is_valid():
		building._selection_tween.custom_step(delta)

func reset_motion() -> void:
	if motion != null:
		motion.kill()
	body.transform = _body_rest
	_upper.transform = _upper_rest
	building.set_selected(false)

func sample_motion(progress: float) -> void:
	var height := 1.0 + preset.stretch.sample_baked(progress)
	# Preserve approximate volume: a vertical compression spreads the footprint.
	var width := 1.0 / sqrt(height)
	var angles := Vector3(
		deg_to_rad(preset.pitch.sample_baked(progress)),
		deg_to_rad(preset.yaw.sample_baked(progress)),
		deg_to_rad(preset.roll.sample_baked(progress)))
	# Rock on the touching edge instead of burying a corner below the ground.
	var foot_clearance := absf(sin(angles.z)) * 1.75 + absf(sin(angles.x)) * 1.65
	var offset := Vector3(0, preset.lift.sample_baked(progress) + foot_clearance, 0)
	body.transform = _body_rest * Transform3D(Basis.from_euler(angles).scaled_local(Vector3(width, height, width)), offset)
	_upper.transform = _upper_rest
	_upper.position.y += preset.upper.sample_baked(progress)
	peak_displacement = maxf(peak_displacement, absf(height - 1.0) + angles.length() + offset.length() + absf(_upper.position.y - _upper_rest.origin.y))
