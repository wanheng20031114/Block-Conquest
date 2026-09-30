extends SceneTree
## Native input exercises the read-only field guide and saves review images.
## Run with tools/run_godot_private_desktop.py; argv[0] is the output folder.
## The test never applies or saves preferences and never starts a match.

const LOBBY := "res://scenes/lobby.tscn"
const CODEX := "res://scenes/codex/codex.tscn"
const CATALOG := preload("res://scripts/codex/codex_catalog.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const RESOLUTION := Vector2i(1280, 720)

var checks: int = 0
var failures: Array[String] = []
var output_directory: String
var session: Node
var original_preferences: Dictionary
var original_selection: Array
var captures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL CODEX_TEST ", label)
	return condition


func _control(name: String) -> Control:
	return current_scene.get_node("%" + name)


func _frames(count: int = 10) -> void:
	for frame: int in count:
		await RenderingServer.frame_post_draw


func _settle() -> void:
	while session.transition.busy:
		await process_frame
	await _frames()


func _move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event, true)


func _click_at(at: Vector2) -> void:
	_move(at)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)


func _click(name: String) -> void:
	_click_at(_control(name).get_global_rect().get_center())


func _key(code: Key, ctrl: bool = false, unicode: int = 0) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.ctrl_pressed = ctrl
		event.unicode = unicode
		event.pressed = down
		root.push_input(event, true)


func _search(query: String) -> void:
	_click("Search")
	_key(KEY_A, true)
	_key(KEY_BACKSPACE)
	for character: String in query:
		_key(KEY_NONE, false, character.unicode_at(0))
	await _frames(10)
	_check(_control("Search").text == query, "native search input: " + query)


func _hero_row(index: int) -> void:
	var entries: ItemList = _control("Entries")
	var item: Rect2 = entries.get_item_rect(index)
	_click_at(entries.get_global_transform() * item.get_center())
	await _frames(10)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot.get_size() == RESOLUTION, name + " renders at 1280 by 720")
	_check(screenshot.save_png(output_directory.path_join(name + ".png")) == OK, name + " screenshot saves")
	captures += 1


func _fits(name: String, context: String) -> void:
	var control: Control = _control(name)
	var visible_bounds: Rect2 = current_scene.get_global_rect()
	_check(visible_bounds.grow(1.0).encloses(control.get_global_rect()), context + ": " + name + " fits the logical viewport")


func _label_fits(name: String, context: String) -> void:
	var label: Label = _control(name)
	_check(not label.text.is_empty(), context + ": " + name + " has text")
	_check(label.get_visible_line_count() >= label.get_line_count(), context + ": " + name + " has no clipped lines")
	_check(label.size.x + 1.0 >= label.get_minimum_size().x, context + ": " + name + " fits horizontally")


func _hero_layout(context: String) -> void:
	for name: String in ["Book", "PageContent", "HeroPage", "Entries", "Search", "Back", "Demo", "Pause", "Replay"]:
		_fits(name, context)
	for name: String in ["DetailTitle", "DetailSummary", "HeroRole", "HeroNote", "SkillTitle", "SkillStats", "SkillTarget", "SkillDescription"]:
		_label_fits(name, context)


func _guide_layout(entry: Dictionary) -> void:
	var context: String = entry.title
	for name: String in ["Book", "PageContent", "GuidePage", "GuideScroll", "GuideTip"]:
		_fits(name, context)
	for name: String in ["DetailSummary", "GuideTag", "GuideTip"]:
		_label_fits(name, context)
	for index: int in 3:
		var section: Control = _control("Section%d" % index)
		_check(section.visible == (index < entry.sections.size()), context + ": section visibility follows the selected entry")
		if section.visible:
			_label_fits("SectionTitle%d" % index, context)
			_label_fits("SectionBody%d" % index, context)
	var group: Control = _control("GuideTableGroup")
	_check(group.visible == entry.has("table"), context + ": only tabular guides display the table group")
	if not entry.has("table"):
		_check(not _control("GuideTable").is_visible_in_tree(), context + ": ordinary guides hide the previous table")
		return
	var table: RichTextLabel = _control("GuideTable")
	_check(table.is_visible_in_tree() and table.bbcode_enabled and table.fit_content and not table.scroll_active, context + ": table uses the authored native rich text label within the guide scroll")
	_fits("GuideTableGroup", context)
	_check(table.get_content_height() <= table.size.y + 1.0 and table.get_content_width() <= table.size.x + 1.0, context + ": table rows and columns fit without internal clipping")
	_check(table.get_content_width() >= table.size.x - 2.0, context + ": table columns fill the available guide width")
	var cells: Array = entry.table.headers.duplicate()
	for row: Array in entry.table.rows:
		cells.append_array(row)
	var parsed := table.get_parsed_text()
	var cursor := 0
	var complete := true
	for cell: Variant in cells:
		var value := str(cell)
		var at := parsed.find(value, cursor)
		if at < 0:
			complete = false
			break
		cursor = at + value.length()
	_check(complete, context + ": rendered headers and cells retain their catalogue row order")


