shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
varying vec4 tint;
void vertex() {
	tint = INSTANCE_CUSTOM;
	terrain_clearance = 0.095;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
}
void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	float radius = length(UV * 2.0 - 1.0);
	float rim = 1.0 - smoothstep(0.04, 0.13, abs(radius - 0.82));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * rim;
}
