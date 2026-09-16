class_name HeroVisual
extends UnitVisual
## Local appearance is visual only; the equipped weapon owns combat state.
func set_working(_active: bool, _mode: String = "gather") -> void:
	pass

func apply_appearance(profile: Dictionary) -> void:
	var team_color := FactionPalette.model_color(_team)
	var garment: Color = team_color if profile.get("team_clothes",true) else profile.get("garment",Color("2087ab"))
	for mesh: MeshInstance3D in _team_surfaces:
		mesh.set_instance_shader_parameter("garment_color",garment)
		mesh.set_instance_shader_parameter("face_color",profile.get("face",Color("efdaa9")))
		mesh.set_instance_shader_parameter("boot_color",profile.get("boots",Color("63452f")))
	var hats: Array[String] = ["Hat","Beret","TrailHat"]
	for index: int in hats.size():
		get_node("Rig/Accessories/"+hats[index]).visible = profile.hat and profile.headwear==index
	for part: String in ["Backpack","Nose","Glasses","Scarf","Moustache","Feather"]:
		get_node("Rig/Accessories/"+part).visible = profile[part.to_snake_case()]
	for index: int in $Rig/Expressions.get_child_count():
		$Rig/Expressions.get_child(index).visible = index==profile.expression

func play_reload() -> void:
	synchronize_animation()
	attack.play("reload",.08)

func strike() -> void:
	super.strike()
	# Instantaneous fire reads the actual forward-facing socket this same tick.
	attack.advance(0.0)

func set_personal_layer(layer: int) -> void:
	for mesh: MeshInstance3D in _team_surfaces: mesh.layers = layer
