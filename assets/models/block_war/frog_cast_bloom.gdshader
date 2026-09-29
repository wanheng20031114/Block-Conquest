shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
varying vec4 effect;

void vertex() {
	terrain_clearance = 0.16;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
	effect = INSTANCE_CUSTOM;
}

void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = (UV - 0.5) * 2.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float age = effect.a;
	float front = mix(0.14, 0.92, smoothstep(0.0, 0.52, age));
	float wave = exp(-pow((radius - front) * 24.0, 2.0));
	float ripples = 0.65 + 0.35 * sin(angle * 5.0 + radius * 12.0 - age * 6.0);
	float inner = exp(-radius * radius * 6.0) * (1.0 - smoothstep(0.03, 0.27, age));
	vec3 tint = effect.r < 0.5 ? vec3(0.47, 0.64, 0.39) : (effect.r < 1.5 ? vec3(0.53, 0.86, 0.76) : vec3(0.40, 0.54, 0.46));
	ALBEDO = tint;
	EMISSION = tint * wave * 0.10;
	ALPHA = (wave * ripples * 0.38 + inner * 0.12) * (1.0 - smoothstep(0.18, 0.85, age));
}
