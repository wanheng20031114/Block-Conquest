extends SceneTree
## Native HUD only: no simulation, saved preferences, sound, or external input.
## -- <output-directory> additionally captures the same cases on a GPU viewport.

var hud: CanvasLayer
var balance: Control
var checks: int = 0
var failures: Array[String] = []
var output: String = ""
const SKILL_RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const COMMANDERS: Array[StringName] = [&"squirrel", &"rabbit", &"bear", &"frog", &"fox", &"squirrel"]

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL ", label)

func sample(totals: Array, morale: Array, local_faction: int = 0) -> Dictionary:
	var state := {"commander": COMMANDERS[local_faction], "enemy_commander": COMMANDERS[1 - local_faction % 2], "player_total": 0, "enemy_total": 0,
		"local_faction": local_faction, "faction_commanders": [], "faction_skill_statuses": [], "faction_skill_active": [], "faction_names": [],
		"faction_totals": totals, "morale_stars": morale, "faction_count": totals.size(),
		"map_title": "裂谷交汇", "map_mode": "%dv%d" % [totals.size() / 2, totals.size() / 2], "team_size": totals.size() / 2,
		"time": 126, "percentage": 50, "forges": 0, "selected_owned": false, "selected_level": 0,
		"selected_available_population": 0, "upgrade_cost": 10, "selected_max_level": 4, "construction_remaining": 0.0,
		"conversion_target": -1, "selected_kind": -1, "selected_detail": "", "can_upgrade": false, "convert_cost": 20,
		"armed_skill": -1, "energy": 60.0, "cooldowns": [0.0, 0.0, 0.0, 0.0], "skill_durations": [0.0, 0.0, 0.0, 0.0],
		"energy_costs": [30, 30, 35, 70], "energy_max": 100.0, "energy_regen": 2.0, "energy_tower_count": 0}
	for faction: int in totals.size():
		state["player_total" if faction % 2 == local_faction % 2 else "enemy_total"] += int(totals[faction])
		state.faction_commanders.append(COMMANDERS[faction])
		state.faction_skill_statuses.append([faction % 3, (faction + 1) % 3, (faction + 2) % 3, 2])
		state.faction_skill_active.append(true)
		state.faction_names.append(FACTIONS.NAMES[faction])
	return state

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func verify_public_totals(state: Dictionary, label: String) -> void:
	check(hud.get_node("%PlayerTotal").text == str(state.player_total), label + " exact allied total")
	check(hud.get_node("%EnemyTotal").text == str(state.enemy_total), label + " exact public opposing total")
	var shown_rects: Array[Rect2] = []
	for faction: int in 6:
		var total: Label = balance.get_node("Totals/Faction%d" % faction)
		check(total.visible == (state.faction_count > 2 and faction < state.faction_count), label + " individual total visibility %d" % faction)
		if not total.visible:
			continue
		check(total.text == str(state.faction_totals[faction]), label + " exact individual total including zero %d" % faction)
		var rect := total.get_global_rect()
		var stars: Rect2 = balance.get_node("Stars/Faction%d" % faction).get_global_rect()
		var bar: Rect2 = balance.get_global_rect()
		check(absf(rect.get_center().x - stars.get_center().x) < 0.1 and rect.end.y <= stars.position.y, label + " number centered above matching morale %d" % faction)
		check(rect.position.x >= bar.position.x - 0.1 and rect.end.x <= bar.end.x + 0.1, label + " number fits balance width %d" % faction)
		check(total.mouse_filter == Control.MOUSE_FILTER_IGNORE and not hud.is_pointer_blocked(rect.get_center()), label + " number preserves battlefield input %d" % faction)
		for previous: Rect2 in shown_rects:
			check(not rect.intersects(previous), label + " individual totals never overlap %d" % faction)
		shown_rects.append(rect)

