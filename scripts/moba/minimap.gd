extends Control
var game: Node3D
const TEAMS := [Color("65c5dd"), Color("ea787e")]

func _point(at: Vector3) -> Vector2:
	return (Vector2(at.x, at.z) / game.map_size + Vector2(.5, .5)) * size

func _draw() -> void:
	if game == null: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("68856b"))
	var route := PackedVector2Array()
	for side: int in [-1, 1]:
		route.clear()
		for at: Vector3 in [Vector3(-94,0,0), Vector3(-74,0,side*10), Vector3(-34,0,side*10), Vector3(0,0,side*3), Vector3(34,0,side*10), Vector3(74,0,side*10), Vector3(94,0,0)]: route.append(_point(at))
		draw_polyline(route, Color("c6b482"), 3.0, true)
	for entity: Node3D in game.entities_by_id.values():
		if not entity.alive: continue
		var at := _point(entity.position)
		var color: Color = TEAMS[entity.owner_id]
		if entity is BattleBuilding:
			var footprint: Vector3 = entity.get_footprint_size()
			var extent: Vector2 = Vector2(footprint.x, footprint.z) / game.map_size * size
			draw_rect(Rect2(at - extent * .5, extent), color)
		elif entity is HeroUnit:
			draw_circle(at, 4.0, Color.WHITE)
			draw_circle(at, 2.5, color)
		else: draw_circle(at, 1.3, color)
	if not game.hero_controller.first_person:
		var polygon := PackedVector2Array()
		var viewport_size: Vector2 = get_viewport_rect().size
		for corner: Vector2 in [Vector2.ZERO, Vector2(viewport_size.x,0), viewport_size, Vector2(0,viewport_size.y), Vector2.ZERO]:
			polygon.append(_point(game.camera_rig.world_at(corner)))
		draw_polyline(polygon, Color(1,1,1,.85), 1.0, true)
	elif game.local_hero() != null:
		var at: Vector2 = _point(game.local_hero().position)
		var direction: Vector3 = -game.hero_controller.camera.global_basis.z
		draw_line(at, at + Vector2(direction.x, direction.z) * 9, Color.WHITE, 1.5, true)

func _gui_input(event: InputEvent) -> void:
	if game == null or not game.running or game.hero_controller.captured: return
	if event is InputEventMouseButton and event.pressed:
		var world: Vector2 = (event.position / size - Vector2(.5,.5)) * game.map_size
		var at: Vector3 = game.clamp_to_map(Vector3(world.x,0,world.y))
		if event.button_index == MOUSE_BUTTON_LEFT and not game.hero_controller.first_person:
			game.hero_controller.set_follow(false)
			game.camera_rig.focus_at(at)
		elif event.button_index == MOUSE_BUTTON_RIGHT and game.local_hero() != null:
			game.select_entities([game.local_hero()])
			game.command_move(at, false, event.shift_pressed)
		accept_event()
