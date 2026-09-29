extends SceneTree
## Native HUD only: no simulation, saved preferences, sound, or external input.
## -- <output-directory> additionally captures the same cases on a GPU viewport.

var hud: CanvasLayer
var balance: Control
var checks: int = 0
var failures: Array[String] = []
var output: String = ""

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func sample(totals: Array, morale: Array) -> Dictionary:
	var state := {"commander": &"squirrel", "enemy_commander": &"rabbit", "player_total": 0, "enemy_total": 0,
		"faction_buildings": totals, "morale_stars": morale, "faction_count": totals.size(),
		"map_title": "裂谷交汇", "map_mode": "%dv%d" % [totals.size() / 2, totals.size() / 2], "team_size": totals.size() / 2,
		"time": 126, "percentage": 50, "forges": 0, "selected_owned": false, "selected_level": 0,
		"selected_available_population": 0, "upgrade_cost": 10, "selected_max_level": 4, "construction_remaining": 0.0,
		"conversion_target": -1, "selected_kind": -1, "selected_detail": "", "can_upgrade": false, "convert_cost": 20,
		"armed_skill": -1, "energy": 60.0, "cooldowns": [0.0, 0.0, 0.0, 0.0], "skill_durations": [0.0, 0.0, 0.0, 0.0],
		"energy_costs": [30, 30, 35, 70], "energy_max": 100.0, "energy_regen": 2.0, "energy_tower_count": 0}
	for faction: int in totals.size():
		state["player_total" if faction % 2 == 0 else "enemy_total"] += int(totals[faction])
	return state

func capture(label: String) -> void:
	if output.is_empty():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func verify_permanent_bonuses() -> void:
	var bonus: Label = hud.get_node("%ForgeBonus")
	for example: Array in [[0, 0.0, 0, 0, 0], [0, 0.9999, 0, 0, 0], [0, 5.0, 25, 100, 50], [1, 0.0, 30, 15, 0], [1, 4.9999, 50, 95, 40], [1, 5.0, 55, 115, 50], [2, 0.0, 50, 25, 0], [3, 0.0, 70, 35, 0], [4, 0.0, 80, 40, 0], [7, 5.0, 105, 140, 50]]:
		var state := sample([10, 10], [example[1], 0.0])
		state.forges = example[0]
		hud.update_state(state)
		check(bonus.text == "攻 +%d%% · 防 +%d%%\n移速 +%d%%" % [example[2], example[3], example[4]], "forge %d adds combat only; movement uses complete stars from %s" % [example[0], example[1]])
		check(bonus.tooltip_text.contains("铁匠铺 %d 座" % example[0]) and bonus.tooltip_text.contains("士气 %d 星" % floori(float(example[1]))), "tooltip separates forge and morale sources")
		for source: String in bonus.tooltip_text.split("\n"):
			if source.begins_with("铁匠铺 "):
				check(not source.contains("移速 +"), "forge tooltip never advertises a movement bonus")
			if source.begins_with("士气 "):
				check(source.contains("移速 +%d%%" % example[4]), "morale tooltip explains the entire permanent movement bonus")
		for line: String in bonus.text.split("\n"):
			check(bonus.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, bonus.get_theme_font_size("font_size")).x <= bonus.size.x, "permanent bonus text fits existing portrait column")
	check(bonus.mouse_filter == Control.MOUSE_FILTER_PASS and not hud.is_pointer_blocked(bonus.get_global_rect().get_center()), "bonus tooltip preserves battlefield input")
	var team_state := sample([10, 10, 10, 10], [5.0, 0.0, 0.0, 0.0])
	team_state.commander = &"rabbit"
	team_state.forges = 1
	team_state.skill_durations[0] = 4.0
	hud.update_state(team_state)
	check(bonus.text == "攻 +55% · 防 +115%\n移速 +50%", "team label shows own permanent bonuses without forge speed or temporary rabbit buff")
	check(bonus.tooltip_text.begins_with("你的全军常驻加成") and bonus.tooltip_text.contains("炮塔守备与临时技能另行结算"), "tooltip identifies local ownership and bonus scope")

func verify_near_full_stars() -> void:
	var row: Control = balance.get_node("Stars/Faction1")
	var star: TextureProgressBar = row.get_child(4)
	hud.update_state(sample([100, 100], [0.0, 5.0]))
	check(star.value == 1.0 and star.tint_progress == Color.WHITE and star.get_node("Glow").visible, "full fifth star retains bright gold and white glow")
	check(not row.tooltip_text.contains("下颗星充能"), "maximum level has no nonexistent next star")
	for example: Array in [[4.9, "90.0%"], [4.99, "99.0%"], [4.9975, "99.7%"], [4.999999, "99.9%"]]:
		hud.update_state(sample([100, 100], [0.0, 5.0]))
		hud.update_state(sample([100, 100], [0.0, example[0]]))
		check(absf(star.value - (float(example[0]) - 4.0)) < 0.000000000001, "near-full charge keeps its original continuous ratio %s" % example[0])
		check(star.tint_progress.r <= 0.65 and star.tint_progress.g <= 0.65 and star.tint_progress.b <= 0.65 and star.tint_progress.a == 1.0 and not star.get_node("Glow").visible, "dropping below full charge immediately dims gold and removes glow %s" % example[0])
		check(row.tooltip_text.contains("敌方一 · 4 星") and row.tooltip_text.contains("攻击 +20% · 防御 +80% · 移速 +40%") and row.tooltip_text.ends_with("下颗星充能 " + example[1]), "tooltip keeps whole-star bonuses and floors the next-star percentage %s" % example[0])
		hud.update_state(sample([100, 100], [0.0, 5.0]))
		check(star.tint_progress == Color.WHITE and star.get_node("Glow").visible, "refilling restores full brightness and glow %s" % example[0])