func _selection() -> Array:
	return [session.block_war_commander, session.block_war_opponent_commander, session.block_war_map_id]


func _finish() -> void:
	_check(_selection() == original_selection, "browsing preserves the selected commanders and map")
	_check(session.settings.snapshot() == original_preferences, "browsing never applies or saves preferences")
	print("CODEX_TEST ", JSON.stringify({"checks": checks, "failures": failures, "captures": captures, "output": output_directory}))
	quit(0 if failures.is_empty() else 1)


func _run() -> void:
	create_timer(110.0, true, false, true).timeout.connect(func():
		printerr("FAIL CODEX_TEST timeout")
		quit(3))
	var arguments := OS.get_cmdline_user_args()
	if not _check(not arguments.is_empty(), "output directory argument is present"):
		quit(1)
		return
	output_directory = ProjectSettings.globalize_path(arguments[0])
	if not _check(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "output directory can be created"):
		quit(1)
		return
	root.size = RESOLUTION
	session = root.get_node("Session")
	original_preferences = session.settings.snapshot()
	original_selection = _selection()
	if not _check(change_scene_to_file(LOBBY) == OK, "lobby loads"):
		_finish()
		return
	await scene_changed
	await _settle()
	_check(_control("Codex").is_visible_in_tree() and not _control("Codex").disabled, "codex is available on the main menu")
	_fits("Codex", "lobby")
	await _capture("00_lobby")
	_click("Codex")
	await scene_changed
	await _settle()
	if not _check(current_scene.scene_file_path == CODEX, "native menu click opens the codex"):
		_finish()
		return
	_check(_control("Entries").item_count == 6, "all six heroes are unlocked from first visit")
	_check(current_scene.category == 0 and _control("Heroes").button_pressed, "hero category is selected initially")

	for row: int in CATALOG.HEROES.size():
		var id: StringName = CATALOG.HEROES[row]
		await _hero_row(row)
		_check(current_scene.commander == id, "native hero selection: " + str(id))
		_check(_control("Portrait").texture == RULES.PORTRAITS[id], str(id) + " uses the existing commander portrait")
		for index: int in 4:
			_click("Skill%d" % index)
			await _frames(80)
			var context := "%s skill %d" % [id, index + 1]
			_check(current_scene.skill_index == index and _control("Skill%d" % index).button_pressed, context + " selected through native input")
			_check(_control("SkillTitle").text == RULES.names_for(id)[index], context + " name matches battle rules")
			_check(_control("SkillStats").text == "%d 技力    ·    %d 秒冷却" % [RULES.costs_for(id)[index], RULES.cooldowns_for(id)[index]], context + " energy and cooldown match battle rules")
			_check(_control("SkillDescription").text == CATALOG.skill_summary(id, index), context + " description matches the catalogue")
			_check(_control("Demo").playing, context + " demo runs")
			_check(_control("Demo").commander == id and _control("Demo").skill_index == index, context + " battlefield matches the displayed skill")
			_check(_control("Demo").world.cast_succeeded, context + " actual battle rules accept the scheduled skill")
			_check(_control("Demo").viewport.own_world_3d and _control("Demo").world.network_match == null, context + " native battlefield remains isolated")
			_hero_layout(context)
			await _capture("hero_%s_%d" % [id, index + 1])

	var demo: Control = _control("Demo")
	_click("Pause")
	_check(not demo.playing, "pause button stops the demonstration")
	var paused_progress: float = demo.progress
	var paused_positions: Array[Vector3] = []
	for unit: WarMarches.MarchUnit in demo.world.marches._units:
		paused_positions.append(unit.position)
	await _frames(12)
	_check(is_equal_approx(demo.progress, paused_progress), "paused demonstration does not advance")
	var current_positions: Array[Vector3] = []
	for unit: WarMarches.MarchUnit in demo.world.marches._units:
		current_positions.append(unit.position)
	_check(current_positions == paused_positions, "paused demonstration keeps every soldier in place")
	_click("Skill1")
	await _frames(10)
	_check(not demo.playing, "changing skills preserves paused playback")
	_click("Replay")
	_check(demo.playing, "replay resumes paused playback")
	_check(is_zero_approx(demo.progress), "replay resets the demonstration to its beginning")
	var replay_progress: float = demo.progress
	await _frames(4)
	_check(demo.progress > replay_progress, "replayed demonstration advances from its beginning")
	await _capture("demo_replay")

	await _search("兔洞")
	_check(_control("Entries").item_count == 1 and current_scene.commander == &"rabbit", "search finds a hero through a skill name")
	_check(_control("PageContent").visible and not _control("Empty").visible, "matching search displays the selected article")
	await _search("不存在的图鉴条目")
	_check(_control("Entries").item_count == 0 and _control("Empty").visible and not _control("PageContent").visible, "unmatched search displays the empty state")
	_check(not demo.playing, "empty results stop the hidden demonstration")
	await _capture("search_empty")
	await _search("")
	_check(_control("Entries").item_count == CATALOG.HEROES.size() and demo.playing, "clearing search restores all heroes and playback")

	_click("Guides")
	await _frames(10)
	var guides: Array[Dictionary] = CATALOG.guides()
	_check(current_scene.category == 1 and _control("Entries").item_count == guides.size(), "all mechanics are available in the guide category")
	_check(_control("GuidePage").is_visible_in_tree() and not demo.is_visible_in_tree() and not demo.playing, "guide category hides and pauses the skill stage")
	_control("Entries").grab_focus()
	for step: int in guides.size() - 1:
		_key(KEY_DOWN)
	await _frames(2)
	_check(current_scene.guide_index == guides.size() - 1, "native keyboard navigation reaches the last mechanic")
	for step: int in guides.size() - 1:
		_key(KEY_UP)
	await _frames(2)
	_check(current_scene.guide_index == 0, "native keyboard navigation returns to the first mechanic")
	var guide_progress: float = demo.progress
	await _frames(8)
	_check(is_equal_approx(demo.progress, guide_progress), "hidden skill stage remains stopped while reading mechanics")
	for index: int in guides.size():
		var entry: Dictionary = guides[index]
		await _search(entry.title)
		# Titles also match other guides' tags and summaries. Select the exact
		# result through native input instead of requiring a unique search hit.
		var entries: ItemList = _control("Entries")
		var matching_row := -1
		for row: int in entries.item_count:
			if entries.get_item_text(row) == entry.title:
				matching_row = row
		if not _check(matching_row >= 0, "mechanic appears in search results: " + entry.title):
			continue
		await _hero_row(matching_row)
		_check(current_scene.guide_index == index, "native result selection opens the searched mechanic: " + entry.title)
		_check(_control("DetailTitle").text == entry.title, "correct mechanic is displayed: " + entry.title)
		_guide_layout(entry)
		await _capture("guide_%02d_%s" % [index + 1, entry.id])

	_click("Heroes")
	await _frames(10)
	var page_origin: Vector2 = _control("PageContent").position
	var info_origin: Vector2 = _control("SkillInfo").position
	for round_index: int in 12:
		_click("Skill%d" % (round_index % 4))
		_click("Guides")
		_click("Heroes")
		await _frames(1)
	_move(Vector2(10, 10))
	await _frames(12)
	_check(_control("PageContent").position.is_equal_approx(page_origin) and _control("PageContent").scale.is_equal_approx(Vector2.ONE), "interrupted page reveals restore their original transform")
	_check(_control("SkillInfo").position.is_equal_approx(info_origin) and _control("SkillInfo").scale.is_equal_approx(Vector2.ONE), "rapid skill changes do not accumulate displacement or scale")
	_check(is_equal_approx(_control("PageContent").modulate.a, 1.0) and is_equal_approx(_control("SkillInfo").modulate.a, 1.0), "interrupted reveals finish fully opaque")
	_hero_layout("rapid category switching")
	_check(_selection() == original_selection, "all catalogue operations are read-only")

	_key(KEY_ESCAPE)
	await scene_changed
	await _settle()
	_check(current_scene.scene_file_path == LOBBY and _control("Codex").has_focus(), "Esc returns to the lobby and restores codex focus")
	_click("Codex")
	await scene_changed
	await _settle()
	_click("Back")
	await scene_changed
	await _settle()
	_check(current_scene.scene_file_path == LOBBY and _control("Codex").has_focus(), "native Back button also restores main-menu focus")
	_finish()
