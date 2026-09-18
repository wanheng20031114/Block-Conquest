class_name MobaHero
extends HeroUnit
var recovery_cooldown: float = 0.0
var morale_cooldown: float = 0.0
var recovery_ticks: int = 0
var recovery_clock: float = 0.0

func _ready() -> void:
	super._ready()
	# First-person hides only the local hero; the rival remains visible.
	if owner_id != 0:
		(_model as HeroVisual).set_personal_layer(1)
		health_bar.layers = 1
		work_bar.layers = 1
		selection_ring.layers = 1

func _physics_process(delta: float) -> void:
	if not alive: return
	recovery_cooldown = maxf(0, recovery_cooldown - delta)
	morale_cooldown = maxf(0, morale_cooldown - delta)
	if recovery_ticks > 0:
		recovery_clock += delta
		while recovery_ticks > 0 and recovery_clock + .000001 >= 1.0:
			recovery_clock -= 1.0
			recovery_ticks -= 1
			restore_health(25)
	super._physics_process(delta)

func cast_recovery() -> bool:
	if not alive or not _game.running or recovery_cooldown > .000001: return false
	recovery_cooldown = 20.0
	recovery_ticks = 5
	recovery_clock = 0.0
	_game.spawn_effect(global_position, "spawn", Color("65dca0"))
	return true

func cast_morale() -> bool:
	if not alive or not _game.running or morale_cooldown > .000001: return false
	morale_cooldown = 25.0
	_game.get_node("StatusEffects").apply_morale(self)
	_game.spawn_effect(global_position, "spawn", Color("73cfff"))
	return true
