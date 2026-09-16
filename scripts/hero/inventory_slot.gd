class_name HeroInventorySlot
extends Button
const DRAG_PREVIEW := preload("res://scenes/hero/item_drag_preview.tscn")
const FILLED := preload("res://assets/ui/hero/styles/slot.tres")
const EMPTY := preload("res://assets/ui/hero/styles/slot_empty.tres")
const SELECTED := preload("res://assets/ui/hero/styles/slot_selected.tres")
@export var slot_index: int = 0
@export var is_shortcut: bool = false
var inventory: HeroInventory
var selected := false
var shortcut_key := ""
var _surface: StyleBox

func item_id() -> StringName:
	if inventory==null: return &""
	return inventory.hotbar[slot_index] if is_shortcut else inventory.slots[slot_index].id

func refresh() -> void:
	var id := item_id()
	var item: HeroItemDefinition = HeroInventory.ITEMS.get(id)
	var surface: StyleBox = SELECTED if selected else (FILLED if item != null else EMPTY)
	if _surface != surface:
		_surface = surface
		add_theme_stylebox_override("normal", surface)
	$Icon.texture = item.icon if item != null else null
	$Count.text = str(inventory.count(id) if is_shortcut else inventory.slots[slot_index].count) if item != null else ""
	$Count.visible = item != null
	$Name.text = item.display_name if item != null else ""
	$Name.visible = item != null
	$Key.text = shortcut_key if is_shortcut else ""
	var key_half_width := maxf(12.0, shortcut_key.length()*6.0)
	$Key.offset_left = -key_half_width
	$Key.offset_right = key_half_width
	$Key.visible = is_shortcut
	var remaining: float = inventory.cooldowns.get(id,0.0) if item != null else 0.0
	$Cooldown.visible = remaining > 0.0
	$Cooldown.value = remaining/item.cooldown if item != null else 0.0
	$CooldownTime.visible = remaining > 0.0
	$CooldownTime.text = "%.1fs" % remaining
	$Icon.modulate = Color(.52,.60,.65,.78) if remaining > 0.0 else Color.WHITE
	tooltip_text = item.display_name+"\n"+item.description if item != null else ("从背包拖入道具" if is_shortcut else "空格")

func _get_drag_data(_at: Vector2) -> Variant:
	if item_id().is_empty(): return null
	var preview: TextureRect = DRAG_PREVIEW.instantiate()
	preview.texture = HeroInventory.ITEMS[item_id()].icon
	set_drag_preview(preview)
	return {"inventory":inventory,"slot":slot_index,"is_shortcut":is_shortcut,"id":item_id()}

func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	return data is Dictionary and data.get("inventory")==inventory and data.get("slot") is int and data.get("is_shortcut") is bool and data.get("id") is StringName and (is_shortcut or not data.is_shortcut)

func _drop_data(_at: Vector2,data: Variant) -> void:
	if not _can_drop_data(_at,data): return
	if is_shortcut: inventory.assign(slot_index,data.id)
	else: inventory.move_stack(data.slot,slot_index)
