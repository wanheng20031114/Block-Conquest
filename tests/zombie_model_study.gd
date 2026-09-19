extends Node3D
## Editor-only model study: deliberately not linked by any game mode or catalog.
@onready var model: UnitVisual = $Turntable/Zombie
@onready var camera: Camera3D = $Camera
var team_index := 0

func _ready() -> void:
	camera.look_at(Vector3(0, 1.0, -.10))
	model.set_team(team_index)

func show_idle() -> void:
	model.attack.stop()
	model.set_motion(false)
	model.locomotion.play("idle", .16)

func show_walk() -> void:
	model.attack.stop()
	model.set_motion(true)

func show_strike() -> void:
	model.set_motion(false)
	model.strike()

func cycle_team() -> void:
	team_index = (team_index + 1) % 4
	model.set_team(team_index)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		$Turntable.rotation.y += event.relative.x * .008
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera.size = maxf(1.6, camera.size - .15)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera.size = minf(5.0, camera.size + .15)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: show_idle()
			KEY_2: show_walk()
			KEY_3: show_strike()
			KEY_4: cycle_team()
