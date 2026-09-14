class_name RogueArmyPanel
extends Control
## A single army workspace backed exclusively by RogueSession commands.
signal closed

var _tab := "formation"
var _encounter := "outpost"
var _selected_uid := -1
var _selected_ticket := -1
var _candidate_kind := ""
var _refreshing := false
var _reveal: Tween

@onready var _rogue: Node = get_node("/root/Session/Rogue")
@onready var _board: RogueArmyBoard = %ArmyBoard

func _ready() -> void:
	%FormationTab.pressed.connect(_change_tab.bind("formation"))
	%RecruitTab.pressed.connect(_change_tab.bind("recruit"))
	%CloseArmy.pressed.connect(close_panel)
	%MapChoice.item_selected.connect(_on_map_selected)
	%RosterFilter.item_selected.connect(func(_index: int) -> void: _refresh_roster())
	%ArmyRoster.item_selected.connect(_on_unit_selected)
	%ArmyTickets.item_selected.connect(_on_ticket_selected)
	%ArmyCandidates.item_selected.connect(_on_candidate_selected)
	%DeployButton.pressed.connect(_toggle_deployed)
	%ApplyPosition.pressed.connect(_apply_position)
	%RotateLeft.pressed.connect(_rotate_selected.bind(-15.0))
	%RotateRight.pressed.connect(_rotate_selected.bind(15.0))
	%Batches.value_changed.connect(func(_value: float) -> void: _refresh_recruit_summary())
	%RecruitConfirm.pressed.connect(_confirm_recruit)
	%RecruitCancel.pressed.connect(_cancel_recruit)
	_board.unit_selected.connect(_select_uid)
	_board.layout_requested.connect(_save_layout)
	_rogue.changed.connect(_on_state_changed)

func open_panel(tab: String = "formation", encounter: String = "outpost") -> void:
	_encounter = encounter
	%MapChoice.select(1 if encounter == "siege" else 0)
	show()
	_change_tab(tab)
	_set_status("")
	if _reveal != null:
		_reveal.kill()
	modulate.a = 0.0
	_reveal = create_tween()
	_reveal.tween_property(self, "modulate:a", 1.0, .18).set_trans(Tween.TRANS_SINE)
	%CloseArmy.grab_focus()

func close_panel() -> void:
	hide()
	if _reveal != null:
		_reveal.kill()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and _tab == "formation":
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		if event.physical_keycode == KEY_Q:
			_rotate_selected(-15)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_E:
			_rotate_selected(15)
			get_viewport().set_input_as_handled()

func _change_tab(tab: String) -> void:
	_tab = tab
	var formation := tab == "formation"
	%FormationTab.set_pressed_no_signal(formation)
	%RecruitTab.set_pressed_no_signal(not formation)
	%FormationSidebar.visible = formation
	%RecruitSidebar.visible = not formation
	%FormationInspector.visible = formation
	%RecruitInspector.visible = not formation
	%MapChoice.visible = formation
	%WorkspaceTitle.text = "部署阵形" if formation else "招募军队"
	%WorkspaceHint.text = "拖动调整位置 · 右键移动 · Q / E 旋转 · 滚轮缩放" if formation else "选择招募券与兵种 · 按住模型拖动可旋转查看"
	_refresh()

func _on_state_changed() -> void:
	if is_visible_in_tree() and not _refreshing:
		_refresh()

func _refresh() -> void:
	_refreshing = true
	var state = _rogue.state
	%PopulationValue.text = "%d / %d" % [state.population(), state.population_cap()]
	%BreadValue.text = "%d  面包" % int(state.data["bread"])
	%TicketCount.text = "%d 张招募券" % state.data["tickets"].size()
	if _tab == "formation":
		_refresh_roster()
	else:
		_refresh_tickets()
	_refreshing = false

func _refresh_roster() -> void:
	var roster: Array = _rogue.state.data["roster"]
	var list: ItemList = %ArmyRoster
	list.clear()
	var selected_index := -1
	var deployed_count := 0
	var filter_index: int = %RosterFilter.selected
	for unit: Dictionary in roster:
		if bool(unit["deployed"]):
			deployed_count += 1
		if filter_index == 1 and not bool(unit["deployed"]):
			continue
		if filter_index == 2 and bool(unit["deployed"]):
			continue
		var definition: UnitDefinition = _rogue.state.unit_definition(str(unit["kind"]))
		var index := list.add_item("%s  #%02d    %d 人口" % [definition.name, int(unit["uid"]), definition.supply])
		list.set_item_metadata(index, int(unit["uid"]))
		list.set_item_tooltip(index, "%s · %s" % ["已编入出战军队" if bool(unit["deployed"]) else "在待命区", definition.description])
		list.set_item_custom_fg_color(index, Color("f4cf89") if bool(unit["deployed"]) else Color("aabbb0"))
		if int(unit["uid"]) == _selected_uid:
			selected_index = index
	%RosterSummary.text = "出战 %d  ·  待命 %d" % [deployed_count, roster.size() - deployed_count]
	if selected_index < 0 and list.item_count > 0:
		selected_index = 0
		_selected_uid = int(list.get_item_metadata(0))
	elif list.item_count == 0:
		_selected_uid = -1
	if selected_index >= 0:
		list.select(selected_index)
	_refresh_unit_details()

