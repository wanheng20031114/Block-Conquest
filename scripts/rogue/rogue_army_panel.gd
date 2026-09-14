class_name RogueArmyPanel
extends Control
## Selection is local UI state; every formation edit is one atomic session command.
signal closed

const GROUP_ROW := preload("res://scenes/rogue/army_group_row.tscn")
const ROW_IDLE := preload("res://assets/ui/medieval/styles/inset.tres")
const ROW_SELECTED := preload("res://assets/ui/medieval/styles/selection.tres")
var _encounter := "outpost"
var _selected_uids: Array[int] = []
var _rows: Dictionary = {}
var _refreshing := false

@onready var _rogue: Node = get_node("/root/Session/Rogue")
@onready var _board: RogueArmyBoard = %ArmyBoard

func _ready() -> void:
	%CloseArmy.pressed.connect(close_panel)
	%MapChoice.item_selected.connect(_on_map_selected)
	%DeployButton.pressed.connect(_transfer_selected.bind(false))
	%EnlistButton.pressed.connect(_transfer_selected.bind(true))
	%ApplyPosition.pressed.connect(_apply_position)
	%RotateLeft.pressed.connect(_rotate_selected.bind(-15.0))
	%RotateRight.pressed.connect(_rotate_selected.bind(15.0))
	_board.selection_changed.connect(_select_uids)
	_board.unit_activated.connect(func(uid: int) -> void: _transfer([uid], false))
	_board.layouts_requested.connect(_save_layouts)
	_rogue.changed.connect(_on_state_changed)
	UIMotion.bind_buttons(self)

func open_panel(_tab: String = "formation", encounter: String = "outpost") -> void:
	_encounter = encounter
	%MapChoice.select(1 if encounter == "siege" else 0)
	show()
	_refresh()
	_set_status("")
	UIMotion.reveal(self, Vector2.ZERO)
	%CloseArmy.grab_focus(true)

func close_panel() -> void:
	_board.cancel_gesture()
	hide()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event.is_action_pressed("ui_cancel"):
		if _board.has_gesture():
			_board.cancel_gesture()
		else:
			close_panel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if get_viewport().gui_get_focus_owner() is LineEdit: return
		if event.physical_keycode == KEY_Q or event.physical_keycode == KEY_E:
			_rotate_selected(-15 if event.physical_keycode == KEY_Q else 15)
			get_viewport().set_input_as_handled()

func _on_state_changed() -> void:
	if is_visible_in_tree() and not _refreshing: _refresh()

func _refresh() -> void:
	_refreshing = true
	_selected_uids = _selected_uids.filter(func(uid: int) -> bool: return not _unit_by_uid(uid).is_empty())
	%PopulationValue.text = "%d / %d" % [_rogue.state.population(), _rogue.state.population_cap()]
	_refresh_roster()
	_refresh_unit_details()
	_refreshing = false

func _refresh_roster() -> void:
	var groups: Dictionary = {}
	var deployed_count := 0
	var reserve_count := 0
	for unit: Dictionary in _rogue.state.data.roster:
		var key := ("out:" if unit.deployed else "reserve:") + str(unit.kind)
		if not groups.has(key): groups[key] = {"kind": str(unit.kind), "deployed": bool(unit.deployed), "uids": []}
		groups[key].uids.append(int(unit.uid))
		if unit.deployed: deployed_count += 1
		else: reserve_count += 1
	%DeployedCaption.text = "出战军队  ·  %d" % deployed_count
	%ReserveCaption.text = "待命区  ·  %d" % reserve_count
	%DeployedEmpty.visible = deployed_count == 0
	%ReserveEmpty.visible = reserve_count == 0
	%DeployedScroll.size_flags_stretch_ratio = maxf(2.0, groups.values().filter(func(group: Dictionary) -> bool: return group.deployed).size())
	%ReserveScroll.size_flags_stretch_ratio = maxf(1.0, groups.values().filter(func(group: Dictionary) -> bool: return not group.deployed).size())
	var row_indices := {true: 1, false: 1}
	for key: String in groups:
		var group: Dictionary = groups[key]
		if not _rows.has(key):
			var row: Button = GROUP_ROW.instantiate()
			(%DeployedRows if group.deployed else %ReserveRows).add_child(row)
			row.gui_input.connect(_on_group_input.bind(key))
			_rows[key] = row
			UIMotion.bind_buttons(row)
		var row: Button = _rows[key]
		row.get_parent().move_child(row, row_indices[group.deployed])
		row_indices[group.deployed] += 1
		row.set_meta("uids", group.uids)
		row.set_meta("deployed", group.deployed)
		var definition: UnitDefinition = _rogue.state.unit_definition(group.kind)
		row.get_node("Margin/Content/Portrait").texture = %ModelPreviews.portrait(group.kind)
		row.get_node("Margin/Content/Name").text = definition.name
		row.get_node("Margin/Content/Count").text = "× %d" % group.uids.size()
		row.tooltip_text = "%s\n单击选择该兵种 · Shift 单击增减选择\n双击转移 1 名 · Shift 双击转移全部" % definition.description
	for key: String in _rows.keys():
		if not groups.has(key):
			_rows[key].get_parent().remove_child(_rows[key])
			_rows[key].queue_free()
			_rows.erase(key)
	_refresh_row_selection()

