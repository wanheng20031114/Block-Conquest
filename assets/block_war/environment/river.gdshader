shader_type spatial;
render_mode cull_disabled;

#include "res://assets/block_war/environment/water_surface.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	// This analytic shore also defines the original rift's bank mesh.
	float center = p.x < 0.0 ? -12.0 : 12.0;
	float side = -sign(p.x - center);
	float approach = smoothstep(3.7, 5.4, abs(abs(p.y) - 14.0));
	float reach = 0.08 + (0.67 + 0.38 * sin(p.y * 0.25 + center * 0.42) + side * 0.26 * cos(p.y * 0.64)) * approach;
	float distance_to_bank = 3.0 - reach - 0.59 - abs(p.x - center);
	vec3 water_normal;
	paint_water(world_position.xz, distance_to_bank, ALBEDO, water_normal, ROUGHNESS);
	NORMAL = normalize((VIEW_MATRIX * vec4(water_normal, 0.0)).xyz);
	METALLIC = reflection_strength;
	SPECULAR = 0.65;
}
