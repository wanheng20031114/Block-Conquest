extends SceneTree
## Native GPU frame equality proves invisibility rather than merely low alpha.
const Snapshot := preload("res://scripts/network/war_snapshot.gd")
var fixture: Control
var host: Node3D
var replica: Node3D
var displayed: Node3D
var output := ""
var checks := 0
var failures: Array[String] = []
var casualties := 0
var defeat_visuals := 0
var march_sounds := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL FROG_CLOAK_RENDER ", label)

func frames(count: int = 3) -> void:
	for frame: int in count: await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frames()
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)

func pixels_match(label: String, expected := true) -> void:
	await frames()
	var actual: Image = fixture.get_node("Actual/Viewport").get_texture().get_image()
	var reference: Image = fixture.get_node("Reference/Viewport").get_texture().get_image()
	check((actual.get_data() == reference.get_data()) == expected, label + " GPU pixels " + ("match empty field" if expected else "show visible formation"))

func make_game() -> Node3D:
	var game: Node3D = load("res://scenes/block_war/block_war.tscn").instantiate()
	fixture.get_node("Actual/Viewport/World").add_child(game)
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.camera_rig.keyboard_pan = false
	game.camera_rig.global_position = Vector3.ZERO
	game.camera.current = false
	game.ai_enabled = false
	game.audio.muted = true
	game.energy = 100.0
	game.hud.hide()
	game.get_node("Orders").hide()
	game.map.hide()
	game.get_node("Sun").hide()
	game.get_node("WorldEnvironment").environment = null
	game.hide()
	return game

func display_game(game: Node3D) -> void:
	if displayed != null:
		displayed.hide()
	displayed = game
	game.show()
	game.camera.current = false
	fixture.get_node("Actual/Viewport/World/Camera").make_current()

func sync_effects(game: Node3D, delta: float = 0.1) -> void:
	game.marches._render()
	game.world_effects.update_skills(delta, game.faction_skills, game.shields, game.by_id, game.marches)
	game.world_effects.get_node("Frog").sync(game.marches, delta)
	game.world_effects.get_node("Rabbit").update_rush(delta, game.marches)
	game.world_effects.get_node("PigEffects").update_units(delta, game.marches)

func preview_review() -> void:
	display_game(host)
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.rush_remaining = 0.0
		unit.levitation_remaining = 0.0
		unit.order.pig_charge = false
		unit.order.airborne = false
	host.get_node("Orders").show()
	host.get_node("Orders/Atmosphere").hide()
	for entry: Array in [[&"frog", 1, 0, "frog_preview"], [&"frog", 0, 1, "frog_preview"], [&"fox", 2, 1, "fox_preview"], [&"rabbit", 0, 0, "rush_preview"], [&"rabbit", 2, 0, "recall_preview"]]:
		host.local_faction = entry[2]
		host.faction_skills[entry[2]].commander = entry[0]
		host.faction_skills[entry[2]].energy = 100.0
		host.faction_skills[entry[2]].cooldowns.fill(0.0)
		host._cancel_skill_drag()
		host.armed_skill = entry[1]
		var at: Vector3 = host.map.definition.surface_point(host.marches._units[0].position)
		var screen: Vector2 = host.camera.unproject_position(at)
		host._update_skill_drag(screen, true)
		check(host.ground_skill_target.is_finite(), "%s %s preview points inside actual map" % [entry[0], entry[1]])
		check(host.get(entry[3]).is_empty(), "%s %s hidden units excluded from rings counts and validity" % [entry[0], entry[1]])
		await frames()
		var hidden_pixels: PackedByteArray = fixture.get_node("Actual/Viewport").get_texture().get_image().get_data()
		var preserved: Array[WarMarches.MarchUnit] = host.marches._units
		var empty_units: Array[WarMarches.MarchUnit] = []
		host.marches._units = empty_units
		host._update_skill_drag(screen, true)
		await frames()
		var empty_pixels: PackedByteArray = fixture.get_node("Actual/Viewport").get_texture().get_image().get_data()
		check(hidden_pixels == empty_pixels, "%s %s preview pixels equal no soldiers" % [entry[0], entry[1]])
		host.marches._units = preserved
	# Route previews are cached for 0.1 seconds; a new cloak must hide them now.
	host.local_faction = 0
	host.faction_skills[0].commander = &"rabbit"
	host.armed_skill = 2
	host.marches._units[0].cloaked = false
	host.ground_skill_target = host.marches._units[0].position
	host._refresh_rabbit_preview(true)
	check(not host.recall_preview.is_empty(), "visible recall route positive control")
	host.marches._units[0].cloaked = true
	host._refresh_rabbit_preview(false)
	check(host.recall_preview.is_empty(), "cached recall route immediately disappears on cloak")
	host._cancel_skill_drag()
	host.get_node("Orders").hide()
	var returned: WarMarches.MarchUnit = host.marches._units[0]
	check(host.cast_ground_skill(2, returned.position), "manual recall still affects hidden troops")
	check(returned.order.returning and returned.cloaked, "recall changes hidden route without revealing soldier")
	# The public whistle is intentionally visible; isolate the per-soldier dust.
	host.world_effects.get_node("Rabbit/Rallies").hide()
	await pixels_match("hidden recall produces no per-soldier dust")
	host.faction_skills[0].commander = &"frog"

