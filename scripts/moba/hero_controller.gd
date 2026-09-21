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
var follow_hero: bool = true
var top_down_firing: bool = false
var top_down_direct: bool = false
var focused: bool = true
var attack_target: Node3D
var _auto_target_in: float = 0.0
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
	attack_target = null
	top_down_direct = false
	hero.shot_resolved.connect(func(hit: Dictionary):
		if hit.enemy_hit: hit_flash = .16)

func release_hero() -> void:
	stop_input()
	attack_target = null
	set_first_person(false)
	hero = null

func toggle_view() -> void:
	if game.running and is_instance_valid(hero) and hero.alive: set_first_person(not first_person)

func set_first_person(value: bool) -> void:
	if value == first_person: return
	if value and (not is_instance_valid(hero) or not hero.alive): return
	first_person = value
	top_down_firing = false
	top_down_direct = false
	attack_target = null
	pending_jump = false
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
	pending_jump = false
	top_down_firing = false
	if top_down_direct:
		hero.set_direct_control(false)
		top_down_direct = false

func prepare_order(command: Dictionary) -> void:
	if first_person or bool(command.get("queued", false)): return
	attack_target = game.entities_by_id.get(command.get("target", 0)) if command.kind == "attack" else null
	top_down_firing = false
	if top_down_direct:
		hero.set_direct_control(false)
		top_down_direct = false

func set_follow(value: bool) -> void:
	follow_hero = value
	game.camera_rig.edge_scroll = not value
	game.hud.get_node("%FocusHero").text = "跟随中" if value else "跟随 Y"

func begin_pointer_fire() -> void:
	top_down_firing = true

func stop_input() -> void:
	top_down_firing = false
	pending_jump = false
	if is_instance_valid(hero):
		hero.move_input = Vector3.ZERO
		hero.trigger_held = false
		if top_down_direct: hero.set_direct_control(false)
	top_down_direct = false

func handle_input(event: InputEvent) -> bool:
	if not first_person:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			top_down_firing = false
		if event is InputEventKey:
			var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			return key in [KEY_W, KEY_A, KEY_S, KEY_D]
		return false
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

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hero) or not hero.alive: return
	if not game.running or not focused or game.settings.is_open():
		stop_input()
		return
	var axis := Input.get_vector("hero_left", "hero_right", "hero_forward", "hero_back")
	if not first_person:
		_update_top_down(axis, delta)
		return
	if not captured:
		stop_input()
		return
	hero.move_input = Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	hero.aim_direction = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
	if pending_jump: hero.jump()
	pending_jump = false

func _update_top_down(axis: Vector2, delta: float) -> void:
	var manual := not axis.is_zero_approx() or top_down_firing
	if manual != top_down_direct:
		# Switching intent does not replace the body or reset its weapon cooldown.
		if manual and hero._valid_target(hero.target): attack_target = hero.target
		hero.set_direct_control(manual)
		top_down_direct = manual
		if not manual:
			# Releasing WASD stops at once; an automatic shot must not turn into
			# an unrequested chase after a retreating enemy.
			hero.hold()
			if hero._valid_target(attack_target) and hero._within_attack_range(attack_target): hero.target = attack_target
	if not manual: return
	var right: Vector3 = game.camera.global_basis.x
	var down: Vector3 = Vector3(game.camera.global_basis.z.x, 0, game.camera.global_basis.z.z).normalized()
	hero.move_input = (right * axis.x + down * axis.y).limit_length(1.0)
	hero.trigger_held = false
	if top_down_firing:
		var mouse := get_viewport().get_mouse_position()
		var hovered: Node3D = game.entity_at(mouse)
		var at: Vector3 = hero._aim_point(hovered) if hero._valid_target(hovered) else game.camera_rig.world_at(mouse) + Vector3.UP * 1.3
		hero.aim_direction = (at - hero.logic_eye()).normalized()
		hero.trigger_held = true
		return
	_auto_target_in -= delta
	if not hero._valid_target(attack_target) or not hero._within_attack_range(attack_target):
		if _auto_target_in <= 0:
			_auto_target_in = .15
			attack_target = hero._find_auto_target(true)
	if hero._valid_target(attack_target) and hero._can_start_strike(attack_target):
		hero.aim_direction = (hero._aim_point(attack_target) - hero.logic_eye()).normalized()
		hero.trigger_held = true
	elif not hero.move_input.is_zero_approx():
		hero.aim_direction = hero.move_input.normalized()

func _process(delta: float) -> void:
	if not is_instance_valid(hero): return
	if not first_person:
		if game.running and focused and (follow_hero or Input.is_physical_key_pressed(KEY_SPACE)):
			game.camera_rig.focus_at(hero.get_global_transform_interpolated().origin)
		return
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
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		stop_input()
		if first_person: capture_mouse(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: focused = true

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
