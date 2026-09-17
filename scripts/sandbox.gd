extends "res://scripts/game.gd"
## Offline scenario authoring uses the real combat, orders, navigation and pools.
## It has its own lifecycle: no roster handshake, economy, fog or victory checks.
const UNIT_LIMIT := 500
const BUILDING_LIMIT := 64
var running: bool = false
var placing: bool = true
var paint_kind: String = "swordsman"
var paint_advanced: bool = false
var paint_count: int = 1
var paint_rotation: float = 0.0
var map_mode: String = "1v1"
var sandbox_unit_count: int = 0
var _placement_shape := CylinderShape3D.new()
var _building_placement_shape := BoxShape3D.new()
var _paint_query := PhysicsShapeQueryParameters3D.new()
var _ghost: UnitVisual
var _ghost_check: float = 0.0
var _busy: bool = true
@onready var hero_controller: SandboxHeroController = $HeroController

func _ready() -> void:
	get_tree().auto_accept_quit = false
	assert(not Session.online, "Sandbox is offline only")
	players.clear()
	for owner: int in FactionPalette.SANDBOX_COLORS.size():
		var player := PlayerState.new(owner, owner)
		player.display_name = "%02d · %s" % [owner + 1, FactionPalette.SANDBOX_NAMES[owner]]
		player.controller = "human"
		player.gold = 0
		players.append(player)
	command_bus = MatchCommands.new(self)
	map_mode = Session.config.get("mode", "1v1")
	map_definition = load(NetworkProtocol.map_path(map_mode))
	map_size = map_definition.size
	map_instance = map_definition.scene.instantiate()
	$MapContainer.add_child(map_instance)
	$ConstructionNavigation.refresh()
	$StaticMotionGrid.configure(map_instance, $Buildings, Rect2(-map_size * 0.5, map_size))
	_placement_shape.height = 2.0
	_paint_query.shape = _placement_shape
	_paint_query.collision_mask = 2 | 4 | 128
	_paint_query.margin = 0.03
	hud.bind_game(self)
	hero_controller.bind(self)
	settings.pause_requested.connect(_settings_pause_action)
	camera_rig.focus_at(Vector3.ZERO, true)
	set_paint_kind("swordsman")
	set_running(false)
	game_started = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	_busy = false
	_match_ready = true
	hud.refresh()

func presentation_faction(owner: int, _alliance: int) -> int:
	return FactionPalette.SANDBOX_OFFSET + owner

func command_unit_limit(_owner: int) -> int:
	return UNIT_LIMIT

func spawn_unit(kind: String, faction: int, at: Vector3, id: int = 0) -> Node3D:
	var unit: BattleUnit = super.spawn_unit(kind, faction, at, id)
	# Paused troops remain obstacles and mouse-pick targets. Native REMOVE mode
	# would remove disabled bodies from the physics space and allow overlap.
	unit.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	return unit

func spawn_building(kind: String, owner: int, at: Vector3, construction: bool = false, id: int = 0) -> BattleBuilding:
	var building: BattleBuilding = super.spawn_building(kind, owner, at, construction, id)
	building.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	return building

func spawn_variant(kind: String, faction: int, at: Vector3) -> BattleUnit:
	assert(UnitVariantCatalog.ADVANCED.has(kind))
	var variant: UnitVariantDefinition = UnitVariantCatalog.ADVANCED[kind]
	var unit: BattleUnit = UNIT_SCENE.instantiate()
	unit.unit_type = kind
	unit.definition_override = variant.definition()
	unit.model_scene_override = variant.batched_model if unit_batches_enabled else variant.model
	unit.prune_stationary_avoidance = stationary_avoidance_pruning_enabled
	unit.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	if unit_batches_enabled: unit.render_batches = $VariantRenderBatches
	return attach_unit(unit, faction, at)

func register_entity(entity: Node3D) -> void:
	super.register_entity(entity)
	if entity is BattleUnit:
		sandbox_unit_count += 1

func on_entity_died(entity: Node3D) -> void:
	if entity is BattleUnit:
		sandbox_unit_count -= 1
	super.on_entity_died(entity)

func can_see_entity(_owner: int, entity: Node3D) -> bool:
	return is_instance_valid(entity) and entity.alive

func can_see_position(_owner: int, _at: Vector3) -> bool:
	return true

func _physics_process(delta: float) -> void:
	if _busy or finished:
		return
	command_bus.tick()
	if running:
		simulation_tick += 1
		elapsed += delta

