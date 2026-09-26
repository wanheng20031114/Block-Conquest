shader_type spatial;
render_mode cull_disabled;

#include "res://assets/block_war/environment/water_surface.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The linear distance field follows the union shore, including island holes.
	float distance_to_bank = COLOR.g * 8.0;
	vec3 water_normal;
	paint_water(world_position.xz, distance_to_bank, ALBEDO, water_normal, ROUGHNESS);
	NORMAL = normalize((VIEW_MATRIX * vec4(water_normal, 0.0)).xyz);
	METALLIC = reflection_strength;
	SPECULAR = 0.65;
}
