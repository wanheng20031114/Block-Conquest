extends HBoxContainer
## Public skill indicators reveal readiness, never energy or a cooldown timer.

const RULES := preload("res://scripts/block_war/war_skill_rules.gd")
const STATUS_TEXT: Array[String] = ["冷却中", "冷却完成 · 技力不足", "可以施放"]

func update_skills(commander: StringName, statuses: Array, player_name: String, active: bool = true) -> void:
	var icons := RULES.icons_for(commander)
	var names := RULES.names_for(commander)
	for index: int in 4:
		var slot: Panel = get_child(index)
		var status: int = int(statuses[index])
		var icon: TextureRect = slot.get_node("Icon")
		icon.texture = icons[index]
		icon.modulate.a = 0.38 if status == 0 else 1.0
		slot.get_node("Cooling").visible = status == 0
		slot.get_node("ReadyLight").visible = status == 2 and active
		slot.tooltip_text = "%s · %s\n%s" % [player_name, names[index], STATUS_TEXT[status] if active else "当前无法施放"]
