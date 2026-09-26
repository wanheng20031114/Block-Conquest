extends Button
## The native tooltip owns a fresh instance of the scene-authored hint card.

signal hint_changed()

const HINT_SCENE: PackedScene = preload("res://scenes/block_war/skill_tooltip.tscn")

var hint: Dictionary = {}

func set_hint(title: String, description: String, cost: int, cooldown: float, energy: float, status: String, preview_enabled: bool) -> void:
	var stats := "消耗 %d 技力   ·   冷却 %d 秒" % [cost, int(cooldown)]
	hint = {
		"title": title, "shortcut": "[%s]" % $Key.text,
		"description": description, "stats": stats,
		"status": status if not status.is_empty() else "可以施放",
		"energy": "当前技力  %d / 100" % floori(energy),
		"ready": not disabled,
		"preview_enabled": preview_enabled,
	}
	# Keep the native hover delay stable while live energy/cooldowns change.
	tooltip_text = "%s  %s\n%s\n%s" % [title, hint.shortcut, description, stats] if preview_enabled else ""
	hint_changed.emit()

func _get_tooltip(at_position: Vector2) -> String:
	# Mouse capture must never turn a battlefield pointer into a button preview.
	return tooltip_text if Rect2(Vector2.ZERO, size).has_point(at_position) else ""

func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.is_empty():
		return null
	var card: Control = HINT_SCENE.instantiate()
	card.configure(self)
	return card