func _refresh_row_selection() -> void:
	for row: Button in _rows.values():
		var uids: Array = row.get_meta("uids")
		var selected_count: int = uids.filter(func(uid: int) -> bool: return uid in _selected_uids).size()
		row.add_theme_stylebox_override("normal", ROW_SELECTED if selected_count > 0 else ROW_IDLE)
		row.get_node("Margin/Content/Count").text = "%d / %d" % [selected_count, uids.size()] if selected_count > 0 and selected_count < uids.size() else "× %d" % uids.size()

func _on_group_input(event: InputEvent, key: String) -> void:
	if not _rows.has(key): return
	var row: Button = _rows[key]
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var uids: Array = row.get_meta("uids")
		if event.double_click:
			_transfer(uids if event.shift_pressed else [uids[0]], not bool(row.get_meta("deployed")))
		else:
			_select_group(uids, event.shift_pressed or event.ctrl_pressed)
		row.accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.is_action_pressed("ui_accept"):
		_select_group(row.get_meta("uids"), event.shift_pressed or event.ctrl_pressed)
		row.accept_event()

func _select_group(uids: Array, additive: bool) -> void:
	var next: Array[int] = []
	if additive: next.assign(_selected_uids)
	var remove := additive and uids.all(func(uid: int) -> bool: return uid in next)
	for uid: int in uids:
		if remove: next.erase(uid)
		elif uid not in next: next.append(uid)
	_select_uids(next)

func _select_uid(uid: int) -> void:
	_select_uids([uid])

func _select_uids(uids: Array) -> void:
	_selected_uids.assign(uids)
	_set_status("")
	_refresh_row_selection()
	_refresh_unit_details()

func _unit_by_uid(uid: int) -> Dictionary:
	for unit: Dictionary in _rogue.state.data.roster:
		if int(unit.uid) == uid: return unit
	return {}

func _selected_units(deployed_only: bool = false) -> Array:
	return _rogue.state.data.roster.filter(func(unit: Dictionary) -> bool: return int(unit.uid) in _selected_uids and (not deployed_only or bool(unit.deployed)))

