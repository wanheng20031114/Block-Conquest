class_name WarSurfaceEffects
extends RefCounted
## Simulation and GPU effects sample the same baked triangular height field.

static func configure(material: ShaderMaterial, definition: WarMapDefinition) -> void:
	material.set_shader_parameter("terrain_enabled", definition.has_elevation())
	if not definition.has_elevation():
		material.set_shader_parameter("terrain_heights", null)
		return
	var surface: WarTerrainSurface = definition.terrain
	material.set_shader_parameter("terrain_origin", surface.origin)
	material.set_shader_parameter("terrain_cell_size", surface.cell_size)
	material.set_shader_parameter("terrain_size", Vector2i(surface.width, surface.depth))
	material.set_shader_parameter("terrain_heights", surface.height_texture)

static func offset_point(definition: WarMapDefinition, origin: Vector3, offset: Vector3) -> Vector3:
	var at := origin + offset
	if not definition.has_elevation():
		return at
	var lift := origin.y - definition.surface_height(Vector2(origin.x, origin.z))
	return definition.surface_point(at) + Vector3.UP * (lift + offset.y)
