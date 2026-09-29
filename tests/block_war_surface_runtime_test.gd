extends SceneTree
## Elevated runtime regression: targeting, interpolation, effects and presence.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var checks := 0
var failures: Array[String] = []
var game: Node3D

class CursorConnection extends Node:
	signal room_changed(room: Dictionary)
	signal state_changed(state: String)
	signal cursor_received(sender: int, payload: Dictionary)
	var player_id := 10
	var connection_state := "match"
	var room: Dictionary = {"slots": [
		{"slot_id": 0, "player_id": 10, "kind": "human", "team_id": 0, "faction_id": 0, "connected": true, "controller": "human", "name": "Local"},
		{"slot_id": 2, "player_id": 15, "kind": "human", "team_id": 0, "faction_id": 2, "connected": true, "controller": "human", "name": "Ally"},
	]}
	func send_cursor(_payload: Dictionary) -> void: pass

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.002, "%s: %.4f / %.4f" % [message, actual, expected])

func _march_surface() -> void:
	var definition := WarMapDefinition.new()
	var zone := WarHeightZone.new()
	zone.region = Rect2(-20, -20, 40, 40)
	zone.start_height = 0
	zone.end_height = 8
	zone.axis = 1
	definition.height_zones = [zone]
	var marches: WarMarches = load("res://scenes/block_war/marches.tscn").instantiate()
	root.add_child(marches)
	marches.map_definition = definition
	marches.send(0, 1, 0, 6, PackedVector3Array([Vector3(-12, 4, 0), Vector3(12, 4, 0)]))
	for unit: WarMarches.MarchUnit in marches._units:
		unit.distance = 12.0
		marches._update_pose(unit)
		near(unit.position.y, definition.surface_height(Vector2(unit.position.x, unit.position.z)), "lateral files follow the cross-slope surface")
	check(marches._units[0].position.y != marches._units[-1].position.y, "outer files do not inherit the route center's elevation")
	var first: WarMarches.MarchUnit = marches._units[0]
	first.levitation_remaining = RULES.FROG_DURATIONS[1] - 0.5
	marches._update_pose(first)
	var lift := first.position.y - definition.surface_height(Vector2(first.position.x, first.position.z))
	check(lift > 1.6 and lift < 1.8, "levitation remains relative to the ramp")
	first.presentation_offset = Vector3(1.0, -5.0, 2.0)
	marches._render()
	var drawn := marches._presentation_position(first)
	near(drawn.y, definition.surface_height(Vector2(drawn.x, drawn.z)) + lift + 0.035, "network smoothing preserves lift while resampling the shifted surface")
	if DisplayServer.get_name() != "headless":
		check(marches._multimesh.get_instance_transform(0).origin.distance_to(drawn) < 0.002, "native militia receives the surface-adjusted presentation position")
	first.cloaked = true
	marches._render()
	drawn = marches._presentation_position(first)
	near(drawn.y, definition.surface_height(Vector2(drawn.x, drawn.z)) + lift + 0.035, "cloaked presentation follows the same elevated surface")
	if DisplayServer.get_name() != "headless":
		check(marches._cloaked_mesh.get_instance_transform(0).origin.distance_to(drawn) < 0.002, "native cloaked militia receives the same surface-adjusted position")
	var mote := WarSurfaceEffects.offset_point(definition, first.position, Vector3(0, 0.2, 2.0))
	near(mote.y, definition.surface_height(Vector2(mote.x, mote.z)) + lift + 0.2, "offset effects retain intended clearance and existing levitation")
	for mesh: MultiMesh in [marches._multimesh, marches._cloaked_mesh]:
		check(mesh.custom_aabb.has_point(Vector3(78, 18, 60)) and mesh.custom_aabb.has_point(Vector3(-78, 0, -60)), "march culling contains the widest map and high floating units")
	marches.clear()
	marches.send(0, 1, 1, 1, PackedVector3Array([Vector3(10.8, 4, 0), Vector3(10.8, 4.8, 4)]))
	first = marches._units[0]
	first.distance = 0.1
	marches._update_pose(first)
	check(marches.acquire_targets(Vector3(0, 12, 0), 0, 11, 1, false, true).size() == 1, "an elevated tower retains its full horizontal radius")
	first.reserved = false
	first.position = Vector3(11.05, 0, 0)
	check(marches.acquire_targets(Vector3(0, 8, 0), 0, 11, 1, false, true).is_empty(), "height support does not extend the horizontal tower radius")
	marches.free()

func _materials() -> void:
	var effects: Node3D = game.world_effects
	var definition: WarMapDefinition = game.map.definition
	var materials: Array[ShaderMaterial] = [
		effects.get_node("RecruitRings").multimesh.mesh.material,
		effects.get_node("HasteFields").multimesh.mesh.material,
		effects.get_node("Rabbit/RushBursts").multimesh.mesh.material,
		effects.get_node("Bear/Ground").multimesh.mesh.material,
		effects.get_node("Frog/Mist").multimesh.mesh.material,
	]
	for rally: Node3D in effects.get_node("Rabbit/Rallies").get_children():
		materials.append(rally.get_node("Waves").material_override)
		check(rally.get_node("Waves").extra_cull_margin >= 8.0, "recall wave bounds contain displacement across a full-height cliff")
	for fire: WarFireWave in effects.get_node("FireWaves").get_children():
		materials.append(fire.get_node("Ground").material_override)
		for path: String in ["Flames", "Sparks", "Smoke"]:
			materials.append(fire.get_node(path).draw_pass_1.material)
	for material: ShaderMaterial in materials:
		check(int(material.get_shader_parameter("terrain_zone_count")) == definition.height_zones.size(), "all authored ground and fire materials receive the match's zone count")
		var regions: PackedVector4Array = material.get_shader_parameter("terrain_regions")
		var profiles: PackedVector3Array = material.get_shader_parameter("terrain_profiles")
		check(regions.size() == WarSurfaceEffects.MAX_ZONES and profiles.size() == WarSurfaceEffects.MAX_ZONES, "complete native uniform arrays reach every effect instance")
	var tower: WarBuilding = game.buildings[0]
	tower.kind = 1
	for tier: int in [1, 2, 3]:
		tower.level = tier
		tower.refresh_visual()
		var decal: Decal = tower.get_node("AttackRange")
		check(decal.size.y >= 16 and decal.cull_mask == 524288, "tower upgrades preserve projection height and the exclusive terrain receiver layer")

