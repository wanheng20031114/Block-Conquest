extends Node
## An intentionally silent presentation adapter. Menu music and preferences
## remain owned by Session; all gameplay and native visual effects still run.

func play_world(_kind: StringName, _at: Vector3) -> void:
	pass

func play_ui(_kind: StringName) -> void:
	pass

func tick_marches(_delta: float, _marches: WarMarches) -> void:
	pass
