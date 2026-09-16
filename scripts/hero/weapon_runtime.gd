class_name HeroWeaponRuntime
extends Node
## One simulation clock for both input modes. Rendering never advances ammo.
signal fired
signal reload_started
signal changed
@export var definition: HeroWeaponDefinition
var rounds: int = 10
var cooldown: float = 0.0
var reload_remaining: float = 0.0
var shots_fired: int = 0

func _ready() -> void:
	rounds = definition.magazine_size

func advance(delta: float) -> void:
	cooldown = cooldown-delta if cooldown>0.0 else 0.0
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0,reload_remaining-delta)
		if reload_remaining <= .000001:
			reload_remaining = 0.0
			rounds = definition.magazine_size
			changed.emit()

func begin_reload() -> bool:
	if rounds == definition.magazine_size or reload_remaining > 0.0:
		return false
	reload_remaining = definition.reload_seconds
	reload_started.emit()
	changed.emit()
	return true

func consume_shot() -> bool:
	if cooldown > .000001 or reload_remaining > 0.0:
		return false
	if rounds <= 0:
		begin_reload()
		return false
	rounds -= 1
	shots_fired += 1
	cooldown = definition.interval+minf(cooldown,0.0)
	fired.emit()
	changed.emit()
	return true

func finish_shot() -> void:
	if rounds == 0: begin_reload()

func payload(body: CombatDefinition, owner: int, alliance: int) -> DamagePayload:
	var result := DamageResolver.snapshot(body,definition.attack_bonus,owner,alliance)
	result.channel = definition.channel
	result.armor_penetration = definition.armor_penetration
	return result
