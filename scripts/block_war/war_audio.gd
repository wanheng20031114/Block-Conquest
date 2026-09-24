extends "res://scripts/audio_director.gd"
## The campaign uses the shared native pools and preferences, with its own foley.
const WAR_BANK = preload("res://scripts/block_war/war_sound_bank.gd")
const MARCH_INTERVAL := 0.34
var _march_elapsed := 0.0
var _march_cursor := 0
@onready var _camera: Camera3D = get_parent().get_node("CameraRig/Camera3D")

func _ready() -> void:
	super._ready()
	# Native autoplay starts before this parent's ready callback. Track the music
	# playback alongside effects so scene changes await the mixer releasing it.
	_playbacks.append(weakref($Music.get_stream_playback()))

func stop_all() -> Array[WeakRef]:
	if not _stopping:
		$Music.stop()
		$Music.queue_free()
	return super.stop_all()

func _event_info(kind: StringName) -> Dictionary:
	if WAR_BANK.EVENTS.has(kind):
		return WAR_BANK.EVENTS[kind]
	return super._event_info(kind)

func _world_range(info: Dictionary) -> float:
	return 72.0 if info.bus == &"Foley" else 96.0

func tick_marches(delta: float, marches: WarMarches) -> void:
	if _stopping or _world_paused:
		return
	_march_elapsed += delta
	if _march_elapsed < MARCH_INTERVAL:
		return
	# A stalled frame emits one group, never a backlog of individual footsteps.
	_march_elapsed = fmod(_march_elapsed, MARCH_INTERVAL)
	var groups: Dictionary = {}
	for unit: Dictionary in marches.get_units():
		var at: Vector3 = unit.position
		var distance_squared := _listener.global_position.distance_squared_to(at)
		if distance_squared > 72.0 * 72.0 or not _camera.is_position_in_frustum(at):
			continue
		var key := Vector3i(unit.source_id, unit.target_id, unit.faction)
		if not groups.has(key) or distance_squared < float(groups[key].distance_squared):
			groups[key] = {"position": at, "distance_squared": distance_squared}
	if groups.is_empty():
		return
	var nearby: Array = groups.values()
	nearby.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance_squared < b.distance_squared)
	# Alternate the two nearest visible orders, even when either has 500 soldiers.
	var group: Dictionary = nearby[_march_cursor % mini(nearby.size(), 2)]
	_march_cursor += 1
	play_world(&"war_march", group.position)
