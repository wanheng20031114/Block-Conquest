extends Node3D
## Simulation-age driven landing: deterministic pose after a network snapshot.

const IMPACT_TIME := 0.65
const VISIBLE_TIME := 1.4
var drop_id := -1
var faction := 0
var age := 0.0
var active := false
var dust_emitted := false
var roof_height := 0.0

func _ready() -> void:
	# Texture import resolution must not change the physical 5.5-meter silhouette.
	$Pig.pixel_size = 5.5 / float($Pig.texture.get_width())

func configure_surface(definition: WarMapDefinition) -> void:
	WarSurfaceEffects.configure($Ground.material_override, definition)

func begin(id: int, owner: int, at: Vector3, elapsed: float, roof: float = 0.0) -> void:
	drop_id = id
	faction = owner
	position = at
	age = elapsed
	active = age < VISIBLE_TIME
	dust_emitted = age >= IMPACT_TIME
	roof_height = roof
	$Ground.material_override.set_shader_parameter("tint", Color("e7ac91").lerp(WarBuilding.FACTION_COLORS[faction], 0.15))
	pose()

func tick(delta: float) -> void:
	if active:
		age += delta
		active = age < VISIBLE_TIME
		pose()

func pose() -> void:
	visible = active
	if not active:
		return
	$Ground.material_override.set_shader_parameter("age", age)
	var falling := clampf(age / IMPACT_TIME, 0.0, 1.0)
	var landed := maxf(0.0, age - IMPACT_TIME)
	var squash := sin(clampf(landed / 0.18, 0.0, 1.0) * PI)
	var bounce := sin(clampf((landed - 0.14) / 0.32, 0.0, 1.0) * PI) * 0.55
	var fade := 1.0 - smoothstep(0.42, 0.70, landed)
	$Pig.position.y = roof_height + 1.75 + (1.0 - falling * falling) * 12.0 + bounce - squash * 0.25
	$Pig.scale = Vector3(1.0 + squash * 0.28, 1.0 - squash * 0.34, 1.0)
	$Pig.rotation.z = lerpf(-0.16, 0.0, falling) + sin(landed * 16.0) * 0.035 * (1.0 - smoothstep(0.1, 0.5, landed))
	$Pig.modulate.a = fade
	$Pig.visible = landed < 0.70

func reset() -> void:
	drop_id = -1
	active = false
	hide()
