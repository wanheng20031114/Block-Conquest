class_name LobbyDiorama
extends SubViewportContainer
## An authored riverside world, isolated from match simulation and audio.
var clock := 0.0
var pointer_target := Vector2.ZERO
var pointer := Vector2.ZERO
var interactive := true
var ripple_age := 10.0
var hover_owner: LobbyOutpost
@onready var viewport: SubViewport = $World
@onready var camera: Camera3D = $World/Stage/CameraRig/Camera3D
@onready var rig: Node3D = $World/Stage/CameraRig
@onready var outposts: Array[Node] = $World/Stage/Island/Outposts.get_children()
@onready var flag_material: ShaderMaterial = $World/Stage/Island/Outposts/Home/Lift/Model/Flag.material_override
@onready var water_material: ShaderMaterial = $World/Stage/Island/Water.material_override
@onready var leaves: ShaderMaterial = $World/Stage/Island/Trees/Oak/Foliage.material_override
@onready var camera_rest: Vector3 = rig.rotation
@onready var ferry: PathFollow3D = $World/Stage/Island/FerryRoute/Ferry
@onready var raft: Node3D = $World/Stage/Island/FerryRoute/Ferry/Raft

func _ready() -> void:
	mouse_exited.connect(_leave)
	for outpost: LobbyOutpost in outposts:
		outpost.touched.connect(_touched)
		outpost.hover_changed.connect(_hover_changed)
	$World/Stage/Island/WaterPick.input_event.connect(_water_input)

func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseMotion:
		pointer_target = (event.position / size * 2.0 - Vector2.ONE).clamp(-Vector2.ONE, Vector2.ONE)

func _leave() -> void:
	pointer_target = Vector2.ZERO
	for outpost: LobbyOutpost in outposts:
		outpost.set_hovered(false)

func set_interactive(value: bool) -> void:
	interactive = value
	viewport.gui_disable_input = not value
	viewport.physics_object_picking = value
	viewport.process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE if value else SubViewport.UPDATE_DISABLED
	for outpost: LobbyOutpost in outposts:
		outpost.set_interactive(value)
	if not value:
		_leave()
	set_process(value)

func _hover_changed(outpost: LobbyOutpost, value: bool) -> void:
	if value:
		hover_owner = outpost
	elif hover_owner == outpost:
		hover_owner = null
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hover_owner != null else Control.CURSOR_ARROW

func _touched(outpost: LobbyOutpost) -> void:
	get_node("/root/Session/UIFeedback").play(&"select")
	_ripple(Vector2(outpost.position.x, outpost.position.z))

func _water_input(_camera: Node, event: InputEvent, at: Vector3, _normal: Vector3, _shape: int) -> void:
	if interactive and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_ripple(Vector2(at.x, at.z))

func _ripple(at: Vector2) -> void:
	ripple_age = 0.0
	water_material.set_shader_parameter("ripple_at", at)

func _process(delta: float) -> void:
	clock += delta
	ripple_age += delta
	ferry.progress += delta * 0.9
	raft.position.y = sin(clock * 2.3) * 0.026
	raft.rotation.z = sin(clock * 1.7) * 0.045
	pointer = pointer.lerp(pointer_target, 1.0 - exp(-delta * 4.0))
	# Slow, bounded camera breathing; text and hitboxes never bob independently.
	rig.rotation = camera_rest + Vector3(pointer.y * 0.018 + sin(clock * 0.22) * 0.004, pointer.x * 0.035 + sin(clock * 0.16) * 0.009, 0)
	flag_material.set_shader_parameter("visual_time", clock)
	leaves.set_shader_parameter("flow_time", clock)
	water_material.set_shader_parameter("visual_time", clock)
	water_material.set_shader_parameter("ripple_age", ripple_age)
	water_material.set_shader_parameter("ferry_at", Vector2(ferry.position.x, ferry.position.z))
	var forward := -ferry.basis.z
	water_material.set_shader_parameter("ferry_direction", Vector2(forward.x, forward.z).normalized())
	for outpost: LobbyOutpost in outposts:
		outpost.advance(delta)
