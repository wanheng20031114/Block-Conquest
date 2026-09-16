extends SubViewport
## One cached portrait for the local hero, shared by details and composition.
var _appearance: Dictionary = {}
func _ready() -> void:
	$Model.process_mode = Node.PROCESS_MODE_DISABLED
	$Model/Locomotion.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	$Model/Attack.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
func sync_appearance(profile: Dictionary) -> void:
	if _appearance == profile: return
	_appearance = profile.duplicate(true)
	$Model.set_team(FactionPalette.SANDBOX_OFFSET + profile.faction)
	$Model.apply_appearance(profile)
	render_target_update_mode = SubViewport.UPDATE_ONCE
