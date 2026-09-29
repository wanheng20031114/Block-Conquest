extends SceneTree
## Focused native E review: authored scenes, actual casts and damage settlement.
## Run with run_godot_private_desktop.py; output contains two 24 fps clips.

const FPS := 24
const LINK_NODES: Array[String] = ["Chains", "LinkGrounds", "LinkAnchors", "LinkPlates"]
const KIND_LABELS: Array[String] = ["house", "tower", "smithy", "energy"]
var game: Node3D
var output := ""
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL BEAR_LINK_VISUAL ", label)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func frames(count: int) -> void:
	for frame: int in count:
		await RenderingServer.frame_post_draw

func effect_state(world: Node3D) -> Array:
	var effects: Node3D = world.world_effects.get_node("Bear")
	var state: Array = [effects.time]
	for path: String in LINK_NODES:
		var mesh: MultiMesh = effects.get_node(path).multimesh
		state.append([mesh.visible_instance_count, mesh.buffer])
	return state

func check_active(world: Node3D, label: String) -> void:
	var effects: Node3D = world.world_effects.get_node("Bear")
	check(world.bear.links.size() == 1, label + " one actual link")
	for path: String in LINK_NODES:
		var mesh: MultiMesh = effects.get_node(path).multimesh
		check(mesh.visible_instance_count > 0 and mesh.visible_instance_count <= mesh.instance_count, label + " bounded " + path)
	for path: String in ["LinkGrounds", "LinkAnchors", "LinkPlates"]:
		check(effects.get_node(path).multimesh.visible_instance_count == 2, label + " two building attachments " + path)

func check_cleared(world: Node3D, label: String) -> void:
	check(world.bear.links.is_empty(), label + " link rules cleared")
	for path: String in LINK_NODES:
		check(world.world_effects.get_node("Bear").get_node(path).multimesh.visible_instance_count == 0, label + " clears " + path)

func reset_game(map_id: String = "rift") -> void:
	if game != null:
		await game.prepare_shutdown()
	var session: Node = root.get_node("Session")
	session.block_war_map_id = map_id
	session.block_war_commander = &"bear"
	session.block_war_opponent_commander = &"bear"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.select_building(null)
	game.hud.hide()
	await frames(3)

func configure_building(building: WarBuilding, kind: int, faction: int, population: float = 80.0) -> void:
	building.kind = kind
	building.level = 1
	building.faction = faction
	building.population = population
	building.refresh_visual()

func focus(a: WarBuilding, b: WarBuilding, zoom: float) -> void:
	game.camera.size = zoom
	var center := (a.global_position + b.global_position) * 0.5
	if zoom >= 50.0:
		game.camera_rig.zoom_target = zoom
		game.camera_rig.focus_at(center, true)
	else:
		game.camera_rig.global_position = center

func codex_review(include_clip: bool = true) -> void:
	var page: Control = load("res://scenes/codex/codex.tscn").instantiate()
	root.add_child(page)
	await frames(8)
	page.get_node("%Entries").select(2)
	page._select_entry(2)
	page._select_skill(2, false)
	var demo: Control = page.get_node("%Demo")
	demo.set_playing(false)
	await frames(24)
	var world: Node3D = demo.world
	world.set_running(true)
	world.set_process(false)
	demo.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world._process(1.6)
	demo._update_caption()
	check(world.cast_succeeded and world.cast_count == 1, "codex actual E cast")
	check_active(world, "codex")
	await capture("codex_link_idle")
	if not include_clip:
		page.queue_free()
		await process_frame
		return
	# Start near actual troop arrival, so a four-second clip includes the pulse.
	world._process(2.4)
	DirAccess.make_dir_recursive_absolute(output.path_join("codex_clip"))
	var pulse_seen := false
	for frame: int in FPS * 4:
		world._process(1.0 / FPS)
		demo._update_caption()
		if not pulse_seen and float(world.bear.links[0].pulse) > 0.0:
			pulse_seen = true
			await capture("codex_link_damage")
		await capture("codex_clip/frame_%04d" % frame)
	check(pulse_seen, "codex real arrivals produce transfer pulse")
	world.set_running(false)
	var stopped := effect_state(world)
	var stopped_at: float = world.elapsed
	world._process(0.5)
	await frames(6)
	check(effect_state(world) == stopped and is_equal_approx(world.elapsed, stopped_at), "codex pause freezes meshes and simulation")
	world.set_running(true)
	world.set_process(false)
	world._process(1.5)
	check_cleared(world, "codex natural expiry")
	await capture("codex_link_expired")
	page.queue_free()
	await process_frame