func _scene_material_isolation() -> void:
	var scene: PackedScene = load("res://scenes/block_war/war_effects.tscn")
	var elevated: Node3D = scene.instantiate()
	var flat: Node3D = scene.instantiate()
	var definition: WarMapDefinition = load("res://data/block_war/maps/switchback.tres")
	elevated.configure_surface(definition)
	flat.configure_surface(load("res://data/block_war/maps/rift.tres"))
	for path: String in ["RecruitRings", "HasteFields", "Rabbit/RushBursts", "Bear/Ground", "Frog/Mist"]:
		var high_material: ShaderMaterial = elevated.get_node(path).multimesh.mesh.material
		var flat_material: ShaderMaterial = flat.get_node(path).multimesh.mesh.material
		check(high_material != flat_material, "separate battle scenes own their nested ground material: " + path)
		check(int(high_material.get_shader_parameter("terrain_zone_count")) == definition.height_zones.size() and int(flat_material.get_shader_parameter("terrain_zone_count")) == 0, "configuring a flat battle cannot erase an elevated battle's zones: " + path)
	elevated.free()
	flat.free()

func _ground_commands() -> void:
	var top := Vector3(0, 8, 0)
	game.camera_rig.focus_at(top, true)
	var screen: Vector2 = game.camera.unproject_position(top)
	var picked: Vector3 = game.skill_ground_at(screen)
	check(picked.is_finite() and picked.distance_to(top) < 0.02, "the visible summit is the skill target under the pointer")
	game.faction_skills[0].commander = &"squirrel"
	game.faction_skills[0].energy = 100.0
	game.faction_skills[0].cooldowns.fill(0.0)
	var result: Dictionary = game.execute_network_command(0, {"type": "skill_ground", "skill": 3, "x": 0.0, "z": 0.0})
	check(result.accepted, "an XZ-only ground command is accepted on a high plateau")
	check(game.fire_states.size() == 1, "the command creates exactly one authoritative fire")
	if not game.fire_states.is_empty():
		near(game.fire_states[0].global_position.y, 8.0, "network commands reconstruct height from the selected map")
	var waves: Node3D = game.world_effects.get_node("FireWaves")
	var first: WarFireWave = waves.get_child(0)
	game.start_fire(Vector3(20, 0, 0), 4.5, 0)
	game.world_effects.sync_fire_states(game.fire_states)
	var second: WarFireWave = waves.get_child(1)
	near(first.get_node("Flames").draw_pass_1.material.get_shader_parameter("emitter_surface_height"), 8.0, "starting a low fire does not overwrite a high fire's material")
	near(second.get_node("Flames").draw_pass_1.material.get_shader_parameter("emitter_surface_height"), 0.0, "each fire owns its source height")
	for path: String in ["Flames", "Sparks", "Smoke"]:
		check(first.get_node(path).draw_pass_1.material != second.get_node(path).draw_pass_1.material, "scene-local fire materials stay independent: " + path)
		near(first.get_node(path).draw_pass_1.material.get_shader_parameter("emitter_surface_height"), 8.0, "all high fire layers retain their own source height: " + path)
	var rabbit: Node3D = game.world_effects.get_node("Rabbit")
	rabbit.start_tunnel(0, top, Vector3(0, 4.5, -27), Vector3.FORWARD, 6, 1.0)
	rabbit.tick(0.5)
	var digging: Vector3 = rabbit.get_node("Tunnels").get_child(0).get_node("Digging").position
	near(digging.y, game.map.definition.surface_height(Vector2(digging.x, digging.z)), "the burrow's moving mound stays on the actual slope")

func _cursor_surface() -> void:
	var connection := CursorConnection.new()
	game.add_child(connection)
	var cursors: CanvasLayer = game.get_node("TeammateCursors")
	cursors.configure(game, connection)
	var payload := {"world_x": 0.0, "world_z": 0.0, "visible": true, "pressed": false, "cursor_seq": 1, "presence_epoch": 1}
	cursors._receive(15, payload)
	near(cursors._peers[15].point.y, 8.0, "remote cursor XZ is placed on the summit")
	payload.world_x = 20.0
	payload.cursor_seq = 2
	cursors._receive(15, payload)
	near(cursors._peers[15].target.y, 0.0, "remote cursor target follows the lower terrace")
	cursors.tick(0.02)
	var point: Vector3 = cursors._peers[15].point
	near(point.y, game.map.definition.surface_height(Vector2(point.x, point.z)), "cursor smoothing does not float across a cliff")

func _run() -> void:
	create_timer(60.0, true, false, true).timeout.connect(func(): quit(3))
	_march_surface()
	var session := root.get_node("Session")
	var previous_map: String = session.block_war_map_id
	session.block_war_map_id = "switchback"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.ai_enabled = false
	game.audio.muted = true
	_materials()
	_scene_material_isolation()
	_ground_commands()
	_cursor_surface()
	await game.prepare_shutdown()
	session.block_war_map_id = previous_map
	print("BLOCK_WAR_SURFACE_RUNTIME checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