func verify_skill_row(row: Control, commander: StringName, statuses: Array, active: bool, label: String) -> void:
	check(row.get_child_count() == 4, label + " four authored skill slots")
	check(row.find_children("*", "Label", true, false).is_empty() and row.find_children("*", "Range", true, false).is_empty(), label + " public row contains no numeric or proportional cooldown controls")
	var icons := SKILL_RULES.icons_for(commander)
	var names := SKILL_RULES.names_for(commander)
	for index: int in 4:
		var slot: Control = row.get_child(index)
		var icon: TextureRect = slot.get_node("Icon")
		var status: int = statuses[index]
		check(icon.texture == icons[index] and icon.visible, label + " correct complete icon %d" % index)
		check(slot.get_node("Cooling").visible == (status == 0), label + " cooling mask %d" % index)
		check(slot.get_node("ReadyLight").visible == (status == 2 and active), label + " glow requires cooldown and energy %d" % index)
		check(is_equal_approx(icon.modulate.a, 0.38 if status == 0 else 1.0), label + " insufficient energy retains full icon %d" % index)
		var status_text: String = ["冷却中", "冷却完成 · 技力不足", "可以施放"][status] if active else "当前无法施放"
		check(slot.tooltip_text.ends_with(" · " + names[index] + "\n" + status_text), label + " tooltip reveals only skill and categorical status %d" % index)
		check(slot.mouse_filter == Control.MOUSE_FILTER_PASS and not hud.is_pointer_blocked(slot.get_global_rect().get_center()), label + " skill hover preserves battlefield input %d" % index)
		for child: Control in slot.get_children():
			check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, label + " decorative controls ignore input %d/%s" % [index, child.name])

func verify_public_skills() -> void:
	var enemy_row: Control = hud.get_node("UI/Enemy/Skills")
	for commander: StringName in SKILL_RULES.PORTRAITS:
		for statuses: Array in [[2, 2, 2, 2], [0, 1, 2, 0], [1, 2, 0, 1], [2, 0, 1, 2]]:
			var state := sample([100, 100], [1.5, 2.75])
			state.faction_commanders[1] = commander
			state.faction_skill_statuses[1] = statuses
			hud.update_state(state)
			verify_skill_row(enemy_row, commander, statuses, true, "duel %s %s" % [commander, str(statuses)])
	var inactive := sample([100, 100], [1.5, 2.75])
	inactive.faction_skill_statuses[1] = [2, 2, 2, 2]
	inactive.faction_skill_active[1] = false
	hud.update_state(inactive)
	verify_skill_row(enemy_row, &"rabbit", [2, 2, 2, 2], false, "surrender or pause removes all ready lights")
	inactive.faction_skill_active[1] = true
	hud.update_state(inactive)
	verify_skill_row(enemy_row, &"rabbit", [2, 2, 2, 2], true, "resume restores all ready lights")
	for local_faction: int in 2:
		var state := sample([111, 257], [1.5, 2.75], local_faction)
		state.online = true
		state.faction_names = ["测试玩家甲", "测试玩家乙"]
		hud.update_state(state)
		verify_public_totals(state, "duel local seat %d" % local_faction)
		check(enemy_row.visible and not hud.get_node("UI/Enemy/Role").visible, "duel replaces role text with skill row")
		check(hud.get_node("UI/Enemy/Name").text == state.faction_names[1 - local_faction], "duel maps opposite online seat name %d" % local_faction)
		verify_skill_row(enemy_row, state.faction_commanders[1 - local_faction], state.faction_skill_statuses[1 - local_faction], true, "duel local seat %d" % local_faction)
		for faction: int in 6:
			check(not balance.get_node("Skills/Faction%d" % faction).visible, "duel hides top skill rows %d" % faction)
	await capture("08_duel_public_skills")
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		for count: int in [4, 6]:
			for local_faction: int in count:
				var totals: Array = [0, 900, 2, 8, 1, 500].slice(0, count)
				var state := sample(totals, [1.5, 2.75, 0.0, 4.1, 5.0, 3.25].slice(0, count), local_faction)
				state.online = local_faction % 2 == 1
				hud.update_state(state)
				await create_timer(0.3).timeout
				var label := "%dx%d %d seats local %d" % [dimensions.x, dimensions.y, count, local_faction]
				verify_public_totals(state, label)
				check(not enemy_row.visible and hud.get_node("UI/Enemy/Role").visible, label + " alliance summary shows no misleading skill row")
				var shown_rects: Array[Rect2] = []
				for faction: int in 6:
					var row: Control = balance.get_node("Skills/Faction%d" % faction)
					check(row.visible == (faction < count and faction != local_faction), label + " exact other-player visibility %d" % faction)
					if not row.visible:
						continue
					verify_skill_row(row, state.faction_commanders[faction], state.faction_skill_statuses[faction], true, label + " faction %d" % faction)
					var rect: Rect2 = row.get_global_rect()
					var stars: Rect2 = balance.get_node("Stars/Faction%d" % faction).get_global_rect()
					var bar: Rect2 = balance.get_global_rect()
					check(absf(rect.position.x - stars.position.x) < 0.1 and rect.position.y >= stars.end.y, label + " skill row directly below matching morale %d" % faction)
					check(rect.position.x >= bar.position.x - 0.1 and rect.end.x <= bar.end.x + 0.1, label + " skill row fits balance width %d" % faction)
					check(rect.end.y <= hud.get_node("%Time").get_global_rect().position.y, label + " time stays below skill row %d" % faction)
					for previous: Rect2 in shown_rects:
						check(not rect.intersects(previous), label + " player skill rows never overlap %d" % faction)
					shown_rects.append(rect)
				if local_faction == count - 1:
					await capture("09_public_%dx%d_%d_players" % [dimensions.x, dimensions.y, count])
	# Returning to a duel must also remove stale multiplayer indicators.
	var duel := sample([100, 100], [0.0, 0.0])
	hud.update_state(duel)
	verify_public_totals(duel, "returning from team match restores duel totals")
	check(enemy_row.visible, "returning from team match restores duel skill row")
	for faction: int in 6:
		check(not balance.get_node("Skills/Faction%d" % faction).visible, "returning to duel clears stale top row %d" % faction)

