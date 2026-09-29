extends PanelContainer
## One authored seat: identity, commander and host-only bot controls stay separate.

signal move_requested(slot_id: int)
signal kind_requested(slot_id: int, kind: String, commander: String)
signal commander_requested(slot_id: int, commander: String)

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const FACTIONS := preload("res://scripts/block_war/war_factions.gd")
const COMMANDERS: Array[String] = ["squirrel", "rabbit", "bear", "frog", "fox"]
var slot_id := 0
var _slot: Dictionary = {}

func _ready() -> void:
	for commander: String in COMMANDERS:
		%Commander.add_item(RULES.name_for(StringName(commander)))
	%Commander.item_selected.connect(_commander_selected)
	%Occupant.item_selected.connect(_kind_selected)
	%Move.pressed.connect(func(): move_requested.emit(slot_id))

func refresh(slot: Dictionary, local_player: int, host_player: int, editable: bool) -> void:
	_slot = slot
	slot_id = int(slot.slot_id)
	var kind := str(slot.kind)
	var own := kind == "human" and int(slot.player_id) == local_player
	var host := local_player == host_player
	var tint: Color = FACTIONS.COLORS[int(slot.faction_id)]
	%SeatColor.color = tint
	%Number.text = "%02d" % (slot_id + 1)
	%Name.text = "等待加入" if kind == "open" else str(slot.name)
	%Name.tooltip_text = %Name.text
	%Badge.text = "你 · 房主" if own and host else ("你" if own else ("房主" if kind == "human" and int(slot.player_id) == host_player else ""))
	%Badge.visible = not %Badge.text.is_empty()
	var commander := str(slot.commander)
	%Commander.select(COMMANDERS.find(commander))
	%Portrait.texture = RULES.PORTRAITS[StringName(commander)]
	%Portrait.modulate.a = 0.35 if kind == "open" else 1.0
	%Commander.disabled = not editable or not (own or (host and kind == "bot"))
	%Commander.tooltip_text = " · ".join(RULES.names_for(StringName(commander)))
	%Move.visible = not own and kind != "human"
	%Move.disabled = not editable
	%Move.text = "移至此处"
	%Move.tooltip_text = "移动到这个出生位置；原位置将空出。" if kind == "open" else "与这个电脑交换位置。"
	%Occupant.visible = host and kind != "human"
	%Occupant.disabled = not editable
	%Occupant.select(1 if kind == "bot" else 0)
	%Status.text = "空位" if kind == "open" else "电脑已就位"
	%Status.modulate = Color("577666")
	if kind == "human":
		%Status.text = "已准备" if bool(slot.ready) else "尚未准备"
		if not bool(slot.connected):
			%Status.text = "连接中断 · 等待重连"
		elif str(slot.controller) == "reconnecting":
			%Status.text = "正在同步战场"
		%Status.modulate = Color("387651") if bool(slot.ready) else Color("8d6d40")

func _commander_selected(index: int) -> void:
	commander_requested.emit(slot_id, COMMANDERS[index])

func _kind_selected(index: int) -> void:
	kind_requested.emit(slot_id, "bot" if index == 1 else "open", str(_slot.commander))
