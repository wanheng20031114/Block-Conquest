extends VBoxContainer

var skill_button: Button

func configure(button: Button) -> void:
	# Populate before the native PopupPanel measures the content's minimum size.
	skill_button = button
	skill_button.hint_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	var hint: Dictionary = skill_button.hint
	%Title.text = hint.title
	%Shortcut.text = hint.shortcut
	%Description.text = hint.description
	%Stats.text = hint.stats
	%State.text = hint.status
	%Energy.text = hint.energy
	%State.add_theme_color_override("font_color", Color("376743") if hint.ready else Color("88523a"))
