extends Control

const CATALOG := preload("res://scripts/block_war/war_map_catalog.gd")
const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const COMMANDERS: Array[StringName] = [&"squirrel", &"rabbit"]
var selected: Resource
var _maps: Array[Resource] = []
var _launching := false
@onready var session: Node = get_node("/root/Session")

func _ready() -> void:
	get_tree().auto_accept_quit = true
	for index: int in 3:
		get_node("%%Size%d" % index).pressed.connect(_select_size.bind(index))
	for index: int in 2:
		get_node("%%Map%d" % index).pressed.connect(_select_map.bind(index))
	%Start.pressed.connect(_start)
	%Back.pressed.connect(func(): session.back_to_lobby())
	for index: int in 2:
		get_node("%%PlayerCommander%d" % index).pressed.connect(_select_commander.bind(index, false))
		get_node("%%OpponentCommander%d" % index).pressed.connect(_select_commander.bind(index, true))
		for side: String in ["Player", "Opponent"]:
			get_node("%%%sCommander%d" % [side, index]).tooltip_text = " · ".join(RULES.names_for(COMMANDERS[index]))
	_select_commander(COMMANDERS.find(session.block_war_commander), false)
	_select_commander(COMMANDERS.find(session.block_war_opponent_commander), true)
	selected = CATALOG.find_map(session.block_war_map_id)
	_select_size(selected.size_class)
	UIMotion.bind_buttons(self)

func _select_commander(index: int, opponent: bool) -> void:
	if opponent:
		session.block_war_opponent_commander = COMMANDERS[index]
	else:
		session.block_war_commander = COMMANDERS[index]
	for i: int in 2:
		get_node("%%%sCommander%d" % ["Opponent" if opponent else "Player", i]).set_pressed_no_signal(i == index)

func _select_size(size_class: int) -> void:
	_maps.clear()
	for definition: Resource in CATALOG.MAPS:
		if definition.size_class == size_class:
			_maps.append(definition)
	for index: int in 3:
		get_node("%%Size%d" % index).set_pressed_no_signal(index == size_class)
	var selected_index := maxi(0, _maps.find(selected))
	for index: int in 2:
		var button: Button = get_node("%%Map%d" % index)
		button.text = _maps[index].title
	_select_map(selected_index)

func _select_map(index: int) -> void:
	selected = _maps[index]
	for i: int in 2:
		get_node("%%Map%d" % i).set_pressed_no_signal(i == index)
	%MapName.text = selected.title
	%MapInfo.text = "%s型战场   ·   %s   ·   %d × %d 米   ·   %d 座据点" % [["小", "中", "大"][selected.size_class], selected.mode_label(), selected.half_size.x * 2, selected.half_size.y * 2, selected.building_positions.size()]
	%Description.text = selected.description
	%Teams.text = "你对战 1 名电脑" if selected.team_size == 1 else "你 + %d 名电脑盟友，对战 %d 名电脑\n增援抵达队友建筑后，交由队友指挥。" % [selected.team_size - 1, selected.team_size]
	%Start.text = "开始 %s 对局" % selected.mode_label()
	%Preview.show_map(selected)

func _start() -> void:
	if _launching or session.transition.busy:
		return
	_launching = true
	%Start.disabled = true
	session.block_war_map_id = selected.map_id
	if session.change_scene("res://scenes/block_war/block_war.tscn") != OK:
		_launching = false
		%Start.disabled = false
		%Teams.text = "地图载入失败，请检查游戏文件后重试。"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _launching:
		session.back_to_lobby()
		get_viewport().set_input_as_handled()
