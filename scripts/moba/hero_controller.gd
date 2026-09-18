extends Node3D
## Mode-specific input; the existing HeroUnit remains the sole combat/movement body.
var game: Node3D
var hero: MobaHero
var first_person: bool = false
var captured: bool = false
var yaw: float = 0.0
var pitch: float = 0.0
var pending_jump: bool = false
var hit_flash: float = 0.0
@onready var camera: Camera3D = $View/Pitch/Camera3D

func bind(value: Node3D) -> void:
	game = value
	for action: String in ["hero_left", "hero_right", "hero_forward", "hero_back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = {"hero_left": KEY_A, "hero_right": KEY_D, "hero_forward": KEY_W, "hero_back": KEY_S}[action]
			InputMap.action_add_event(action, key)

func adopt(value: MobaHero) -> void:
	hero = value
	hero.shot_resolved.connect(func(hit: Dictionary):
		if hit.enemy_hit: hit_flash = .16)

func release_hero() -> void:
	set_first_person(false)
	hero = null

func toggle_view() -> void:
	if game.running and is_instance_valid(hero) and hero.alive: set_first_person(not first_person)

func set_first_person(value: bool) -> void:
	if value == first_person: return
	if value and (not is_instance_valid(hero) or not hero.alive): return
	first_person = value
	game.camera_rig.dragging = false
	game.camera_rig.set_process(not value)
	if is_instance_valid(hero): hero.set_direct_control(value)
	if value:
		yaw = hero.model_pivot.rotation.y
		pitch = 0
		_update_camera()
		camera.make_current()
		game.get_node("Audio").set_listener($View/Pitch/Camera3D/Listener)
	else:
		game.camera.make_current()
		game.get_node("Audio").set_listener(game.camera_rig.get_node("AudioListener3D"))
		game.focus_hero()
	capture_mouse(value)
	game.hud.set_first_person(value)

func capture_mouse(value: bool) -> void:
	captured = value and first_person
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(hero): hero.trigger_held = false; hero.move_input = Vector3.ZERO

func handle_input(event: InputEvent) -> bool:
	if not first_person: return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_TAB: capture_mouse(not captured)
		elif key == KEY_SPACE: pending_jump = true
		return true
	if event is InputEventMouseMotion and captured:
		var scale: float = GameSettings.FP_MOUSE_RADIANS_PER_COUNT * game.settings.fp_sensitivity
		yaw -= event.screen_relative.x * scale
		pitch = clampf(pitch - event.screen_relative.y * scale * (-1 if game.settings.fp_invert_y else 1), deg_to_rad(-80), deg_to_rad(80))
		return true
	if event is InputEventMouseButton and captured and event.button_index == MOUSE_BUTTON_LEFT:
		hero.trigger_held = event.pressed
		return true
	return captured

func _physics_process(_delta: float) -> void:
	if not first_person or not is_instance_valid(hero) or not hero.alive: return
	if not game.running or not captured or game.settings.is_open():
		hero.move_input = Vector3.ZERO
		hero.trigger_held = false
		pending_jump = false
		return
	var axis := Input.get_vector("hero_left", "hero_right", "hero_forward", "hero_back")
	hero.move_input = Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	hero.aim_direction = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	if pending_jump: hero.jump()
	pending_jump = false

func _process(delta: float) -> void:
	if not first_person or not is_instance_valid(hero): return
	_update_camera()
	hit_flash = maxf(0, hit_flash - delta)
	game.hud.set_hit_feedback(hit_flash > 0)
	game.hud.update_weapon(hero.weapon)

func _update_camera() -> void:
	var interpolated := hero.get_global_transform_interpolated()
	var jump := lerpf(hero.previous_jump_offset, hero.jump_offset, Engine.get_physics_interpolation_fraction())
	var bob: float = sin(game.elapsed * 12) * .025 if game.settings.fp_head_bob and hero._observed_velocity.length_squared() > .1 else 0.0
	$View.global_position = interpolated.origin + Vector3.UP * (HeroUnit.EYE_HEIGHT + jump + bob)
	$View.rotation.y = yaw
	$View/Pitch.rotation.x = pitch
	camera.fov = rad_to_deg(2 * atan(tan(deg_to_rad(game.settings.fp_fov) * .5) / get_viewport().get_visible_rect().size.aspect()))

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and first_person: capture_mouse(false)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
