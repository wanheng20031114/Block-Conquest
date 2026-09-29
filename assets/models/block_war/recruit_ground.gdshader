shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
uniform float visual_time = 0.0;
varying vec4 effect_data;
void vertex() {
	terrain_clearance = 0.07;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
	effect_data = INSTANCE_CUSTOM;
}
void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float phase = fract(visual_time * 0.65);
	float ripple = exp(-abs(radius - mix(0.4, 0.82, phase)) * 55.0) * sin(phase * 3.14159);
	float rim = exp(-abs(radius - 0.83) * 65.0);
	float dashes = smoothstep(0.1, 0.7, cos(angle * 8.0));
	float fade = smoothstep(0.0, 0.18, effect_data.a);
	ALBEDO = mix(vec3(0.80, 0.74, 0.36), effect_data.rgb, 0.18);
	EMISSION = ALBEDO * 0.25;
	ALPHA = (rim * dashes * 0.42 + ripple * 0.26) * fade;
}