func verify_permanent_bonuses() -> void:
	# Combat numbers now live in the optional debug panel. Their full rule/source
	# matrix is exercised against the actual simulation in debug_panel_test.
	check(not hud.has_node("UI/Player/ForgeBonus"), "portrait column no longer contains permanent combat text")
	check(not hud.has_node("UI/QuickHint"), "persistent shortcut text and its close button are removed")
	check(not hud.debug_visible(), "optional debug information starts hidden")

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
	var state := sample(totals, morale)
	hud.update_state(state)
	await create_timer(0.35).timeout
	verify_public_totals(state, label)
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
		check(not row.tooltip_text.contains("未知") and not row.tooltip_text.contains("据点占比"), label + " tooltip reflects public troop rule %d" % faction)
		check(row.mouse_filter == Control.MOUSE_FILTER_PASS and not hud.is_pointer_blocked(row.get_global_rect().get_center()), label + " morale hover preserves battlefield input %d" % faction)
		if population > 0.0:
			check(absf(segment.position.x - right) < 0.1 and absf(segment.size.x / balance.size.x - float(totals[faction]) / population) < 0.001, label + " exact public troop share %d" % faction)
		else:
			check(not segment.visible, label + " zero troops leaves neutral bar %d" % faction)
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
	check(hud.get_node("%Time").visible and hud.get_node("%Time").text == "02:06" and hud.get_node("%Time").get_global_rect().position.y > stars_bottom, "match time remains visible and updates below all stars")
	hud.notify("气势提升")
	check(hud.get_node("%Toast").get_global_rect().position.y >= hud.get_node("%Time").get_global_rect().end.y, "revealing toast does not cover match time")
	await verify_public_skills()
	hud.queue_free()
	await process_frame
	print("MORALE_HUD_RESULTS ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