func _process(delta: float) -> void:
	_ui_accumulator += delta
	if _ui_accumulator >= 0.2:
		_ui_accumulator = 0.0
		_prune_selection()
		hud.refresh()
	if dragging:
		overlay.box_end = get_viewport().get_mouse_position()
		overlay.box_visible = overlay.box_start.distance_to(overlay.box_end) > 6.0
	var show_ghost: bool = placing and not _busy and not settings.is_open() and get_viewport().gui_get_hovered_control() == null
	$PlacementPreview.visible = show_ghost and not painting_building()
	$BuildingPreview.visible = show_ghost and painting_building()
	if show_ghost:
		var at: Vector3 = camera_rig.world_at(get_viewport().get_mouse_position())
		$PlacementPreview.position = at
		$PlacementPreview.rotation.y = paint_rotation
		$BuildingPreview.position = snap_build_position(at)
		$BuildingPreview.rotation.y = paint_rotation
		_ghost_check -= delta
		if _ghost_check <= 0.0:
			_ghost_check = 0.10
			var valid: bool = placement_valid(at, paint_kind)
			if painting_building():
				$BuildingPreview.set_valid(valid)
			else:
				_ghost.set_team(presentation_faction(local_owner_id, local_owner_id) if valid else FactionPalette.ENEMY)

func set_running(value: bool) -> void:
	running = value
	var mode: ProcessMode = Node.PROCESS_MODE_INHERIT if running else Node.PROCESS_MODE_DISABLED
	$Units.process_mode = mode
	$Buildings.process_mode = mode
	$ProjectilePool.process_mode = mode
	$EffectPool.process_mode = mode
	# Keep physics-space queries and the camera alive while troops are paused.
	hud.refresh()

func handle_pause_action() -> void:
	if not _busy:
		set_running(not running)

func _settings_pause_action() -> void:
	if hero_controller.has_hero(): hero_controller.toggle_view()
	else: handle_pause_action()

func set_placing(value: bool) -> void:
	placing = value
	if value:
		set_attack_mode(false)
	dragging = false
	overlay.box_visible = false
	hud.refresh()

func set_paint_kind(kind: String) -> void:
	paint_kind = kind
	if not UnitVariantCatalog.ADVANCED.has(kind): paint_advanced = false
	for model: UnitVisual in $PlacementPreview/Models.get_children():
		model.visible = model.kind == kind and (model.grade == &"advanced") == paint_advanced
		if model.visible:
			_ghost = model
			model.set_team(presentation_faction(local_owner_id, local_owner_id))
	if painting_building():
		$BuildingPreview.configure(kind, BalanceCatalog.building(kind).size)
	set_placing(true)
	_ghost_check = 0.0

func set_paint_advanced(value: bool) -> void:
	assert(not value or UnitVariantCatalog.ADVANCED.has(paint_kind))
	paint_advanced = value
	set_paint_kind(paint_kind)

func set_faction(owner: int) -> void:
	select_entities([])
	set_attack_mode(false)
	dragging = false
	overlay.box_visible = false
	local_owner_id = owner
	control_groups.clear()
	_last_group = -1
	_ghost.set_team(presentation_faction(owner, owner))
	_ghost_check = 0.0
	hud.refresh()

func placement_valid(at: Vector3, kind: String) -> bool:
	if BalanceCatalog.BUILDINGS.has(kind):
		return building_placement_valid(snap_build_position(at), kind)
	return placement_valid_for_definition(at,BalanceCatalog.unit(kind))

func painting_building() -> bool:
	return BalanceCatalog.BUILDINGS.has(paint_kind)

func building_placement_valid(at: Vector3, kind: String) -> bool:
	if not at.is_finite() or $Buildings.get_child_count() >= BUILDING_LIMIT:
		return false
	var definition: BuildingDefinition = BalanceCatalog.building(kind)
	var basis := Basis(Vector3.UP, paint_rotation)
	var extent: Vector3 = (basis * definition.size).abs() * .5
	if absf(at.x) + extent.x > map_size.x * .5 - 2 or absf(at.z) + extent.z > map_size.y * .5 - 2:
		return false
	for corner: Vector3 in [Vector3(-extent.x, 0, -extent.z), Vector3(extent.x, 0, -extent.z), Vector3(-extent.x, 0, extent.z), Vector3(extent.x, 0, extent.z), Vector3.ZERO]:
		if not $ConstructionNavigation.contains_walkable_point(at + corner): return false
	# Reserve footprints immediately, before physics publishes a same-frame spawn.
	for existing: BattleBuilding in $Buildings.get_children():
		if not existing.alive: continue
		var other: Vector3 = existing.get_footprint_size() * .5
		var separation: Vector3 = (existing.position - at).abs()
		if separation.x < extent.x + other.x and separation.z < extent.z + other.z: return false
	_building_placement_shape.size = definition.size - Vector3(.01, 0, .01)
	_paint_query.shape = _building_placement_shape
	_paint_query.transform = Transform3D(basis, at + Vector3.UP * definition.size.y * .5)
	return get_world_3d().direct_space_state.intersect_shape(_paint_query, 1).is_empty()

