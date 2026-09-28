extends RefCounted
## Cannon report shared by the campaign audio pool.

const EVENTS: Dictionary = {
	"cannon_shot": {"streams": [preload("res://assets/audio/cannon_shot_01.wav"), preload("res://assets/audio/cannon_shot_02.wav")], "gain_db": -2.0, "bus": &"Combat", "priority": 5, "gap_ms": 160, "limit": 3},
}
