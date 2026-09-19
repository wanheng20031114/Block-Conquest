extends Node3D
## Independent authoring viewer. No gameplay scene or unit catalog links here.

const DEFINITIONS: Array[MonsterDefinition] = [
	preload("res://data/prototypes/monsters/zombie_archer.tres"),
	preload("res://data/prototypes/monsters/zombie_musketeer.tres"),
	preload("res://data/prototypes/monsters/zombie_crossbowman.tres"),
	preload("res://data/prototypes/monsters/zombie_pitchfork.tres"),
	preload("res://data/prototypes/monsters/zombie_axe.tres"),
	preload("res://data/prototypes/monsters/zombie_miner.tres"),
	preload("res://data/prototypes/monsters/zombie_bell.tres"),
	preload("res://data/prototypes/monsters/zombie_door.tres"),
]

@onready var camera: Camera3D = $Camera
@onready var models: Array[UnitVisual] = [
	$Turntable/ZombieArcher,
	$Turntable/ZombieMusketeer,
	$Turntable/ZombieCrossbowman,
	$Turntable/ZombiePitchfork,
	$Turntable/ZombieAxe,
	$Turntable/ZombieMiner,
	$Turntable/ZombieBell,
	$Turntable/ZombieDoor,
]
@onready var selector: OptionButton = $Overlay/Interface/Selector
@onready var repeat_timer: Timer = $RepeatAction
@onready var loop_button: CheckButton = $Overlay/Interface/Controls/Loop
var model: UnitVisual
var team_index := 0
var selected_index := 0
var action_clip: StringName = &""


func _ready() -> void:
	camera.look_at(Vector3(0, 1.08, -.10))
	for definition: MonsterDefinition in DEFINITIONS:
		selector.add_item("%s · %d级" % [definition.name, definition.pve_tier])
	select_model(0)


func select_model(index: int) -> void:
	assert(index >= 0 and index < models.size(), "Select one of the eight saved monster models")
	repeat_timer.stop()
	for candidate: UnitVisual in models:
		candidate.attack.stop()
		candidate.locomotion.pause()
		candidate.visible = false
	selected_index = index
	selector.select(index)
	model = models[index]
	model.visible = true
	model.set_team(team_index)
	var definition: MonsterDefinition = DEFINITIONS[index]
	$Overlay/Interface/Title.text = definition.name
	var attack_name: String = "远程攻击" if definition.damage_channel == CombatDefinition.DamageChannel.RANGED else "近战攻击"
	$Overlay/Interface/Caption.text = "%d级 · 生命 %d · %s %d · 穿甲 %d\n近战护甲 %d · 远程护甲 %d · 攻击间隔 %.1f秒 · 移速 %.1f" % [
		definition.pve_tier, definition.hp, attack_name, definition.damage, definition.armor_penetration,
		definition.melee_armor, definition.ranged_armor, definition.cooldown, definition.speed]
	$Overlay/Interface/Controls/Rally.disabled = definition.monster_ability != MonsterDefinition.Ability.RALLY
	show_idle()


func show_idle() -> void:
	action_clip = &""
	repeat_timer.stop()
	model.attack.stop()
	model.set_motion(false)
	model.locomotion.play("idle", .16)
	model.locomotion.advance(0)


func show_walk() -> void:
	action_clip = &""
	repeat_timer.stop()
	model.attack.stop()
	model.set_motion(true)
	model.locomotion.play("walk", .16)


func show_strike() -> void:
	_play_action(&"strike")


func show_rally() -> void:
	if DEFINITIONS[selected_index].monster_ability == MonsterDefinition.Ability.RALLY:
		_play_action(&"rally")


func _play_action(clip: StringName) -> void:
	repeat_timer.stop()
	action_clip = clip
	model.set_motion(false)
	model.locomotion.play("idle", .12)
	if clip == &"strike":
		model.strike()
	else:
		model.synchronize_animation()
		model.attack.stop()
		model.attack.play(clip)
	if loop_button.button_pressed:
		_schedule_repeat()


func _schedule_repeat() -> void:
	var definition: MonsterDefinition = DEFINITIONS[selected_index]
	var interval: float = definition.rally_period if action_clip == &"rally" else definition.cooldown
	var clip_length: float = model.attack.get_animation(action_clip).length
	repeat_timer.start(maxf(interval, clip_length))


func _on_repeat_action_timeout() -> void:
	_play_action(action_clip)


func _on_loop_toggled(enabled: bool) -> void:
	if enabled and not action_clip.is_empty():
		_schedule_repeat()
	else:
		repeat_timer.stop()


func cycle_team() -> void:
	team_index = (team_index + 1) % 4
	model.set_team(team_index)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		$Turntable.rotation.y += event.relative.x * .008
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(1.6, camera.size - .15)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(5.5, camera.size + .15)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: show_idle()
			KEY_2: show_walk()
			KEY_3: show_strike()
			KEY_4: cycle_team()
			KEY_5: show_rally()
