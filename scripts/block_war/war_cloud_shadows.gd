extends Node3D
## Higher sample count keeps the large, distant penumbrae free of stipple.
## RenderingServer exposes this setting globally, so restore the project
## preference when the battlefield releases its shadow-casting cloud scene.

func _enter_tree() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)

func _exit_tree() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(
		ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")
	)
