extends Control

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const COMMANDERS: Array[StringName] = [&"squirrel", &"rabbit", &"bear", &"frog"]
var selected: Resource
var _maps: Array[Resource] = []
var _launching := false
@onready var session: Node = get_node("/root/Session")
@onready var _map_buttons: Array[Button] = [%Map0, %Map1, %Map2]

func _ready() -> void:
	get_tree().auto_accept_quit = true
	for index: int in 3:
		get_node("%%Size%d" % index).pressed.connect(_select_size.bind(index))
	for index: int in _map_buttons.size():
		_map_buttons[index].pressed.connect(_select_map.bind(index))
	%Start.pressed.connect(_start)
	%Back.pressed.connect(_back)
	%Settings.pressed.connect(session.settings.open_menu)
	%Preview.inspected.connect(func(text: String): %Inspection.text = text)
	for index: int in COMMANDERS.size():
		get_node("%%OpponentCommander%d" % index).pressed.connect(_select_commander.bind(index))
		get_node("%%OpponentCommander%d" % index).tooltip_text = " · ".join(RULES.names_for(COMMANDERS[index]))
	_select_commander(COMMANDERS.find(session.block_war_opponent_commander))
	%PlayerPortrait.texture = RULES.PORTRAITS[session.block_war_commander]
	%PlayerName.text = "%s已准备好" % RULES.name_for(session.block_war_commander)
	selected = CATALOG.find_map(session.block_war_map_id)
	_select_size(selected.size_class)
	UIMotion.bind_menu_buttons(self)
	session.get_node("UIFeedback").bind_buttons(self)

func _select_commander(index: int) -> void:
	session.block_war_opponent_commander = COMMANDERS[index]
	for i: int in COMMANDERS.size():
		get_node("%%OpponentCommander%d" % i).set_pressed_no_signal(i == index)

func _select_size(size_class: int) -> void:
	_maps.clear()
	for definition: Resource in CATALOG.MAPS:
		if definition.size_class == size_class:
			_maps.append(definition)
	for index: int in 3:
		get_node("%%Size%d" % index).set_pressed_no_signal(index == size_class)
	var selected_index := maxi(0, _maps.find(selected))
	assert(_maps.size() == _map_buttons.size(), "Each battlefield size has one authored button per map.")
	for index: int in _map_buttons.size():
		var button: Button = _map_buttons[index]
		button.text = _maps[index].title
		button.tooltip_text = _maps[index].description
	_select_map(selected_index)

func _select_map(index: int) -> void:
	var changed: bool = selected != _maps[index]
	selected = _maps[index]
	session.block_war_map_id = selected.map_id
	for i: int in _map_buttons.size():
		_map_buttons[i].set_pressed_no_signal(i == index)
	%MapName.text = selected.title
	%MapNumber.text = "%02d / %02d" % [CATALOG.MAPS.find(selected) + 1, CATALOG.MAPS.size()]
	%MapInfo.text = "%s   ·   %d × %d 米   ·   %d 座据点" % [selected.mode_label(), selected.half_size.x * 2, selected.half_size.y * 2, selected.building_positions.size()]
	var terrain: Array[String] = []
	if not selected.water_regions.is_empty():
		terrain.append("水域迂回")
	if not selected.mountain_regions.is_empty():
		terrain.append("山地隘口")
	if not selected.bridges.is_empty():
		terrain.append("桥梁连接")
	if not selected.height_zones.is_empty():
		terrain.append("高地土坡")
	%TerrainInfo.text = " · ".join(terrain)
	var spawns: Array[String] = ["① 你", "② 敌方一"]
	if selected.team_size >= 2:
		spawns.append("③ 盟友一")
		spawns.append("④ 敌方二")
	if selected.team_size >= 3:
		spawns.append("⑤ 盟友二")
		spawns.append("⑥ 敌方三")
	%SpawnLegend.text = "   ".join(spawns)
	%Description.text = selected.description
	%Teams.text = "你对战 1 名电脑" if selected.team_size == 1 else "你 + %d 名电脑盟友，对战 %d 名电脑\n增援抵达队友建筑后，交由队友指挥。" % [selected.team_size - 1, selected.team_size]
	%Start.text = "开始 %s 对局   →" % selected.mode_label()
	%Preview.show_map(selected)
	if changed:
		_animate_map_change()

func _animate_map_change() -> void:
	# Keep the selection controls in place while the new terrain and facts appear.
	UIMotion.reveal_menu(%Preview, Vector2.ZERO)
	UIMotion.reveal_menu($Margin/Column/Content/Overview/OverviewColumn/MapHeader, Vector2.ZERO)
	UIMotion.reveal_menu(%MapInfo, Vector2.ZERO, 0.025)
	UIMotion.reveal_menu(%TerrainInfo, Vector2.ZERO, 0.035)
	UIMotion.reveal_menu(%Description, Vector2.ZERO, 0.055)
	UIMotion.reveal_menu(%SpawnLegend, Vector2.ZERO, 0.075)
	UIMotion.reveal_menu(%Teams, Vector2.ZERO, 0.075)

func _start() -> void:
	if _launching or session.transition.busy or session.settings.is_open():
		return
	_launching = true
	%Start.disabled = true
	session.block_war_map_id = selected.map_id
	if session.change_scene("res://scenes/block_war/block_war.tscn") != OK:
		_launching = false
		%Start.disabled = false
		%Teams.text = "地图载入失败，请检查游戏文件后重试。"

func _back() -> void:
	if not _launching and not session.transition.busy:
		session.change_scene("res://scenes/block_war/commander_select.tscn")

func _unhandled_key_input(event: InputEvent) -> void:
	if session.settings.is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
