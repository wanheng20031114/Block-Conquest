extends Node
## Persistent scene-authored UI players; menu changes never cut off a click.
## AudioStreamRandomizer selects variants, native polyphony bounds rapid input.
signal sound_played(kind: StringName)

var _next_ms: Dictionary[StringName, int] = {}

func play(kind: StringName) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_ms.get(kind, 0):
		return
	_next_ms[kind] = now + (100 if kind == &"ratio" else 55)
	var player: AudioStreamPlayer = get_node(NodePath(kind))
	player.play()
	sound_played.emit(kind)

func bind_buttons(container: Node) -> void:
	for button: BaseButton in container.find_children("*", "BaseButton", true, false):
		button.pressed.connect(_on_button_pressed.bind(button))
		if button is OptionButton:
			button.item_selected.connect(func(_index: int): play(&"select"))

func _on_button_pressed(button: BaseButton) -> void:
	play(StringName(button.get_meta(&"ui_sound", &"select")))

func stop_all() -> void:
	for player: AudioStreamPlayer in get_children():
		player.stop()
	_next_ms.clear()