func placement_valid_for_definition(at: Vector3, definition: UnitDefinition) -> bool:
	if not at.is_finite() or at.distance_squared_to(clamp_to_map(at)) > 0.001:
		return false
	if not $ConstructionNavigation.contains_walkable_point(at):
		return false
	_placement_shape.radius = definition.radius + 0.06
	_paint_query.shape = _placement_shape
	_paint_query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP)
	return get_world_3d().direct_space_state.intersect_shape(_paint_query, 1).is_empty()

func place_units(at: Vector3) -> int:
	if _busy or finished:
		return 0
	if painting_building():
		var point: Vector3 = snap_build_position(at)
		if not building_placement_valid(point, paint_kind):
			hud.toast("这里无法放置建筑，或已达到64座上限", 2.5)
			return 0
		var building: BattleBuilding = spawn_building(paint_kind, local_owner_id, point)
		building.rotation.y = paint_rotation
		building.reset_physics_interpolation()
		$ConstructionNavigation.refresh()
		hud.toast("已放置%s · %s" % [building.display_name, players[local_owner_id].display_name], 2.5)
		hud.refresh()
		return 1
	var available: int = UNIT_LIMIT - sandbox_unit_count
	if available <= 0:
		hud.toast("沙盘最多同时放置 500 个单位", 3.0)
		return 0
	var amount: int = mini(paint_count, available)
	var columns: int = ceili(sqrt(float(amount)))
	var rows: int = ceili(float(amount) / columns)
	var spacing: float = maxf(1.65, BalanceCatalog.unit(paint_kind).radius * 2.5)
	var basis := Basis(Vector3.UP, paint_rotation)
	var placed: int = 0
	for index: int in amount:
		var offset := Vector3((index % columns - (columns - 1) * 0.5) * spacing, 0, (floori(float(index) / columns) - (rows - 1) * 0.5) * spacing)
		var point: Vector3 = at + basis * offset
		if not placement_valid(point, paint_kind):
			continue
		var unit: BattleUnit = spawn_variant(paint_kind, local_owner_id, point) if paint_advanced else spawn_unit(paint_kind, local_owner_id, point)
		unit.model_pivot.rotation.y = paint_rotation
		unit.reset_physics_interpolation()
		placed += 1
	var unit_name: String = UnitVariantCatalog.ADVANCED[paint_kind].display_name if paint_advanced else UNIT_NAMES[paint_kind]
	hud.toast("已放置 %d 名%s · %s" % [placed, unit_name, players[local_owner_id].display_name] if placed > 0 else "这里被占用，或无法通行", 2.5)
	hud.refresh()
	return placed

func remove_selected() -> void:
	for entity: Node3D in selection.duplicate():
		if entity is BattleBuilding:
			_remove_building(entity)
			continue
		if not entity is BattleUnit:
			continue
		if entity == hero_controller.hero:
			hero_controller.set_first_person(false)
		forget_entity_selection(entity)
		entities_by_id.erase(entity.entity_id)
		sandbox_unit_count -= 1
		var player: PlayerState = get_player(entity.owner_id)
		if entity._stats.is_construction():
			player.farmers -= 1
		else:
			player.military_supply -= entity.get_combat_definition().supply
		entity.stop()
		entity.navigation_agent.avoidance_enabled = false
		entity.set_physics_process(false)
		entity.queue_free()
	$ConstructionNavigation.refresh()
	$StaticMotionGrid.invalidate()
	hud.refresh()

func _remove_building(building: BattleBuilding) -> void:
	forget_entity_selection(building)
	entities_by_id.erase(building.entity_id)
	building.alive = false
	building.collision_layer = 0
	building.remove_from_group("buildings")
	building.remove_from_group("entities")
	building.set_physics_process(false)
	building.queue_free()

