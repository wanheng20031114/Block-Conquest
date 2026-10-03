extends SceneTree
## Native input verifies the new conversion entry, rate tooltip and guide article.

var game: Node3D
var checks: int = 0
var failures: Array[String] = []
var output_directory: String


func _initialize() -> void:
	_run.call_deferred()


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("FAIL ENERGY_TOWER_HUD ", description)


func _frames(count: int = 8) -> void:
	for frame: int in count:
		await RenderingServer.frame_post_draw


func _move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)


func _click(button: Control) -> void:
	var at := button.get_global_rect().get_center()
	_move(at)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	_check(image.save_png(output_directory.path_join(name + ".png")) == OK, "screenshot saves: " + name)


func _timeout() -> void:
	printerr("FAIL ENERGY_TOWER_HUD timeout")
	create_timer(5.0, true, false, true).timeout.connect(func(): quit(3))
	if is_instance_valid(game):
		await game.prepare_shutdown()
	quit(3)


func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(_timeout)
	output_directory = ProjectSettings.globalize_path(OS.get_cmdline_user_args()[0])
	DirAccess.make_dir_recursive_absolute(output_directory)
	root.size = Vector2i(1600, 900)
	var session := root.get_node("Session")
	var old_map: String = session.block_war_map_id
	var preferences: Dictionary = session.settings.snapshot()
	session.block_war_map_id = "rift"
	change_scene_to_file("res://scenes/block_war/block_war.tscn")
	await scene_changed
	game = current_scene
	game.set_process(false)
	game.camera_rig.set_process(false)
	game.camera_rig.edge_scroll = false
	game.ai_enabled = false
	game.audio.muted = true
	var home: WarBuilding = game.by_id[0]
	game.camera_rig.focus_at(home.global_position, true)
	game.camera.size = 28.0
	var hud: CanvasLayer = game.hud
	var conversions: Array[Button] = [hud.get_node("%ConvertHouse"), hud.get_node("%ConvertTower"), hud.get_node("%ConvertForge"), hud.get_node("%ConvertEnergy")]
	for kind: int in 4:
		home.kind = kind
		home.level = 1
		home.population = 60.0
		home.refresh_visual()
		game.select_building(home)
		await _frames()
		_check(hud.get_node("%Upgrade").visible == (kind in [0, 1]), "only residences and cannon towers expose upgrades: %d" % kind)
		for target: int in 4:
			var allowed := target != kind and (target != 3 or kind == 2)
			_check(conversions[target].is_visible_in_tree() == allowed, "kind %d shows exactly the legal conversion to %d" % [kind, target])
			_check(conversions[target].disabled == not allowed, "kind %d enables only the legal conversion to %d" % [kind, target])
			if allowed:
				var cost := 5 if kind in [2, 3] and target in [2, 3] else 20
				_check(conversions[target].get_node("Cost/Amount").text == str(cost) and conversions[target].tooltip_text.contains("消耗 %d 名驻军" % cost), "kind %d displays its actual conversion cost to %d" % [kind, target])
		_check(hud.get_node("%Selection").size.x == 226.0, "three actions fit the current 68-pixel buttons and spacing for kind %d" % kind)
		_check(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(hud.get_node("%Selection").get_global_rect()), "building actions fit inside the viewport")
	for kind: int in [2, 3]:
		home.kind = kind
		home.population = 4.0
		home.refresh_visual()
		game.select_building(home)
		var target := 3 if kind == 2 else 2
		_check(conversions[target].disabled and conversions[target].tooltip_text.contains("还差 1 名驻军"), "kind %d shows the one-soldier shortfall below five" % kind)
		home.population = 5.0
		game.update_hud()
		_check(not conversions[target].disabled and not conversions[target].tooltip_text.contains("还差"), "kind %d enables discounted conversion at exactly five" % kind)
		_check(conversions[0].disabled and conversions[1].disabled, "five soldiers still cannot buy a residence or cannon tower")
	# Use the actual mouse entry to pay for and finish the selected forge.
	home.kind = 2
	home.population = 60.0
	home.refresh_visual()
	game.select_building(home)
	await _frames()
	var energy_button: Button = conversions[3]
	_check(energy_button.tooltip_text.contains("+0.5 / +0.25 / +0.15") and energy_button.tooltip_text.contains("中立建筑除外"), "conversion tooltip states marginal recovery and the enemy-only reward")
	await _capture("00_forge_actions")
	_click(energy_button)
	await _frames(2)
	_check(home.is_constructing and home.kind == 2 and home.conversion_target == 3 and home.population == 55.0, "native energy action pays five soldiers and starts the forge conversion")
	_check(home.construction_remaining == 10.0 and energy_button.disabled and energy_button.get_node("Cost/Amount").text == "10s", "conversion displays its disabled ten-second countdown")
	_click(energy_button)
	_check(home.population == 55.0 and home.construction_remaining == 10.0, "repeated input cannot repay or restart construction")
	game.simulate(10.0)
	game.update_hud()
	await _frames()
	_check(home.kind == 3 and not home.is_constructing and home.max_level == 1, "paid conversion installs the fixed-level energy tower")
	_check(not hud.get_node("%Upgrade").visible and not energy_button.visible, "completed energy tower has no upgrade or self-conversion")
	_check(conversions[0].visible and conversions[1].visible and conversions[2].visible, "completed energy tower can convert back to each original building")
	_check(hud.get_node("%EnergyBar").tooltip_text.contains("+1.50 点/秒") and hud.get_node("%EnergyBar").tooltip_text.contains("1 座有效能量塔"), "energy tooltip shows the first tower's actual recovery rate")
	await _capture("01_completed_tower")
	var second: WarBuilding = game.by_id[3]
	second.kind = 3
	second.level = 1
	second.faction = 0
	second.refresh_visual()
	game.update_hud()
	var energy_bar: ProgressBar = hud.get_node("%EnergyBar")
	_check(energy_bar.tooltip_text.contains("+1.75 点/秒") and energy_bar.tooltip_text.contains("2 座有效能量塔") and energy_bar.tooltip_text.contains("玩家独立"), "energy tooltip updates the actual second marginal bonus and independent ownership")
	_check(energy_bar.tooltip_text.contains("前 100 秒 +1.0 点/秒，之后 +1.5 点/秒"), "natural recovery explanation preserves the fractional late rate")
	_check(energy_bar.mouse_filter != Control.MOUSE_FILTER_IGNORE, "the energy strip accepts native tooltip hover")
	_move(energy_bar.get_global_rect().get_center())
	await _frames(24)
	await _capture("02_energy_tooltip")
	for bracket: Array in [[2.999, "0.20"], [3.0, "0.15"], [4.999, "0.15"], [5.0, "0.10"]]:
		game.morale.adjust(0, game.MORALE.points_for_stars(bracket[0]) - game.morale.points(0))
		game.update_hud()
		_check(energy_bar.tooltip_text.contains("当前技力 +%s" % bracket[1]), "tooltip follows fractional morale bracket: %s" % bracket[0])
	game.elapsed = 100.0
	game.energy = 75.15
	game.update_hud()
	_check(energy_bar.tooltip_text.contains("75.15 / 100") and energy_bar.tooltip_text.contains("+2.25 点/秒"), "tooltip preserves fractional energy and switches the natural rate at one hundred seconds")
	_move(energy_bar.get_global_rect().get_center() + Vector2(4, 0))
	await _frames(24)
	await _capture("03_combat_energy_late")
	_click(conversions[2])
	await _frames(2)
	_check(home.kind == 3 and home.conversion_target == 2 and home.population == 50.0 and home.construction_cost == 5, "native reverse action pays five soldiers to restore the forge")
	_check(home.construction_remaining == 10.0 and conversions[2].disabled and conversions[2].get_node("Cost/Amount").text == "10s", "reverse action shows the same ten-second countdown")
	game.simulate(10.0)
	game.update_hud()
	_check(home.kind == 2 and not home.is_constructing, "native reverse conversion completes into a forge")
	_click(hud.get_node("%Help"))
	await _frames(24)
	var help_detail: Label = hud.get_node("%HelpCard/Detail2")
	_check(help_detail.text.contains("互相改建花费 5 人，其余改建 20 人") and help_detail.get_visible_line_count() >= help_detail.get_line_count(), "help explains both prices without clipping")
	await _capture("04_conversion_help")
	await game.prepare_shutdown()
	change_scene_to_file("res://scenes/codex/codex.tscn")
	await scene_changed
	game = null
	root.size = Vector2i(1280, 720)
	await _frames()
	_click(current_scene.get_node("%Guides"))
	await _frames()
	var entries: ItemList = current_scene.get_node("%Entries")
	var row := -1
	for index: int in entries.item_count:
		if entries.get_item_text(index) == "能量塔":
			row = index
	_check(row >= 0, "codex exposes the fourth building with its final name")
	if row >= 0:
		entries.select(row)
		entries.ensure_current_is_visible()
		await _frames(2)
		_click_at_entry(entries, row)
		await _frames()
		_check(current_scene.get_node("%DetailTitle").text == "能量塔", "native list selection opens the energy article")
		var restrictions: String = current_scene.get_node("%SectionBody2").text
		_check(restrictions.contains("消耗 5 人") and restrictions.contains("改建回铁匠铺也消耗 5 人") and restrictions.contains("改建回住宅或炮塔消耗 20 人"), "codex lists the two five-soldier directions and ordinary reverse prices")
		for name: String in ["DetailSummary", "GuideTip", "SectionBody0", "SectionBody1", "SectionBody2"]:
			var label: Label = current_scene.get_node("%" + name)
			_check(not label.text.is_empty() and label.get_visible_line_count() >= label.get_line_count(), "guide text fits without internal truncation: " + name)
		_check(current_scene.get_node("%GuideIcon").texture is DPITexture, "new guide illustration remains sharp when enlarged")
		await _capture("03_codex_energy")
	session.block_war_map_id = old_map
	_check(session.settings.snapshot() == preferences, "HUD verification preserves all user preferences")
	print("ENERGY_TOWER_HUD ", JSON.stringify({"checks": checks, "failures": failures, "output": output_directory}))
	quit(0 if failures.is_empty() else 1)


func _click_at_entry(entries: ItemList, row: int) -> void:
	var at: Vector2 = entries.get_global_transform() * entries.get_item_rect(row).get_center()
	_move(at)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