func _run() -> void:
	create_timer(90.0, true, false, true).timeout.connect(func(): quit(3))
	output = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	root.gui_disable_input = true
	root.get_node("Session").block_war_map_id = "highland"
	root.get_node("Session").block_war_commander = &"frog"
	fixture = load("res://tests/scenes/frog_cloak_render_fixture.tscn").instantiate()
	root.add_child(fixture)
	host = make_game()
	replica = make_game()
	display_game(host)
	host.marches.send(0, 1, 0, 24, PackedVector3Array([Vector3(0, 0, -5), Vector3(0, 0, 60)]))
	host.marches.tick(2.4)
	await pixels_match("ordinary soldiers", false)
	await capture("01_visible_before_cast")
	var cast_center := Vector3(0, 0, -1.5)
	check(host.cast_ground_skill(2, cast_center), "real frog cloak cast accepted")
	check(host.marches._units.size() == 24 and host.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.cloaked), "all 24 soldiers retain authoritative cloak flags")
	check(not host.marches.has_node("CloakedMilitia"), "no transparent model pool remains")
	# The public cast bloom belongs to the selected ground. Let it finish before
	# checking that no body, shadow or continuously following cue remains.
	for frame: int in 32:
		host.world_effects.tick(1.0 / 24.0)
		sync_effects(host, 1.0 / 24.0)
		await process_frame
	await pixels_match("owner view")
	await capture("02_completely_invisible")
	var before: Vector3 = host.marches._units[0].position
	host.marches.tick(2.0)
	sync_effects(host)
	check(host.marches._units[0].position.distance_to(before) > 1.0, "hidden formation keeps marching")
	await pixels_match("moving owner view")
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.rush_remaining = 4.0
		unit.order.pig_charge = true
		unit.order.airborne = true
		unit.order.panicked = true
	sync_effects(host)
	await pixels_match("flight and charge without levitation")
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.order.airborne = false
	sync_effects(host)
	await pixels_match("ground rush and charge trails")
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.levitation_remaining = 2.0
	sync_effects(host)
	check(host.world_effects.get_node("Frog/Bubbles").multimesh.visible_instance_count == 0, "levitation has no revealing bubbles")
	check(host.marches.get_node("PanicMarks").multimesh.visible_instance_count == 0, "panic has no revealing marks")
	await pixels_match("overlapping buffs")
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.levitation_remaining = 0.0
	# Imported authoritative units use the identical renderer for every viewer.
	var writer := Snapshot.new()
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(writer.capture(host, 7), "", true, true))
	check(Snapshot.valid(snapshot, replica), "cloaked complete snapshot validates")
	var reader := Snapshot.new()
	for viewer: int in [0, 2, 1]:
		replica.local_faction = viewer
		reader.install(replica, Snapshot.for_player(snapshot, viewer))
		display_game(replica)
		sync_effects(replica)
		check(replica.marches._units.size() == 24 and replica.marches._units.all(func(unit: WarMarches.MarchUnit): return unit.cloaked), "replica viewer %d retains live hidden formation" % viewer)
		await pixels_match("replica viewer %d" % viewer)
		reader.present(replica, snapshot, 0.2)
		sync_effects(replica)
		await pixels_match("replica interpolation viewer %d" % viewer)
	await capture("03_replica_invisible_with_buffs")
	await preview_review()
	display_game(host)
	host.marches.combat_death.connect(func(_f: int, _target: int, _killer: int): casualties += 1)
	host.marches.unit_defeated.connect(func(_at: Vector3, _heading: Vector3, _f: int, _impulse: Vector3, _burning: bool): defeat_visuals += 1)
	for unit: WarMarches.MarchUnit in host.marches._units:
		unit.levitation_remaining = 0.0
		unit.order.airborne = false
		unit.rush_remaining = 0.0
		unit.order.pig_charge = false
	host.audio.sound_played.connect(func(kind: StringName, _at: Vector3, _spatial: bool):
		if kind == &"war_march": march_sounds += 1)
	host.audio.muted = false
	host.audio.tick_marches(0.4, host.marches)
	check(march_sounds == 0, "cloaked ground formation emits no footsteps")
	host.marches._units[0].cloaked = false
	host.audio.tick_marches(0.4, host.marches)
	check(march_sounds == 1, "same exposed formation produces ordinary footsteps")
	host.marches._units[0].cloaked = true
	host.marches.ignite_at(host.marches._units[0].position, 20.0, 1)
	check(host.marches._units.is_empty() and casualties == 24, "area fire still kills every hidden soldier and records casualties")
	check(defeat_visuals == 0, "hidden casualties emit no corpse or replicated death visual")
	sync_effects(host)
	await pixels_match("hidden casualty aftermath")
	await capture("04_hidden_casualties_no_reveal")
	# Keep the complete authored battles intact throughout their lifecycle.
	displayed = null
	await host.prepare_shutdown()
	await replica.prepare_shutdown()
	host.free()
	replica.free()
	fixture.free()
	print("FROG_CLOAK_RENDER_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
