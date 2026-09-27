shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float age = effect.a;
    float t = clamp(age / 0.16, 0.0, 1.0);
    float front = mix(-1.2, 1.2, t);
    float cut = exp(-pow((p.x - front + p.y * 0.42) * 15.0, 2.0));
    float leaf = 1.0 - smoothstep(0.72, 1.0, length(p * vec2(0.82, 1.15)));
    float scar = exp(-pow((p.x + p.y * 0.42) * 24.0, 2.0)) * (1.0 - smoothstep(0.14, 0.45, age));
    ALBEDO = mix(vec3(0.26, 0.45, 0.34), vec3(0.92, 0.97, 0.73), cut);
    ALPHA = leaf * min(0.9, cut * 0.9 + scar * 0.25) * (1.0 - smoothstep(0.40, 0.55, age));
}
