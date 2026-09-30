extends Control
## A read-only field guide. All nodes are authored in codex.tscn.

const CATALOG := preload("res://scripts/codex/codex_catalog.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
var category: int = 0
var commander: StringName = &"squirrel"
var skill_index: int = 0
var guide_index: int = 0
var _guides: Array[Dictionary] = []
var _entries: Array[int] = []
var _paused: bool = false
@onready var session: Node = get_node("/root/Session")

func _ready() -> void:
	_guides = CATALOG.guides()
	%Heroes.pressed.connect(_set_category.bind(0))
	%Guides.pressed.connect(_set_category.bind(1))
	%Search.text_changed.connect(_filter_entries)
	%Entries.item_selected.connect(_select_entry)
	%Back.pressed.connect(_back)
	%Pause.pressed.connect(_toggle_pause)
	%Replay.pressed.connect(_replay)
	for index: int in 4:
		get_node("%%Skill%d" % index).pressed.connect(_select_skill.bind(index))
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)
	_set_category(0)
	%Entries.grab_focus(true)

func _set_category(value: int) -> void:
	category = value
	%Entries.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if value == 0 else CanvasItem.TEXTURE_FILTER_LINEAR
	%Heroes.set_pressed_no_signal(value == 0)
	%Guides.set_pressed_no_signal(value == 1)
	%Search.text = ""
	%IndexTitle.text = "指挥官名录" if value == 0 else "战场指南"
	%HeroPage.visible = value == 0
	%GuidePage.visible = value == 1
	%Demo.set_playing(value == 0 and not _paused)
	_filter_entries("")

func _filter_entries(query: String) -> void:
	%Entries.clear()
	_entries.clear()
	var selected: int = CATALOG.HEROES.find(commander) if category == 0 else guide_index
	var count: int = CATALOG.HEROES.size() if category == 0 else _guides.size()
	for index: int in count:
		var title: String
		var keywords: String
		var icon: Texture2D
		if category == 0:
			var id: StringName = CATALOG.HEROES[index]
			var profile: Dictionary = CATALOG.hero_profile(id)
			title = profile.title
			keywords = title + profile.subtitle + " ".join(RULES.names_for(id))
			icon = RULES.PORTRAITS[id]
		else:
			title = _guides[index].title
			keywords = title + _guides[index].tag + _guides[index].summary
			icon = _guides[index].icon
		if not query.strip_edges().is_empty() and not keywords.containsn(query.strip_edges()):
			continue
		_entries.append(index)
		%Entries.add_item(title, icon)
	%Empty.visible = _entries.is_empty()
	%PageContent.visible = not _entries.is_empty()
	if _entries.is_empty():
		%Demo.set_playing(false)
		%PageNumber.text = "未找到条目"
		return
	var row: int = _entries.find(selected)
	if row < 0:
		row = 0
	%Entries.select(row)
	%Entries.ensure_current_is_visible()
	_select_entry(row)

func _select_entry(row: int) -> void:
	var index: int = _entries[row]
	if category == 0:
		var next: StringName = CATALOG.HEROES[index]
		if next != commander:
			skill_index = 0
		commander = next
		_show_hero()
	else:
		guide_index = index
		_show_guide()
	%PageNumber.text = "%02d / %02d" % [row + 1, _entries.size()]
	UIMotion.reveal_menu(%PageContent, Vector2.ZERO)

func _show_hero() -> void:
	var profile: Dictionary = CATALOG.hero_profile(commander)
	%DetailTag.text = "英雄图鉴   /   " + profile.subtitle
	%DetailTitle.text = profile.title
	%DetailSummary.text = profile.summary
	%Portrait.texture = RULES.PORTRAITS[commander]
	%HeroRole.text = profile.subtitle
	%HeroNote.text = profile.note
	for index: int in 4:
		var button: Button = get_node("%%Skill%d" % index)
		button.text = RULES.names_for(commander)[index]
		button.icon = RULES.icons_for(commander)[index]
	_select_skill(skill_index, false)

func _select_skill(index: int, animate: bool = true) -> void:
	skill_index = index
	for i: int in 4:
		get_node("%%Skill%d" % i).set_pressed_no_signal(i == index)
	%SkillTitle.text = RULES.names_for(commander)[index]
	%SkillStats.text = "%d 技力    ·    %d 秒冷却" % [RULES.costs_for(commander)[index], RULES.cooldowns_for(commander)[index]]
	%SkillTarget.text = "目标  " + CATALOG.skill_target(commander, index)
	%SkillDescription.text = CATALOG.skill_summary(commander, index)
	%Demo.configure(commander, index)
	%Demo.set_playing(not _paused)
	if animate:
		UIMotion.reveal_menu(%SkillInfo, Vector2.ZERO)

func _show_guide() -> void:
	var entry: Dictionary = _guides[guide_index]
	%DetailTag.text = "战场指南   /   " + entry.tag
	%DetailTitle.text = entry.title
	%DetailSummary.text = entry.summary
	%GuideIcon.texture = entry.icon
	%GuideTag.text = entry.tag
	%GuideTip.text = entry.tip
	%GuideTableGroup.visible = entry.has("table")
	%GuideTable.text = _guide_table_text(entry.table) if entry.has("table") else ""
	for index: int in 3:
		var section: Control = get_node("%%Section%d" % index)
		section.visible = index < entry.sections.size()
		if section.visible:
			get_node("%%SectionTitle%d" % index).text = entry.sections[index].title
			get_node("%%SectionBody%d" % index).text = entry.sections[index].body
	%GuideScroll.scroll_vertical = 0
	%Demo.set_playing(false)

func _guide_table_text(table: Dictionary) -> String:
	var cells: PackedStringArray = []
	# Keep column expansion on every cell; native shrink would return it to text width.
	for header: String in table.headers:
		var lines := header.split("\n")
		var text := "[font_size=20]%s[/font_size]" % lines[0]
		if lines.size() == 2:
			text += "\n[color=#697557][font_size=17]%s[/font_size][/color]" % lines[1]
		cells.append("[cell expand=1 shrink=false bg=#e2e6cc padding=10,16,10,16][center]%s[/center][/cell]" % text)
	for row_index: int in table.rows.size():
		var row: Array = table.rows[row_index]
		var background := "#f0eedb" if row_index % 2 == 0 else "#faf5e3"
		for column: int in row.size():
			var text: String = row[column]
			if column == 0:
				text = "[color=#405437]%s[/color]" % text
			cells.append("[cell expand=1 shrink=false bg=%s padding=10,17,10,17][center]%s[/center][/cell]" % [background, text])
	return "[table=%d]%s[/table]" % [table.headers.size(), "".join(cells)]

func _toggle_pause() -> void:
	_paused = not _paused
	%Pause.text = "继续演示" if _paused else "暂停演示"
	%Demo.set_playing(not _paused)

func _replay() -> void:
	_paused = false
	%Pause.text = "暂停演示"
	%Demo.set_playing(true)
	%Demo.replay()

func _back() -> void:
	if session.transition.busy:
		return
	%Demo.set_playing(false)
	session.set_meta("codex_return_focus", true)
	session.back_to_lobby()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
