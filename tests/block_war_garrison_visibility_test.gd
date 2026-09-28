extends SceneTree
## Enemy population badges disappear without changing simulation or allied knowledge.
## Render with run_godot_private_desktop.py; argv[0] is the capture directory.

const RESOLUTION := Vector2i(1600, 900)
const TEAMS: Array[Array] = [[0, 2, 4], [1, 3, 5]]

var game: Node3D
var session: Node
var checks: int = 0
var failures: Array[String] = []
var original_map: String
var original_preferences: Dictionary
var output_directory: String


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL GARRISON_VISIBILITY ", description)


func _known(owner: int, viewer: int) -> bool:
	return owner == -1 or owner in TEAMS[0 if viewer in TEAMS[0] else 1]


func _badge(building: WarBuilding) -> Label3D:
	return building.get_node("PopulationLabel")


func _settle_collision() -> void:
	await physics_frame
	await process_frame


func _presentation_matches(building: WarBuilding, known: bool, population: String) -> bool:
	return _badge(building).text == (population if known else "") \
		and _badge(building).visible == known \
		and building.get_node("PopulationBadge").visible == known \
		and building.get_node("PickArea/BadgeCollisionShape3D").disabled == not known


func _matrix(building: WarBuilding) -> void:
	var original: Array = [building.faction, building.population, building.queued_population]
	building.population = 64.75
	building.queued_population = 13
	for viewer: int in 6:
		building.viewer_faction = viewer
		for owner: int in range(-1, 6):
			building.faction = owner
			building.refresh_visual()
			await _settle_collision()
			var context := "viewer %d / owner %d" % [viewer, owner]
			var visible := _known(owner, viewer)
			_check(building.is_population_visible() == visible, context + " has the correct knowledge boundary")
			_check(_presentation_matches(building, visible, "64"), context + " shows the badge, label and pick volume only for known garrisons")
			_check(building.population == 64.75 and building.available_population == 51.75, context + " preserves exact simulation and queued population")
		# Concealing a previously wide badge must remove its label, background and
		# pick volume together, while preserving the building's own collider.
		building.faction = viewer
		building.population = 9999.0
		building.refresh_visual()
		_check(building.get_node("PopulationBadge").scale.x > 1.0, "viewer %d can read an oversized friendly total" % viewer)
		building.faction = (viewer + 1) % 6
		building.refresh_visual()
		await _settle_collision()
		_check(_presentation_matches(building, false, ""), "viewer %d removes the previous wide badge and pick volume" % viewer)
		for population: int in [0, 9, 99, 9999]:
			building.population = float(population)
			building.refresh_visual()
			await _settle_collision()
			var context := "viewer %d / hidden population %d" % [viewer, population]
			_check(_badge(building).text.is_empty(), context + " leaves no number or placeholder")
			_check(not _badge(building).visible and not building.get_node("PopulationBadge").visible, context + " hides both the label and badge")
			_check(building.get_node("PickArea/BadgeCollisionShape3D").disabled, context + " disables the invisible badge's pick volume")
			_check(not building.get_node("PickArea/CollisionShape3D").disabled, context + " preserves picking the building itself")
			_check(building.population == population and building.available_population == maxf(0.0, population - 13.0), context + " does not modify population accounting")
		building.population = 64.75
		# Population does not change during these ownership changes: the visual
		# cache must still invalidate after capture and restored neutrality.
		for owner: int in [viewer, (viewer + 1) % 6, (viewer + 2) % 6, (viewer + 1) % 6, -1]:
			building.faction = owner
			building.pulse_capture()
			await _settle_collision()
			_check(_presentation_matches(building, _known(owner, viewer), "64"), "viewer %d restores or hides unchanged population after capture by %d" % [viewer, owner])
	building.faction = original[0]
	building.population = original[1]
	building.queued_population = original[2]
	building.viewer_faction = 0
	building.refresh_visual()


func _viewers() -> void:
	_check(game.faction_count == 6, "the authored islands match contains all six factions")
	for viewer: int in 6:
		game.local_faction = viewer
		await _settle_collision()
		for building: WarBuilding in game.buildings:
			var expected := str(maxi(0, floori(building.population)))
			_check(building.viewer_faction == viewer and _presentation_matches(building, _known(building.faction, viewer), expected), "changing local viewer to %d updates building %d without changing population" % [viewer, building.building_id])
	game.local_faction = 0
	await _settle_collision()
	game.select_building(game.by_id[0])
	game.hud._position_selection()
	_check(game.hud._actions_visible, "the local player retains controls for its own building")
	var enemy: WarBuilding = game.by_id[1]
	game.select_building(enemy)
	game.hud._position_selection()
	_check(game.selected == enemy and _presentation_matches(enemy, false, ""), "the local player can select an enemy without exposing its garrison")
	_check(not game.hud._actions_visible and not game.hud.get_node("%Selection").visible, "the local player receives no enemy action bar")
	_check(game.hud.get_node("%Upgrade").disabled, "the local player cannot upgrade an enemy building")
	game.select_building(null)


func _capture() -> void:
	# A reproducible local battlefield state presents owned, allied, neutral and
	# captured enemy outposts together. No persistent map or settings are edited.
	var enemy: WarBuilding = game.by_id[6]
	enemy.faction = 1
	enemy.population = 9999.0
	enemy.refresh_visual()
	game.by_id[0].population = 37.0
	game.by_id[0].refresh_visual()
	game.camera_rig.focus_at(Vector3(-48, 0, -17), true)
	game.camera.size = 62.0
	game.update_hud()
	for frame: int in 20:
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image.get_size() == RESOLUTION, "native screenshot uses 1600 by 900 resolution")
	_check(image.save_png(output_directory.path_join("garrison_visibility.png")) == OK, "native battlefield screenshot saves")


func _timeout() -> void:
	printerr("FAIL GARRISON_VISIBILITY timeout")
	# A second bounded timer also protects a shutdown regression. The private
	# desktop runner owns this process tree if even native release cannot finish.
	create_timer(6.0, true, false, true).timeout.connect(func(): quit(3))
	if is_instance_valid(game):
		await game.prepare_shutdown()
	quit(3)


func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(_timeout)
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		printerr("FAIL GARRISON_VISIBILITY output directory argument is required")
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path(arguments[0])
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		printerr("FAIL GARRISON_VISIBILITY cannot create output directory")
		quit(1)
		return
	root.size = RESOLUTION
	root.gui_disable_input = true
	session = root.get_node("Session")
	original_map = session.block_war_map_id
	original_preferences = session.settings.snapshot()
	session.block_war_map_id = "islands"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	for building: WarBuilding in game.buildings:
		_check(building.viewer_faction == game.local_faction, "ready initializes viewer on building %d" % building.building_id)
	await _matrix(game.by_id[0])
	await _viewers()
	await _capture()
	await game.prepare_shutdown()
	_check(game._closing and not game.is_processing(), "battle acknowledges safe shutdown")
	_check(session.settings.snapshot() == original_preferences, "verification does not apply or save user settings")
	session.block_war_map_id = original_map
	print("GARRISON_VISIBILITY ", JSON.stringify({"checks": checks, "failures": failures, "output": output_directory}))
	quit(0 if failures.is_empty() else 1)
