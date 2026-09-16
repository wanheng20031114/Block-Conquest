class_name SandboxHeroController
extends Node3D
const HERO_SCENE := preload("res://scenes/hero/hero_unit.tscn")
const HERO_DEFINITION := preload("res://data/sandbox/heroes/capsule.tres")
var game: Node3D
var hero: HeroUnit
var first_person: bool = false
var profile := HeroProfile.defaults()
var yaw: float = 0.0
var pitch: float = 0.0
var _ui_elapsed: float = 0.0
var _menu_was_running: bool = false
var _menu_active: bool = false
var _look_captured: bool = false
var _pending_jump: bool = false
var _shot_feedback: float = 0.0
@onready var camera: Camera3D = $View/Pitch/Camera3D
@onready var interface: CanvasLayer = $Interface

func bind(controller: Node3D) -> void:
	game = controller
	for action: String in ["hero_left","hero_right","hero_forward","hero_back"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = {"hero_left":KEY_A,"hero_right":KEY_D,"hero_forward":KEY_W,"hero_back":KEY_S}[action]
			InputMap.action_add_event(action,key)
	profile = HeroProfile.read_profile()
	interface.bind(self)
	game.settings.opened.connect(_settings_opened)
	game.settings.closed.connect(_settings_closed)
	game.settings.changed.connect(_apply_view_settings)
	_apply_view_settings()

func has_hero() -> bool:
	return is_instance_valid(hero) and hero.alive

func blocks_rts() -> bool:
	return first_person or _menu_active

func create_or_update(values: Dictionary, persist: bool = true) -> bool:
	profile = HeroProfile.sanitize(values)
	if not has_hero():
		if game.sandbox_unit_count >= game.UNIT_LIMIT:
			interface.notice("沙盘已达单位上限")
			return false
		var spawn_at := _find_spawn()
		if not spawn_at.is_finite():
			interface.notice("当前镜头附近没有可站立的位置，请移动镜头后再创建")
			return false
		hero = HERO_SCENE.instantiate()
		hero.owner_id = profile.faction
		hero.alliance_id = profile.faction
		hero.position = spawn_at
		hero.sound_requested.connect(game.play_world_sound)
		game.unit_container.add_child(hero)
		hero.inventory.changed.connect(interface.refresh)
		hero.died.connect(_hero_died)
		hero.tree_exiting.connect(_hero_removed.bind(hero))
		hero.shot_resolved.connect(_on_shot)
	elif hero.owner_id != profile.faction:
		hero.stop()
		game.get_player(hero.owner_id).military_supply -= hero._stats.supply
		hero.owner_id = profile.faction
		hero.alliance_id = profile.faction
		hero._owner_state = game.get_player(profile.faction)
		hero._owner_state.military_supply += hero._stats.supply
		hero.collision_layer = 4 | CombatLayers.UNIT_LAYERS[profile.faction]
		hero._target_query.collision_mask = CombatLayers.hostile_entities(profile.faction)
		hero._rts_visible_target = null
	hero.display_name = profile.name
	hero._model.set_team(FactionPalette.SANDBOX_OFFSET+profile.faction)
	(hero._model as HeroVisual).apply_appearance(profile)
	if persist and HeroProfile.save_profile(profile) != OK: interface.notice("形象已应用，本地保存失败")
	if game.local_owner_id!=profile.faction: game.set_faction(profile.faction)
	game.set_placing(false)
	game.select_entities([hero])
	game.camera_rig.focus_at(hero.global_position)
	interface.refresh()
	return true

func _find_spawn() -> Vector3:
	var center: Vector3 = game.clamp_to_map(game.camera_rig.position)
	for ring: int in 8:
		for point: int in maxi(1,ring*8):
			var angle: float = TAU*point/maxi(1,ring*8)
			var at := center+Vector3(cos(angle),0,sin(angle))*ring*1.3
			if game.placement_valid_for_definition(at,HERO_DEFINITION): return at
	return Vector3.INF

func toggle_view() -> void:
	if not has_hero() or _menu_active or game.settings.is_open(): return
	set_first_person(not first_person)

func set_first_person(value: bool) -> void:
	if value and not has_hero(): return
	if value == first_person: return
	first_person = value
	game.set_placing(false)
	game.dragging = false
	game.camera_rig.dragging = false
	game.overlay.box_visible = false
	game.hud.visible = not value
	game.get_node("ContextCursor").set_process(not value)
	game.get_node("ContextCursor").set_cursor("normal")
	game.get_node("OrderPlanOverlay").set_process(not value)
	game.camera_rig.set_process(not value)
	if has_hero(): hero.set_direct_control(value)
	if value:
		yaw = hero.model_pivot.rotation.y
		pitch = 0.0
		_update_camera(0)
		camera.make_current()
		$View/Pitch/Camera3D/Listener.make_current()
		_capture(true)
	else:
		_capture(false)
		game.camera.make_current()
		game.camera_rig.get_node("AudioListener3D").make_current()
		if has_hero():
			game.camera_rig.focus_at(hero.global_position,true)
			if game.local_owner_id!=hero.owner_id: game.set_faction(hero.owner_id)
			game.select_entities([hero])
	interface.set_first_person(value)
	game.hud.refresh()

func handle_input(event: InputEvent) -> bool:
	if game == null or game._busy: return false
	if _menu_active:
		var modal_key: int = (event.physical_keycode if event.physical_keycode!=0 else event.keycode) if event is InputEventKey else 0
		if event is InputEventKey and event.pressed and not event.echo and modal_key == KEY_ESCAPE:
			interface.close_panels()
			return true
		if event is InputEventKey and event.pressed and not event.echo and modal_key==KEY_I and interface.get_node("%Inventory").visible:
			interface.close_panels()
			return true
		return false
	if game.settings.is_open(): return false
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if event.pressed and not event.echo:
			if key==KEY_I and has_hero():
				interface.open_inventory()
				return true
			if key>=KEY_1 and key<=KEY_5 and has_hero() and (first_person or event.alt_pressed):
				interface.use_shortcut(key-KEY_1)
				return true
			if key == KEY_F5 and has_hero():
				toggle_view()
				return true
			if first_person:
				match key:
					KEY_ESCAPE: interface.open_pause()
					KEY_SPACE: _pending_jump = true
					KEY_R:
						if game.running: hero.weapon.begin_reload()
					KEY_F11: game.settings.toggle_fullscreen()
				return true
		return first_person
	if first_person:
		if event is InputEventMouseMotion and _look_captured:
			yaw -= event.screen_relative.x*.002*game.settings.fp_sensitivity
			pitch = clampf(pitch-event.screen_relative.y*.002*game.settings.fp_sensitivity*(-1 if game.settings.fp_invert_y else 1),deg_to_rad(-80),deg_to_rad(80))
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if _look_captured: hero.trigger_held = event.pressed
			elif event.pressed: _capture(true)
		return true
	return false

func _physics_process(_delta: float) -> void:
	if not first_person or not has_hero(): return
	if not game.running or _menu_active or game.settings.is_open() or not _look_captured:
		hero.move_input = Vector3.ZERO
		hero.trigger_held = false
		_pending_jump = false
		return
	var axis := Input.get_vector("hero_left","hero_right","hero_forward","hero_back")
	hero.move_input = Basis(Vector3.UP,yaw)*Vector3(axis.x,0,axis.y)
	hero.aim_direction = Basis(Vector3.UP,yaw)*Basis(Vector3.RIGHT,pitch)*Vector3.FORWARD
	if _pending_jump: hero.jump()
	_pending_jump = false

func _process(delta: float) -> void:
	if game == null: return
	if first_person and has_hero(): _update_camera(delta)
	_shot_feedback = maxf(0.0,_shot_feedback-delta)
	interface.set_hit_feedback(_shot_feedback>0.0)
	_ui_elapsed += delta
	if _ui_elapsed >= .10:
		_ui_elapsed = 0.0
		interface.refresh()

func _update_camera(_delta: float) -> void:
	var body_transform := hero.get_global_transform_interpolated()
	var jumping := lerpf(hero.previous_jump_offset,hero.jump_offset,Engine.get_physics_interpolation_fraction())
	var bob: float = sin(game.elapsed*12.0)*.025 if game.settings.fp_head_bob and hero._observed_velocity.length_squared()>.1 else 0.0
	$View.global_position = body_transform.origin+Vector3.UP*(HeroUnit.EYE_HEIGHT+jumping+bob)
	$View.rotation.y = yaw
	$View/Pitch.rotation.x = pitch
	_apply_view_settings()
	interface.update_weapon_pose(hero.weapon)

func _apply_view_settings() -> void:
	if game == null: return
	var aspect := get_viewport().get_visible_rect().size.aspect()
	camera.fov = rad_to_deg(2.0*atan(tan(deg_to_rad(game.settings.fp_fov)*.5)/aspect))

func begin_panel() -> void:
	if _menu_active: return
	_menu_active = true
	_menu_was_running = game.running
	game.set_running(false)
	game.set_placing(false)
	game.hud.hide()
	interface.refresh()
	_capture(false)
	if has_hero(): hero.trigger_held = false

func end_panel() -> void:
	if not _menu_active: return
	_menu_active = false
	game.set_running(_menu_was_running)
	game.hud.visible = not first_person
	interface.refresh()
	if first_person and has_hero(): _capture(true)

func _capture(value: bool) -> void:
	_look_captured = value
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE

func _settings_opened() -> void:
	if first_person:
		begin_panel()
		interface.hide_pause()

func _settings_closed() -> void:
	if first_person: end_panel()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and first_person:
		_capture(false)
		if has_hero():
			hero.trigger_held = false
			hero.move_input = Vector3.ZERO

func _hero_died(_unit: Node3D) -> void:
	set_first_person(false)
	interface.notice("英雄已阵亡，可在「我的英雄」中重新创建")

func _hero_removed(unit: HeroUnit) -> void:
	if unit != hero: return
	set_first_person(false)
	hero = null

func _on_shot(hit: Dictionary) -> void:
	if hit.enemy_hit: _shot_feedback = .16

func shutdown() -> void:
	set_first_person(false)
	_capture(false)

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
