class_name WarSurfaceEffects
extends RefCounted
## The same authored planar zones drive the simulation and GPU ground effects.

const MAX_ZONES := 16

static func configure(material: ShaderMaterial, definition: WarMapDefinition) -> void:
	assert(definition.height_zones.size() <= MAX_ZONES)
	var regions := PackedVector4Array()
	var profiles := PackedVector3Array()
	regions.resize(MAX_ZONES)
	profiles.resize(MAX_ZONES)
	for index: int in definition.height_zones.size():
		var zone: WarHeightZone = definition.height_zones[index]
		regions[index] = Vector4(zone.region.position.x, zone.region.position.y, zone.region.size.x, zone.region.size.y)
		profiles[index] = Vector3(zone.start_height, zone.end_height, zone.axis)
	material.set_shader_parameter("terrain_zone_count", definition.height_zones.size())
	material.set_shader_parameter("terrain_regions", regions)
	material.set_shader_parameter("terrain_profiles", profiles)

static func offset_point(definition: WarMapDefinition, origin: Vector3, offset: Vector3) -> Vector3:
	var at := origin + offset
	if definition.height_zones.is_empty():
		return at
	var lift := origin.y - definition.surface_height(Vector2(origin.x, origin.z))
	return definition.surface_point(at) + Vector3.UP * (lift + offset.y)
