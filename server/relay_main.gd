extends SceneTree
## Development/source deployment entry. The production package uses the same scene.
const Bootstrap := preload("res://server/relay.tscn")

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	root.add_child(Bootstrap.instantiate())
