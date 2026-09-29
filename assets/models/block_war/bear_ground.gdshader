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
    float edge = 0.95 + 0.025 * sin(angle * 7.0) + 0.015 * cos(angle * 11.0);
    float border = smoothstep(edge - 0.075, edge - 0.02, r) * (1.0 - smoothstep(edge - 0.015, edge, r));
    float broken = smoothstep(0.12, 0.30, abs(sin(angle * 9.0 + sin(angle * 4.0))));
    float cracks = pow(max(0.0, cos(angle * 7.0 + r * 5.0)), 65.0) * smoothstep(0.3, 0.55, r) * (1.0 - smoothstep(0.8, 0.95, r));
    float pad = 1.0 - smoothstep(0.22, 0.245, length((p - vec2(0.0, 0.12)) * vec2(1.0, 1.25)));
    float toes = 0.0;
    for (int i = 0; i < 4; i++) {
        float a = float(i) * 0.58 - 2.44;
        vec2 c = vec2(cos(a), sin(a)) * 0.35;
        toes = max(toes, 1.0 - smoothstep(0.075, 0.095, length(p - c)));
    }
    float age = (1.0 - effect.a) * 4.0;
    float ripple = pow(max(0.0, 1.0 - abs(r - age * 2.65) / 0.075), 2.0) * (1.0 - smoothstep(0.24, 0.39, age));
    float echo = pow(max(0.0, 1.0 - abs(r - max(0.0, age - 0.10) * 2.0) / 0.055), 2.0) * smoothstep(0.10, 0.15, age) * (1.0 - smoothstep(0.39, 0.57, age));
    float fade = smoothstep(0.0, 0.12, effect.a);
    ALBEDO = mix(vec3(0.36, 0.27, 0.13), vec3(0.91, 0.74, 0.39), clamp(border + ripple + echo, 0.0, 1.0));
    ALPHA = min(0.65, (border * broken * 0.7 + cracks * 0.42 + (pad + toes) * 0.2 + ripple * 0.68 + echo * 0.35)) * fade;
}