func _unit_by_uid(uid: int) -> Dictionary:
	for unit: Dictionary in _rogue.state.data["roster"]:
		if int(unit["uid"]) == uid:
			return unit
	return {}

func _on_unit_selected(index: int) -> void:
	_selected_uid = int(%ArmyRoster.get_item_metadata(index))
	_set_status("")
	_refresh_unit_details()

func _select_uid(uid: int) -> void:
	_selected_uid = uid
	if %RosterFilter.selected == 2:
		%RosterFilter.select(0)
	_refresh_roster()

func _refresh_unit_details() -> void:
	var unit := _unit_by_uid(_selected_uid)
	%UnitControls.visible = not unit.is_empty()
	%NoUnit.visible = unit.is_empty()
	_board.show_formation(_rogue.state.data["roster"], _encounter, _selected_uid)
	%MapNote.text = "前哨站 · 西侧出生区 24 × 24" if _encounter == "outpost" else "围剿战 · 中央基地周围部署，琥珀区域不可占用"
	if unit.is_empty():
		return
	var definition: UnitDefinition = _rogue.state.unit_definition(str(unit["kind"]))
	%UnitName.text = definition.name
	%UnitIndex.text = "单位 #%02d · %d 人口" % [int(unit["uid"]), definition.supply]
	%UnitDescription.text = definition.description
	%UnitStats.text = "生命  %s\n攻击  %s    射程  %s\n近战护甲  %s    远程护甲  %s" % [_number(definition.hp), _number(definition.damage), _number(definition.range), _number(definition.melee_armor), _number(definition.ranged_armor)]
	%DeployButton.text = "移入待命区" if bool(unit["deployed"]) else "编入出战军队"
	%PositionControls.visible = bool(unit["deployed"])
	%ReserveNote.visible = not bool(unit["deployed"])
	var layout: Array = unit["layouts"][_encounter]
	%PositionX.set_value_no_signal(float(layout[0]))
	%PositionZ.set_value_no_signal(float(layout[1]))
	%PositionYaw.set_value_no_signal(wrapf(rad_to_deg(float(layout[2])), -180, 180))

func _on_map_selected(index: int) -> void:
	_encounter = "siege" if index == 1 else "outpost"
	%MapChoice.select(index)
	_set_status("")
	_refresh_unit_details()

func _toggle_deployed() -> void:
	var unit := _unit_by_uid(_selected_uid)
	if unit.is_empty():
		return
	var deployed := not bool(unit["deployed"])
	var result: int = _rogue.set_deployed(_selected_uid, deployed)
	if result == OK:
		_set_status("已编入出战军队。" if deployed else "已移入待命区。")
	else:
		_set_status(_rogue.error_message, true)
	_refresh()

func _apply_position() -> void:
	_save_layout(_selected_uid, [%PositionX.value, %PositionZ.value, deg_to_rad(%PositionYaw.value)])

func _save_layout(uid: int, layout: Array) -> void:
	var result: int = _rogue.set_layout(uid, _encounter, layout)
	if result == OK:
		_set_status("阵形位置已更新。")
	else:
		_set_status(_rogue.error_message, true)
	_refresh_unit_details()

func _rotate_selected(degrees: float) -> void:
	var unit := _unit_by_uid(_selected_uid)
	if unit.is_empty() or not bool(unit["deployed"]):
		return
	var layout: Array = unit["layouts"][_encounter].duplicate()
	layout[2] = wrapf(float(layout[2]) + deg_to_rad(degrees), -PI, PI)
	_save_layout(_selected_uid, layout)

