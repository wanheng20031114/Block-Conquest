extends WarMap
## The small authored training ground uses the same native route builder.
## No shared woodland shader clocks or match-map resource is changed.

func _ready() -> void:
	bake_routes = true
	super._ready()

func _process(_delta: float) -> void:
	pass
