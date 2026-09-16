class_name SelectionComposition
extends VBoxContainer
## Local presentation of the current selection; commands retain the full selection.
signal focus_changed
var game: Node3D
var portraits: Dictionary = {}
var groups: Array[Dictionary] = []
var focus_key := ""
var page := 0
var total_count := 0
var total_supply := 0
var _selection_revision := -1
@onready var slots: Array[Node] = %Slots.get_children()

func _ready() -> void:
	for index: int in slots.size():
		slots[index].pressed.connect(func(): activate(index, Input.is_key_pressed(KEY_CTRL), Input.is_key_pressed(KEY_SHIFT)))
	%Previous.pressed.connect(_turn_page.bind(-1))
	%Next.pressed.connect(_turn_page.bind(1))

func bind(controller: Node3D, textures: Dictionary) -> void:
	game = controller
	portraits = textures

func refresh() -> void:
	if game == null: return
	var grouped: Dictionary = {}
	total_count = 0
	total_supply = 0
	for entity: Node3D in game.selection:
		if not is_instance_valid(entity) or not entity.alive or not game.can_see_entity(game.local_owner_id, entity): continue
		var kind: String = entity.unit_type if entity is BattleUnit else (entity.building_type if entity is BattleBuilding else "gold_vein")
		var key := "%d:%s" % [entity.owner_id, kind]
		if not grouped.has(key):
			grouped[key] = {"key":key, "kind":kind, "name":entity.display_name, "owner":entity.owner_id, "members":[], "hp":0.0, "max_hp":0.0, "supply":0}
		var group: Dictionary = grouped[key]
		group.members.append(entity)
		if not entity is ResourceVein:
			group.hp += entity.hp
			group.max_hp += entity.max_hp
		if entity is BattleUnit:
			group.supply += entity.get_combat_definition().supply
			total_supply += entity.get_combat_definition().supply
		total_count += 1
	var old_keys: Array = groups.map(func(group: Dictionary): return group.key)
	groups.assign(grouped.values())
	# Keep the existing selection order (including production subgroups), with
	# hero capabilities first. Health/count updates never reorder the types.
	var heroes: Array[Dictionary] = groups.filter(func(group: Dictionary): return group.kind == "hero")
	groups = heroes + groups.filter(func(group: Dictionary): return group.kind != "hero")
	var composition_changed: bool = old_keys != groups.map(func(group: Dictionary): return group.key)
	var new_selection: bool = _selection_revision != game.selection_revision
	_selection_revision = game.selection_revision
	if new_selection or not grouped.has(focus_key):
		focus_key = groups[0].key if not groups.is_empty() else ""
	if composition_changed or new_selection:
		var keys: Array = groups.map(func(group: Dictionary): return group.key)
		page = maxi(0, keys.find(focus_key)) / slots.size()
	_draw_groups()

func focused_group() -> Dictionary:
	for group: Dictionary in groups:
		if group.key == focus_key: return group
	return {}

func focused_entity() -> Node3D:
	for entity: Node3D in focused_group().get("members", []):
		if is_instance_valid(entity) and entity.alive: return entity
	return null

func cycle(reverse: bool = false) -> bool:
	refresh()
	if groups.size() < 2: return false
	var keys: Array = groups.map(func(group: Dictionary): return group.key)
	var index := posmod(keys.find(focus_key) + (-1 if reverse else 1), groups.size())
	focus_key = groups[index].key
	page = index / slots.size()
	_draw_groups()
	focus_changed.emit()
	return true

func activate(index: int, isolate: bool = false, remove: bool = false) -> void:
	# Capture the displayed identity before pruning, so death cannot shift a click
	# onto an adjacent type between refreshes.
	var key: String = slots[index].get_meta("group_key", "")
	refresh()
	for group: Dictionary in groups:
		if group.key != key: continue
		if remove:
			game.select_entities(game.selection.filter(func(entity): return entity not in group.members))
		elif isolate:
			game.select_entities(group.members.duplicate())
		else:
			focus_key = key
			_draw_groups()
			focus_changed.emit()
		return

func _turn_page(direction: int) -> void:
	page += direction
	_draw_groups()

func _draw_groups() -> void:
	var pages := maxi(1, ceili(float(groups.size()) / slots.size()))
	page = clampi(page, 0, pages-1)
	%Summary.text = "已选 %d · %d 类 · 人口 %d" % [total_count, groups.size(), total_supply]
	var cycle_key: String = game.settings.hotkey_text("rts_cycle_buildings")
	%Summary.tooltip_text = "所选人口 %d\n%s / Shift+%s 切换查看兵种；行军和攻击仍指挥整队。" % [total_supply, cycle_key, cycle_key]
	$Hint.text = "点击查看 · Ctrl 仅选 · Shift 移出 · %s 切换" % cycle_key
	%Page.text = "%d/%d" % [page+1, pages]
	%Previous.disabled = page == 0
	%Next.disabled = page == pages-1
	for index: int in slots.size():
		var slot: Button = slots[index]
		var at := page * slots.size() + index
		slot.visible = at < groups.size()
		if not slot.visible:
			slot.remove_meta("group_key")
			continue
		var group: Dictionary = groups[at]
		slot.set_meta("group_key", group.key)
		slot.set_pressed_no_signal(group.key == focus_key)
		slot.get_node("Portrait").texture = portraits[group.kind]
		slot.get_node("Count").text = "×%d" % group.members.size()
		slot.get_node("Name").text = group.name
		slot.get_node("Health").max_value = maxf(1.0, group.max_hp)
		slot.get_node("Health").value = group.hp
		slot.get_node("Health").visible = group.max_hp > 0
		slot.tooltip_text = "%s ×%d · 生命 %d / %d · 人口 %d\n点击查看 · Ctrl 仅选该类 · Shift 移出该类" % [group.name, group.members.size(), ceili(group.hp), ceili(group.max_hp), group.supply]
