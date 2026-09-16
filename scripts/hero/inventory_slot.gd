class_name HeroInventorySlot
extends Button
const DRAG_PREVIEW := preload("res://scenes/hero/item_drag_preview.tscn")
@export var slot_index: int = 0
@export var is_shortcut: bool = false
var inventory: HeroInventory

func item_id() -> StringName:
	if inventory==null: return &""
	return inventory.hotbar[slot_index] if is_shortcut else inventory.slots[slot_index].id

func refresh() -> void:
	var id := item_id()
	var item: HeroItemDefinition = HeroInventory.ITEMS.get(id)
	$Icon.texture = item.icon if item != null else null
	$Count.text = str(inventory.count(id) if is_shortcut else inventory.slots[slot_index].count) if item != null else ""
	$Key.text = str(slot_index+1) if is_shortcut else ""
	$Key.visible = is_shortcut
	$Cooldown.visible = item != null and inventory.cooldowns.get(id,0.0)>0
	$Cooldown.value = inventory.cooldowns.get(id,0.0)/item.cooldown if item != null else 0.0
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