func clear_units() -> void:
	hero_controller.set_first_person(false)
	select_entities([])
	command_bus.pending.clear()
	control_groups.clear()
	_last_click_entity = null
	$ProjectilePool.reset_all()
	$EffectPool.reset_all()
	for unit: BattleUnit in $Units.get_children():
		entities_by_id.erase(unit.entity_id)
		unit.stop()
		unit.navigation_agent.avoidance_enabled = false
		unit.set_physics_process(false)
		unit.queue_free()
	sandbox_unit_count = 0
	for building: BattleBuilding in $Buildings.get_children():
		_remove_building(building)
	$ConstructionNavigation.refresh()
	$StaticMotionGrid.invalidate()
	for player: PlayerState in players:
		player.farmers = 0
		player.military_supply = 0
		player.kills = 0
	elapsed = 0.0
	hud.refresh()

func switch_map(mode: String) -> void:
	if _busy or mode == map_mode:
		return
	_busy = true
	hud.refresh()
	await prepare_shutdown()
	Session.start_sandbox(mode)

func return_to_menu() -> void:
	if _closing:
		return
	_closing = true
	_busy = true
	await prepare_shutdown()
	Session.back_to_lobby()

func _input(event: InputEvent) -> void:
	if hero_controller.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if hero_controller.blocks_rts(): return
	if settings.is_open() or _busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = settings.resolve_key(event)
		if key == KEY_F5:
			handle_pause_action()
			get_viewport().set_input_as_handled()
		elif key == KEY_ESCAPE:
			set_placing(false)
			set_attack_mode(false)
			get_viewport().set_input_as_handled()
		elif key == KEY_F11:
			settings.toggle_fullscreen()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		camera_rig.dragging = event.pressed
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and camera_rig.dragging:
		camera_rig.drag_by(event.relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		dragging = false
		overlay.box_visible = false
		_finish_selection(event.position)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if hero_controller.blocks_rts(): return
	if _busy or settings.is_open():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: camera_rig.zoom_by(-3)
			MOUSE_BUTTON_WHEEL_DOWN: camera_rig.zoom_by(3)
			MOUSE_BUTTON_LEFT:
				if placing:
					place_units(camera_rig.world_at(event.position))
				elif attack_mode:
					var target := entity_at(event.position)
					if is_instance_valid(target) and target.alliance_id != local_owner_id:
						command_attack(target, event.shift_pressed)
					else:
						command_move(camera_rig.world_at(event.position), true, event.shift_pressed)
					set_attack_mode(false)
				else:
					dragging = true
					drag_start = event.position
					shift_drag = event.shift_pressed
					ctrl_drag = event.ctrl_pressed
					overlay.box_start = drag_start
					overlay.box_end = drag_start
			MOUSE_BUTTON_RIGHT:
				if placing:
					set_placing(false)
				else:
					var target := entity_at(event.position)
					if is_instance_valid(target) and target is ResourceVein:
						command_gather(target, event.shift_pressed)
					elif is_instance_valid(target) and (target is BattleUnit or target is BattleBuilding) and target.owner_id != local_owner_id:
						command_attack(target, event.shift_pressed)
					else:
						command_move(camera_rig.world_at(event.position), attack_mode, event.shift_pressed)
					set_attack_mode(false)
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = settings.resolve_key(event)
		if not placing and key in [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y]:
			if hud.trigger_action_slot([KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y].find(key)):
				get_viewport().set_input_as_handled()
				return
		if key >= KEY_1 and key <= KEY_9:
			use_control_group(key - KEY_0, event.ctrl_pressed, event.shift_pressed)
			return
		match key:
			KEY_TAB: hud.cycle_selection_group(event.shift_pressed)
			KEY_F2, KEY_G: select_army()
			KEY_SPACE: focus_selection()
			KEY_DELETE: remove_selected()
			KEY_A:
				set_placing(false)
				set_attack_mode(true)
			KEY_S: stop_selected()
			KEY_H: hold_selected(event.shift_pressed)
			KEY_R: rotate_placement()
			KEY_Q: set_paint_kind("swordsman")
			KEY_W: set_paint_kind("archer")
			KEY_E: set_paint_kind("knight")

func rotate_placement() -> void:
	paint_rotation = wrapf(paint_rotation + PI * 0.5, 0.0, TAU)
	hud.refresh()

func prepare_shutdown() -> void:
	hero_controller.shutdown()
	await super.prepare_shutdown()
