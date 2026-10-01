shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() {
	terrain_clearance = 0.095;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
	effect = INSTANCE_CUSTOM;
}
void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float hostile = effect.r;
	float age = effect.b;
	float fade = smoothstep(0.0, 0.22, age) * smoothstep(0.0, 0.055, effect.a);
	float rim = smoothstep(0.025, 0.004, abs(r - 0.87));
	float sections = smoothstep(0.20, 0.32, abs(sin(angle * 6.0)));
	float inner = smoothstep(0.013, 0.003, abs(r - 0.72));
	float ticks = pow(max(0.0, cos(angle * 12.0)), 20.0) * smoothstep(0.72, 0.76, r) * (1.0 - smoothstep(0.85, 0.90, r));
	float fracture = pow(max(0.0, cos(angle * 7.0 + r * 9.0)), 90.0) * smoothstep(0.6, 0.68, r) * (1.0 - smoothstep(0.94, 1.0, r));
	float pulse = 0.75 + 0.25 * sin(visual_time * 3.0 + angle * 2.0);
	vec3 bronze = vec3(0.54, 0.35, 0.13);
	vec3 ember = vec3(0.94, 0.20, 0.055);
	ALBEDO = mix(bronze, ember, hostile);
	ALPHA = (rim * sections * 0.48 + inner * 0.13 + ticks * 0.32 + fracture * hostile * 0.45) * fade * pulse;
}
