shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float age = max(0.0, effect.a - effect.r * 0.055);
    vec2 curved = p + vec2(0.13, 0.26);
    float angle = atan(curved.y, curved.x);
    float front = mix(-0.75, 2.95, clamp(age / 0.21, 0.0, 1.0));
    float tail = smoothstep(front - 1.9, front - 0.1, angle) * (1.0 - smoothstep(front, front + 0.17, angle));
    float radius = 0.78 + 0.055 * sin(angle * 2.0);
    float distance_to_blade = abs(length(curved) - radius);
    float core = exp(-pow(distance_to_blade * 60.0, 2.0));
    float wake = exp(-pow(distance_to_blade * 13.0, 2.0));
    float edge = 1.0 - smoothstep(0.83, 1.08, length(p));
    float dissolve = 1.0 - smoothstep(0.26, 0.67, age);
    ALBEDO = mix(vec3(0.35, 0.66, 0.38), vec3(0.97, 1.0, 0.74), core);
    EMISSION = vec3(0.70, 0.92, 0.42) * core * 0.65;
    ALPHA = min(0.96, core + wake * 0.48) * tail * edge * dissolve;
}
