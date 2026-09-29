shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"

varying vec4 burst_data;

void vertex() {
	terrain_clearance = 0.085;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;

	burst_data = INSTANCE_CUSTOM;
}

void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float progress = clamp(burst_data.a, 0.0, 1.0);
	float fade = 1.0 - smoothstep(0.32, 1.0, progress);
	float front = mix(0.16, 0.96, 1.0 - pow(1.0 - progress, 2.0));
	float ring = 1.0 - smoothstep(0.018, 0.048, abs(radius - front));
	// Short pointed rays replace the old persistent wind-and-leaf field.
	float segment = abs(fract(angle / 6.2831853 * 12.0 + 0.5) - 0.5);
	float ray_width = 0.16 * (1.0 - smoothstep(front * 0.52, front, radius));
	float rays = 1.0 - smoothstep(ray_width, ray_width + 0.025, segment);
	rays *= smoothstep(front * 0.32, front * 0.48, radius) * (1.0 - smoothstep(front * 0.86, front, radius));
	ALBEDO = burst_data.rgb;
	EMISSION = burst_data.rgb * 0.42;
	ALPHA = min(0.88, ring * 0.82 + rays * 0.58) * fade;
}
