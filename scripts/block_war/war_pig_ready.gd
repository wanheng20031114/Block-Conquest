extends Node3D
## Charge and flight preparation badges; the authoritative match owns expiry.

var building_id := -1
var remaining := Vector3.ZERO
var age := 0.0
var badge_ages := Vector3.ONE

func configure_surface(definition: WarMapDefinition) -> void:
	WarSurfaceEffects.configure($Ground.material_override, definition)

func update_building(building: WarBuilding, seconds: Vector3) -> void:
	if building_id != building.building_id:
		age = 0.0
		badge_ages = Vector3.ZERO
	for index: int in 2:
		if seconds[index] > 0.0 and (remaining[index] <= 0.0 or seconds[index] > remaining[index] + 0.1):
			badge_ages[index] = 0.0
	building_id = building.building_id
	position = building.global_position
	remaining = seconds
	visible = remaining.x > 0.0 or remaining.y > 0.0
	$Ground.material_override.set_shader_parameter("tint", WarBuilding.FACTION_COLORS[building.faction])
	$Ground.material_override.set_shader_parameter("strength", minf(1.0, maxf(seconds.x, seconds.y) / 3.0))
	for index: int in 2:
		var badge: Node3D = $Badges.get_child(index)
		badge.visible = seconds[index] > 0.0
		badge.get_node("Time").text = "%d" % ceili(seconds[index])
		badge.get_node("Time").modulate = Color("f6d46b") if seconds[index] < 3.0 else Color("fff0e8")
	pose()

func tick(delta: float) -> void:
	if visible:
		age += delta
		badge_ages += Vector3.ONE * delta
		pose()

func pose() -> void:
	$Ground.material_override.set_shader_parameter("age", age)
	$Badges.position.y = 6.3 + sin(age * 2.5) * 0.08
	for index: int in 2:
		var pulse := 1.0 + sin(age * (7.0 if remaining[index] < 3.0 else 2.5)) * 0.025
		var reveal := smoothstep(0.0, 0.12, badge_ages[index])
		var settle := 1.0 + sin(badge_ages[index] * 17.0) * exp(-badge_ages[index] * 6.0) * 0.24
		$Badges.get_child(index).scale = Vector3.ONE * pulse * reveal * settle

func reset() -> void:
	building_id = -1
	remaining = Vector3.ZERO
	hide()