func flat_review(kind: int) -> void:
	await reset_game()
	var target: WarBuilding = game.buildings[0]
	var support: WarBuilding = game.buildings[6]
	var attacker: WarBuilding = game.buildings[8]
	configure_building(target, kind, 0)
	configure_building(support, (kind + 1) % 4, 0)
	configure_building(attacker, 0, 1, 120.0)
	game.sync_environment_bonuses()
	var label := KIND_LABELS[kind] + "_to_" + KIND_LABELS[(kind + 1) % 4]
	focus(target, support, 18.0)
	check(game.cast_skill(2, target), label + " actual cast")
	check(game.bear.links[target.building_id].support == support.building_id, label + " correct support")
	check_active(game, label)
	game.simulate(0.25)
	await capture(label + "_close")
	focus(target, support, 58.0)
	game.hud.show()
	game.update_hud()
	await capture(label + "_normal")
	game.hud.hide()
	focus(target, support, 18.0)
	check(game.issue_order(attacker, target, 50, 1) > 0, label + " real dispatch")
	if kind == 0:
		DirAccess.make_dir_recursive_absolute(output.path_join("battle_clip"))
	var pulse_seen := false
	var before_support := support.population
	for frame: int in FPS * 4:
		game.simulate(1.0 / FPS)
		if not pulse_seen and float(game.bear.links[target.building_id].pulse) > 0.0:
			pulse_seen = true
			await capture(label + "_damage")
		if kind == 0:
			await capture("battle_clip/frame_%04d" % frame)
		else:
			await frames(1)
	check(pulse_seen and support.population < before_support, label + " actual attack transfers casualties")
	game.set_paused(true)
	game.hud.hide()
	var stopped := effect_state(game)
	var stopped_at: float = game.elapsed
	game.simulate(0.5)
	await frames(6)
	check(effect_state(game) == stopped and is_equal_approx(game.elapsed, stopped_at), label + " pause freezes meshes and simulation")
	game.set_paused(false)
	game.hud.hide()
	match kind:
		0:
			game.simulate(8.1)
		1:
			support.population = 1.0
			game._on_unit_arrived(target.building_id, 1, 21.0)
			game.simulate(1.0 / FPS)
		2:
			game._on_unit_arrived(support.building_id, 1, 400.0)
			game.simulate(1.0 / FPS)
		3:
			game._on_unit_arrived(target.building_id, 1, 400.0)
			game.simulate(1.0 / FPS)
	check_cleared(game, label + " " + ["expiry", "support exhausted", "support captured", "target captured"][kind])
	await capture(label + "_cleared")

func elevated_review() -> void:
	await reset_game("terraces")
	var target: WarBuilding = game.buildings[0]
	var support: WarBuilding = game.buildings[15]
	configure_building(target, 3, 0)
	configure_building(support, 0, 0)
	# Reposition one existing building on the authored lower terrain. The upper
	# residence remains at its authored site; no terrain or VFX is substituted.
	target.global_position = game.map.definition.surface_point(Vector3(-25, 0, -7))
	print("BEAR_LINK_ELEVATION target=", target.global_position, " support=", support.global_position)
	check(absf(target.global_position.y - support.global_position.y) > 4.0, "fixture crosses real terrain elevation")
	focus(target, support, 23.0)
	check(game.cast_skill(2, target), "elevated actual cast")
	check_active(game, "elevated")
	game.simulate(0.25)
	await capture("elevated_close")
	# Use the actual arrival handler to exercise damage sharing across height.
	# The relocated fixture does not invent a route in the baked navigation data.
	game._on_unit_arrived(target.building_id, 1, 21.0)
	game.simulate(1.0 / FPS)
	check(float(game.bear.links[target.building_id].pulse) > 0.0, "elevated damage transfers")
	await capture("elevated_damage")
	var chains: MultiMesh = game.world_effects.get_node("Bear/Chains").multimesh
	var above_ground := true
	for index: int in chains.visible_instance_count:
		var at := chains.get_instance_transform(index).origin
		above_ground = above_ground and at.y > game.map.definition.surface_height(Vector2(at.x, at.z))
	check(above_ground, "elevated chain centers remain above terrain")
	focus(target, support, 58.0)
	game.hud.show()
	await capture("elevated_normal")
	game.simulate(8.1)
	check_cleared(game, "elevated natural expiry")

func attachment_review() -> void:
	await reset_game()
	var target: WarBuilding = game.buildings[0]
	var support: WarBuilding = game.buildings[6]
	configure_building(target, 0, 0)
	configure_building(support, 1, 0)
	focus(target, support, 18.0)
	check(game.cast_skill(2, target), "upgrade fixture actual link")
	var effects: Node3D = game.world_effects.get_node("Bear")
	var old_mesh: Mesh = effects._link_mounts[target.building_id].mesh
	game.select_building(target)
	game.upgrade_selected()
	check(target.is_constructing and game.cast_skill(0, target), "upgrade fixture completes real paid construction")
	game.simulate(0.15)
	check(target.level == 2 and not target.is_constructing, "linked residence upgraded")
	var body: MeshInstance3D = target.get_node("Visual/House/Stone")
	check(effects._link_mounts[target.building_id].mesh == body.mesh and body.mesh != old_mesh, "upgrade refreshes cached attachment surface")
	await capture("house_upgraded_link_close")
	focus(target, support, 58.0)
	game.hud.show()
	game.update_hud()
	await capture("house_upgraded_link_normal")
	# A replica may retain the expired authoritative row until its deletion arrives.
	game.bear.links[target.building_id].remaining = 0.0
	effects.sync(game.bear, game.marches, game.by_id, 0.0)
	check(game.bear.links.has(target.building_id), "replica expired-row fixture retains rule row")
	for path: String in LINK_NODES:
		check(effects.get_node(path).multimesh.visible_instance_count == 0, "replica expired row clears " + path)
	check(effects._link_mounts.is_empty(), "replica expired row releases mount cache")

func _run() -> void:
	create_timer(150.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	var attachments_only := OS.get_cmdline_user_args().has("--attachments-only")
	await codex_review(not attachments_only)
	if not attachments_only:
		for kind: int in 4:
			await flat_review(kind)
		await elevated_review()
	await attachment_review()
	await game.prepare_shutdown()
	print("BEAR_LINK_VISUAL_RESULTS ", JSON.stringify({"checks": checks, "failures": failures, "clip_fps": FPS, "frames_per_clip": 0 if attachments_only else FPS * 4}))
	quit(0 if failures.is_empty() else 1)
