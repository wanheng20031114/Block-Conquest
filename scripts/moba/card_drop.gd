extends Control
var interface: Control

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind") != "moba_army_card": return false
	var error: String = interface.game.card_error(0, data.slot, data.uid)
	%DropText.text = "松开：从大本营派出援军" if error.is_empty() else error
	return error.is_empty()

func _drop_data(_position: Vector2, data: Variant) -> void:
	interface.game.play_card(0, data.slot, data.uid)
