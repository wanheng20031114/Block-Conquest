extends SceneTree
## Run from an empty --path with absolute --main-pack and --script paths.
## Resolves every battle's assets from the pack and shuts audio down normally.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func _run() -> void:
	create_timer(150, true, false, true).timeout.connect(func(): quit(3))
	var session: Node = root.get_node("Session")
	check(ProjectSettings.get_setting("application/config/name") == "积木战争", "standalone product identity")
	check(not session.has_node("RelayClient") and not session.has_node("Rogue"), "standalone session")
	check(ProjectSettings.get_setting("application/config/version") == "1.3.4", "multiplayer release version")
	check(ProjectSettings.get_setting("internationalization/locale/include_text_server_data", false), "export includes CJK line breaking data")
	check(FileAccess.file_exists("res://" + TextServerManager.get_primary_interface().get_support_data_filename()), "text support data is present in the actual PCK")
	check(InputMap.has_action("pause") and InputMap.action_get_events("pause").any(func(event: InputEvent): return event is InputEventKey and event.physical_keycode == KEY_F3), "packaged native pause action maps F3")
	check(session.has_node("Online"), "packaged native multiplayer service")
	var protocol: Script = load("res://scripts/network/war_protocol.gd")
	var catalog: Script = load("res://scripts/block_war/war_map_catalog.gd")
	check(protocol.content_hash().length() == 64, "packaged compatibility fingerprint")
	for map_id: String in ["terraces", "switchback", "crown"]:
		var definition: Resource = catalog.find_map(map_id)
		check(definition != null, "packaged catalog includes elevated battlefield " + map_id)
		if definition == null:
			continue
		check(definition.has_elevation(), map_id + " includes its native terrain resource")
		if not definition.has_elevation():
			continue
		var surface: Resource = definition.terrain
		check(surface.width > 1 and surface.depth > 1 and surface.heights.size() == surface.width * surface.depth and surface.max_height > 0.0, map_id + " includes the complete elevated vertex grid")
		check(surface.height_texture != null and surface.preview_texture != null, map_id + " includes both embedded terrain textures")
		if surface.height_texture != null and surface.preview_texture != null:
			var size := Vector2(surface.width, surface.depth)
			check(surface.height_texture.get_size() == size and surface.preview_texture.get_size() == size, map_id + " packaged terrain textures match the vertex grid")
			var height_image: Image = surface.height_texture.get_image()
			check(height_image != null and height_image.get_format() == Image.FORMAT_RF, map_id + " preserves metre-valued RF height data")
	var certificate := X509Certificate.new()
	check(certificate.load("res://scripts/network/relay_trust.crt") == OK, "packaged DTLS trust certificate")
	check(not FileAccess.file_exists("res://server/war_relay_server.gd") and not FileAccess.file_exists("res://server/war_relay_server.gdc"), "server implementation excluded from client")
	check(not ResourceLoader.exists("res://tmp/skill-hover-fix/war_hud.before.gd"), "temporary source backups excluded from client")
	check(ResourceLoader.exists("res://scenes/network/war_room.tscn"), "packaged room scene")
	check(not FileAccess.file_exists("res://scenes/main.tscn") and not FileAccess.file_exists("res://scenes/main.tscn.remap"), "no traditional RTS battle in product")
	check(change_scene_to_file("res://scenes/lobby.tscn") == OK, "home loads")
	await scene_changed
	for definition: Resource in catalog.MAPS:
		var map_id: String = definition.map_id
		session.block_war_map_id = map_id
		check(session.start_war(true) == OK, map_id + " starts")
		await session.transition.completed
		var battle: Node = current_scene
		check(battle.map.definition.map_id == map_id, map_id + " selected map instantiated")
		check(battle.buildings.size() == battle.map.definition.building_positions.size(), map_id + " authored buildings loaded")
		check(protocol.MAP_SEATS[map_id] == battle.faction_count, map_id + " packaged relay seats match the battle")
		check(battle.get_node("Audio/Music").playing, map_id + " packaged music plays")
		check(battle.has_node("TeammateCursors"), map_id + " packaged teammate cursor scene")
		battle.camera_rig.focus_at(Vector3.ZERO, true)
		Input.action_press("war_pan_right")
		battle.camera_rig._process(0.1)
		Input.action_release("war_pan_right")
		check(battle.camera_rig.destination.length() > 0, map_id + " camera consumes standalone actions")
		await battle.prepare_shutdown()
		session.back_to_lobby()
		await session.transition.completed
		check(current_scene.scene_file_path == "res://scenes/lobby.tscn", map_id + " returns home")
	print("PRODUCT_RELEASE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