func verify(totals: Array, morale: Array, label: String) -> void:
	hud.update_state(sample(totals, morale))
	await create_timer(0.35).timeout
	var population: float = 0.0
	for total: int in totals:
		population += total
	var right: float = 0.0
	var previous_row: Rect2 = Rect2()
	for faction: int in [0, 2, 4, 1, 3, 5]:
		var row: Control = balance.get_node("Stars/Faction%d" % faction)
		var segment: ColorRect = balance.get_node("Segments/Faction%d" % faction)
		check(row.visible == (faction < totals.size()), label + " seat visibility %d" % faction)
		if faction >= totals.size():
			continue
		check(row.get_child_count() == 5, label + " five authored slots %d" % faction)
		check(row.tooltip_text.contains("%d 星" % floori(float(morale[faction]))) and row.tooltip_text.contains("防御 +%d%%" % (floori(float(morale[faction])) * 20)), label + " tooltip uses complete star bonuses %d" % faction)
		check(row.mouse_filter == Control.MOUSE_FILTER_PASS and not hud.is_pointer_blocked(row.get_global_rect().get_center()), label + " morale hover preserves battlefield input %d" % faction)
		if population > 0.0:
			check(absf(segment.position.x - right) < 0.1 and absf(segment.size.x / balance.size.x - float(totals[faction]) / population) < 0.001, label + " exact public building share %d" % faction)
		else:
			check(not segment.visible, label + " zero owned buildings leaves neutral bar %d" % faction)
		right += segment.size.x
		var rect := Rect2(row.position, row.size * row.scale)
		check(rect.position.x >= -0.1 and rect.end.x <= balance.size.x + 0.1, label + " row stays inside bar %d" % faction)
		check(previous_row.size == Vector2.ZERO or previous_row.end.x + 3.0 <= rect.position.x, label + " neighboring rows never overlap %d" % faction)
		previous_row = rect
		for star_index: int in 5:
			var star: TextureProgressBar = row.get_child(star_index)
			var expected: float = clampf(float(morale[faction]) - star_index, 0.0, 1.0)
			check(is_equal_approx(star.value, expected), label + " fractional fill %d/%d" % [faction, star_index])
			check(star.get_node("Glow").visible == (expected >= 1.0), label + " only fully charged glows %d/%d" % [faction, star_index])
	await capture(label)

func _run() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func(): quit(3))
	root.size = Vector2i(1600, 900)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	hud = load("res://scenes/block_war/hud.tscn").instantiate()
	root.add_child(hud)
	balance = hud.get_node("%Balance")
	var first_star: TextureProgressBar = balance.get_node("Stars/Faction0/Star0")
	check(first_star.texture_under != null and first_star.texture_progress != null and first_star.get_node("Glow").texture != null, "all star textures are imported")
	await create_timer(0.8).timeout
	verify_permanent_bonuses()
	await capture("00_permanent_bonuses")
	verify_near_full_stars()
	await verify([120, 120], [0.0, 2.5], "01_duel_partial")
	await verify([120, 120, 120, 120], [1.0, 2.0, 3.0, 4.0], "02_four_players")
	await verify([120, 120, 120, 120, 120, 120], [0.0, 1.0, 2.25, 3.5, 4.75, 5.0], "03_six_players")
	await verify([2, 6, 280, 500, 11, 1], [5.0, 0.0, 2.5, 3.1, 0.9, 4.99], "04_small_shares")
	root.size = Vector2i(1280, 720)
	await process_frame
	await verify([0, 10000, 1, 0, 1, 0], [0.0, 5.0, 1.5, 0.0, 4.1, 0.9999], "05_extreme_720p")
	root.size = Vector2i(960, 540)
	await process_frame
	await verify([10, 10, 10, 10, 10, 10], [1.0, 2.0, 3.0, 4.0, 5.0, 0.0], "06_six_small_window")
	await verify([0, 0, 0, 0, 0, 0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "07_all_empty")
	hud.update_state(sample([10, 10], [5.0, 5.0]))
	hud.update_state(sample([10, 10], [0.9999, 4.5]))
	check(not balance.get_node("Stars/Faction0/Star0/Glow").visible and not balance.get_node("Stars/Faction1/Star4/Glow").visible, "losing full charge hides glow immediately")
	var stars_bottom: float = balance.get_node("Stars/Faction0").get_global_rect().end.y
	check(hud.get_node("%Time").get_global_rect().position.y > stars_bottom and hud.get_node("%MapTitle").get_global_rect().position.y >= hud.get_node("%Time").get_global_rect().end.y, "existing time and map labels stay below all stars")
	hud.notify("气势提升")
	check(hud.get_node("%Toast").get_global_rect().position.y >= hud.get_node("%MapTitle").get_global_rect().end.y, "revealing toast does not cover top information")
	hud.queue_free()
	await process_frame
	print("MORALE_HUD_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
