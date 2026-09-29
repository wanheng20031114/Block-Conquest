shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
uniform float age = 0.0;
uniform int kind = 0;
uniform vec4 tint : source_color = vec4(0.95, 0.61, 0.24, 1.0);
void vertex() {
	terrain_clearance = 0.10;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
}
void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float front = clamp(age * 3.6, 0.0, 0.96);
	float band = 1.0 - smoothstep(0.018, 0.055, abs(r - front));
	float glow = exp(-abs(r - front) * 22.0) * 0.24;
	float fade = 1.0 - smoothstep(0.28, 0.68, age);
	// Broad, restrained arcs read as a sweep. Panic breaks into outward rays.
	float mask = kind == 3 ? smoothstep(0.35, 0.65, cos(angle * 8.0)) : 0.85;
	float center = kind == 0 ? exp(-r * 8.0) * (1.0 - smoothstep(0.0, 0.20, age)) : 0.0;
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * (band * 0.75 + center * 1.4);
	ALPHA = clamp((band * 0.65 + glow) * mask + center * 0.65, 0.0, 0.8) * fade;
}
