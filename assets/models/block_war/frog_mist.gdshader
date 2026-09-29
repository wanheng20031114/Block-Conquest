shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() {
	terrain_clearance = 0.22 + INSTANCE_CUSTOM.r * 0.46;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
	effect = INSTANCE_CUSTOM;
}
void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
    vec2 p = (UV - 0.5) * 2.0;
    float t = visual_time * 0.48 + effect.r * 2.1;
    float bank = 0.58 + 0.18 * sin(p.x * 3.0 + t) + 0.13 * cos(p.y * 3.8 - t * 0.7);
    float edge = 1.0 - smoothstep(0.50, 1.0, length(p) + sin(p.y * 3.0 + t) * 0.065);
    ALBEDO = mix(vec3(0.44, 0.57, 0.48), vec3(0.81, 0.86, 0.70), bank);
    ALPHA = edge * bank * 0.24 * smoothstep(0.0, 0.12, effect.a);
}