func _refresh_unit_details() -> void:
	var units := _selected_units()
	var deployed := _selected_units(true)
	%UnitControls.visible = not units.is_empty()
	%NoUnit.visible = units.is_empty()
	_board.show_formation(_rogue.state.data.roster, _encounter, _selected_uids)
	%MapNote.text = "前哨站 · 西侧部署区 24 × 24" if _encounter == "outpost" else "围剿战 · 琥珀区域为大本营及通行预留"
	if units.is_empty(): return
	var kinds: Dictionary = {}
	for unit: Dictionary in units:
		kinds[unit.kind] = int(kinds.get(unit.kind, 0)) + 1
	var first: Dictionary = units[0]
	var definition: UnitDefinition = _rogue.state.unit_definition(first.kind)
	%UnitName.text = definition.name if kinds.size() == 1 else "联合编队"
	%SelectionSummary.text = "已选 %d 名 · 出战 %d · 待命 %d" % [units.size(), deployed.size(), units.size() - deployed.size()]
	%UnitDescription.text = definition.description if kinds.size() == 1 else "整组移动与旋转会保留单位之间的相对阵形。"
	if kinds.size() == 1:
		%UnitStats.text = "生命  %s\n攻击  %s    射程  %s\n近甲  %s    远甲  %s" % [_number(definition.hp), _number(definition.damage), _number(definition.range), _number(definition.melee_armor), _number(definition.ranged_armor)]
	else:
		var lines: PackedStringArray = []
		for kind: String in kinds: lines.append("%s × %d" % [BalanceCatalog.unit(kind).name, kinds[kind]])
		%UnitStats.text = "\n".join(lines)
	%DeployButton.disabled = deployed.is_empty()
	%EnlistButton.disabled = deployed.size() == units.size()
	%DeployButton.text = "移入待命区  (%d)" % deployed.size()
	%EnlistButton.text = "编入出战  (%d)" % (units.size() - deployed.size())
	%PositionControls.visible = not deployed.is_empty()
	%PrecisePosition.visible = units.size() == 1 and deployed.size() == 1
	%ReserveNote.visible = deployed.is_empty()
	if units.size() == 1:
		var layout: Array = first.layouts[_encounter]
		%PositionX.set_value_no_signal(float(layout[0]))
		%PositionZ.set_value_no_signal(float(layout[1]))
		%PositionYaw.set_value_no_signal(wrapf(rad_to_deg(float(layout[2])), -180, 180))

func _on_map_selected(index: int) -> void:
	_board.cancel_gesture()
	_encounter = "siege" if index == 1 else "outpost"
	%MapChoice.select(index)
	_set_status("")
	_refresh_unit_details()

func _transfer_selected(deployed: bool) -> void:
	var uids: Array = _selected_units().filter(func(unit: Dictionary) -> bool: return bool(unit.deployed) != deployed).map(func(unit: Dictionary) -> int: return int(unit.uid))
	_transfer(uids, deployed)

func _toggle_deployed() -> void:
	_transfer_selected(_selected_units(true).is_empty())

func _transfer(uids: Array, deployed: bool) -> void:
	if uids.is_empty(): return
	_board.cancel_gesture()
	var result: int = _rogue.set_deployed_many(uids, deployed)
	_refresh()
	_set_status("%d 名单位已%s。" % [uids.size(), "编入出战军队" if deployed else "移入待命区"] if result == OK else _rogue.error_message, result != OK)

func _apply_position() -> void:
	if _selected_uids.size() == 1:
		_save_layout(_selected_uids[0], [%PositionX.value, %PositionZ.value, deg_to_rad(%PositionYaw.value)])

func _save_layout(uid: int, layout: Array) -> void:
	_save_layouts([{"uid": uid, "layout": layout}])

func _save_layouts(changes: Array) -> void:
	if changes.is_empty(): return
	var result: int = _rogue.set_layouts(_encounter, changes)
	_refresh_unit_details()
	_set_status("已更新 %d 名单位的阵形。" % changes.size() if result == OK else _rogue.error_message, result != OK)

func _rotate_selected(degrees: float) -> void:
	_board.cancel_gesture()
	var units := _selected_units(true)
	if units.is_empty(): return
	var center := Vector2.ZERO
	for unit: Dictionary in units:
		var layout: Array = unit.layouts[_encounter]
		center += Vector2(float(layout[0]), float(layout[1]))
	center /= units.size()
	var radians := deg_to_rad(degrees)
	var changes: Array = []
	for unit: Dictionary in units:
		var layout: Array = unit.layouts[_encounter]
		# Godot's Y rotation is clockwise in the X/Z projection.
		var point := center + (Vector2(float(layout[0]), float(layout[1])) - center).rotated(-radians)
		changes.append({"uid": int(unit.uid), "layout": [point.x, point.y, wrapf(float(layout[2]) + radians, -PI, PI)]})
	_save_layouts(changes)

func _set_status(message: String, error: bool = false) -> void:
	%ArmyStatus.text = message
	%ArmyStatus.add_theme_color_override("font_color", Color("8a3d35") if error else Color("385840"))

static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
