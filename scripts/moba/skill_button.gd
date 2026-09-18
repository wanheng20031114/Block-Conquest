extends Button
## Labels stay stable while a separate native progress bar shows the cooldown.
@export var title: String
@export var detail: String
@export var hotkey: String
@export var cooldown_seconds: float = 20
@export var icon_texture: Texture2D
var _previous_remaining: float = 0
var _target_progress: float = 100

func _ready() -> void:
	%Title.text = title
	%Detail.text = detail
	%Key.text = hotkey
	%Icon.texture = icon_texture
	%Cooldown.value = 100

func present(remaining: float, available: bool, active: bool) -> void:
	disabled = not available or remaining > .000001
	if available and remaining > _previous_remaining + .5:
		%Motion.play("cast")
		%Cooldown.value = 0
	elif available and _previous_remaining > .000001 and remaining <= .000001:
		%Motion.play("ready")
	_previous_remaining = remaining
	_target_progress = (1.0 - remaining / cooldown_seconds) * 100
	%Status.text = "%.1f 秒" % remaining if remaining > .000001 else ("可释放" if available else "未就绪")
	%Detail.text = ("持续恢复中" if hotkey == "E" else "加速生效中") if active else detail
	%Status.modulate = Color.WHITE if available else Color(.75,.8,.82,1)

func _process(delta: float) -> void:
	%Cooldown.value = move_toward(%Cooldown.value, _target_progress, delta * 140)
