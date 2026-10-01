extends Control
## Native viewport references, checked 2026-09-30:
## https://docs.godotengine.org/en/stable/classes/class_subviewport.html
## https://docs.godotengine.org/en/stable/classes/class_subviewportcontainer.html
## https://docs.godotengine.org/en/stable/classes/class_viewport.html
## own_world_3d isolates the scene; disabled input keeps the guide in control;
## UPDATE_DISABLED stops hidden/paused rendering. Whole authored scenes reset
## the example, including every real particle pool and skill rule state.

const WORLD := preload("res://scenes/codex/demo_world.tscn")
var commander: StringName = &"squirrel"
var skill_index := 0
var bear_hostile := false
var frog_siege := false
var pig_hostile := false
var playing := true
var world: Node3D
var progress: float:
	get: return world.elapsed / world.CYCLE_SECONDS if is_instance_valid(world) else 0.0
@onready var viewport: SubViewport = %BattleViewport

func _ready() -> void:
	visibility_changed.connect(_sync_playback)
	resized.connect(_fit_stage)
	_fit_stage()
	replay()

func configure(next_commander: StringName, next_skill_index: int) -> void:
	commander = next_commander
	skill_index = next_skill_index
	bear_hostile = false
	frog_siege = false
	pig_hostile = false
	if is_node_ready(): replay()

func set_playing(enabled: bool) -> void:
	playing = enabled
	if is_node_ready(): _sync_playback()

func replay() -> void:
	if not is_node_ready(): return
	if is_instance_valid(world):
		viewport.remove_child(world)
		world.free()
	world = WORLD.instantiate()
	world.demo_commander = commander
	world.demo_skill = skill_index
	world.bear_hostile = bear_hostile
	world.frog_siege = frog_siege
	world.pig_hostile = pig_hostile
	viewport.add_child(world)
	_fit_stage()
	world.cycle_completed.connect(_repeat)
	_update_caption()
	_sync_playback()

func _repeat() -> void:
	if commander == &"bear" and skill_index == 3:
		bear_hostile = not bear_hostile
	if commander == &"frog" and skill_index == 0:
		frog_siege = not frog_siege
	if commander == &"pig" and skill_index == 2:
		pig_hostile = not pig_hostile
	replay.call_deferred()

func _sync_playback() -> void:
	var active := playing and is_visible_in_tree()
	world.set_running(active)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active)

func _process(_delta: float) -> void:
	_update_caption()

func _update_caption() -> void:
	%Caption.text = world.caption
	%Phase.text = "施放前" if world.cast_count == 0 else "施放后"
	%Timeline.value = progress
	%Morale.visible = commander == &"fox" and skill_index == 1
	if %Morale.visible:
		%Morale.text = "己方士气 %d 星    敌方士气 %d 星" % [world.morale.level(0), world.morale.level(1)]

func _fit_stage() -> void:
	# The native render fills its panel. Orthographic camera framing adapts to
	# the available aspect without stretching buildings or cropping high VFX.
	var available := Vector2(size.x, maxf(1.0, size.y - 41.0))
	%Stage.size = available
	%Stage.position = Vector2.ZERO
	if is_instance_valid(world): world.fit_camera(available.x / available.y)

func _exit_tree() -> void:
	if is_instance_valid(world): world.set_running(false)
