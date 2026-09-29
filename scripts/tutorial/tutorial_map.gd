extends WarMap
## Small, authored practice grounds reuse the battle's full formation routing.
## Their scene-local definitions and layouts never mutate a skirmish map.

func _ready() -> void:
	bake_routes = true
	super._ready()