func _refresh_tickets() -> void:
	var tickets: Array = _rogue.state.data["tickets"]
	%ArmyTickets.clear()
	var selected_index := -1
	for ticket: Dictionary in tickets:
		var index: int = %ArmyTickets.add_item("部队招募券   #%02d" % int(ticket["uid"]))
		%ArmyTickets.set_item_metadata(index, int(ticket["uid"]))
		var names: PackedStringArray = []
		for kind: String in ticket["candidates"]:
			names.append(BalanceCatalog.unit(kind).name)
		%ArmyTickets.set_item_tooltip(index, " / ".join(names))
		if int(ticket["uid"]) == _selected_ticket:
			selected_index = index
	if selected_index < 0 and not tickets.is_empty():
		selected_index = 0
		_selected_ticket = int(tickets[0]["uid"])
	elif tickets.is_empty():
		_selected_ticket = -1
		_candidate_kind = ""
	if selected_index >= 0:
		%ArmyTickets.select(selected_index)
	%NoTickets.visible = tickets.is_empty()
	_refresh_candidates()

func _ticket() -> Dictionary:
	for ticket: Dictionary in _rogue.state.data["tickets"]:
		if int(ticket["uid"]) == _selected_ticket:
			return ticket
	return {}

func _on_ticket_selected(index: int) -> void:
	_selected_ticket = int(%ArmyTickets.get_item_metadata(index))
	_candidate_kind = ""
	%Batches.set_value_no_signal(1)
	_set_status("")
	_refresh_candidates()

func _refresh_candidates() -> void:
	%ArmyCandidates.clear()
	var ticket := _ticket()
	var selected_index := -1
	if not ticket.is_empty():
		for kind: String in ticket["candidates"]:
			var definition: UnitDefinition = _rogue.state.unit_definition(kind)
			var spec: Dictionary = RogueCatalog.RECRUIT[kind]
			var index: int = %ArmyCandidates.add_item("%s   %d名 / %d面包" % [definition.name, int(spec["count"]), int(spec["bread"])])
			%ArmyCandidates.set_item_metadata(index, kind)
			if kind == _candidate_kind:
				selected_index = index
		if selected_index < 0:
			selected_index = 0
			_candidate_kind = str(ticket["candidates"][0])
	if selected_index >= 0:
		%ArmyCandidates.select(selected_index)
	_refresh_recruit_summary()

func _on_candidate_selected(index: int) -> void:
	_candidate_kind = str(%ArmyCandidates.get_item_metadata(index))
	%ArmyCandidates.select(index)
	_set_status("")
	_refresh_recruit_summary()

func _refresh_recruit_summary() -> void:
	var valid := not _candidate_kind.is_empty() and not _ticket().is_empty()
	%RecruitControls.visible = valid
	%RecruitEmpty.visible = not valid
	%RecruitConfirm.disabled = not valid
	%MapNote.text = "新单位进入待命区 · 不占用出战人口"
	_board.show_candidate(_candidate_kind if valid else "")
	if not valid:
		return
	var definition: UnitDefinition = _rogue.state.unit_definition(_candidate_kind)
	var spec: Dictionary = RogueCatalog.RECRUIT[_candidate_kind]
	var batches := int(%Batches.value)
	var cost := int(spec["bread"]) * batches
	var count := int(spec["count"]) * batches
	%RecruitName.text = definition.name
	%RecruitDescription.text = definition.description
	%RecruitStats.text = "每名 %d 人口\n生命 %s  ·  攻击 %s\n射程 %s  ·  移速 %s" % [definition.supply, _number(definition.hp), _number(definition.damage), _number(definition.range), _number(definition.speed)]
	%RecruitCost.text = "%d 名单位\n%d 面包 + 1 张招募券" % [count, cost]
	%RecruitConfirm.disabled = int(_rogue.state.data["bread"]) < cost
	%RecruitConfirm.text = "确认招募  %d 名" % count if not %RecruitConfirm.disabled else "面包不足"

func _confirm_recruit() -> void:
	if _candidate_kind.is_empty() or _selected_ticket < 0:
		return
	var batches := int(%Batches.value)
	var definition: UnitDefinition = _rogue.state.unit_definition(_candidate_kind)
	var amount := int(RogueCatalog.RECRUIT[_candidate_kind]["count"]) * batches
	var result: int = _rogue.recruit(_selected_ticket, _candidate_kind, batches)
	if result == OK:
		_set_status("%d 名%s已加入待命区，可切换编队安排出战。" % [amount, definition.name])
		%Batches.set_value_no_signal(1)
	else:
		_set_status(_rogue.error_message, true)
	_refresh()

func _cancel_recruit() -> void:
	_selected_ticket = -1
	_candidate_kind = ""
	%ArmyTickets.deselect_all()
	%ArmyCandidates.clear()
	%Batches.set_value_no_signal(1)
	_set_status("已取消，本次未消耗面包或招募券。")
	_refresh_recruit_summary()

func _set_status(message: String, error: bool = false) -> void:
	%ArmyStatus.text = message
	%ArmyStatus.modulate = Color("f0bca0") if error else Color("cbd9bd")

static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
