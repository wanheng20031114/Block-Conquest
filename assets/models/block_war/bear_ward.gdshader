shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect;
varying vec3 direction;
void vertex() { effect = INSTANCE_CUSTOM; direction = normalize(VERTEX); }
void fragment() {
    vec3 d = normalize(direction);
    float age = effect.b;
    float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    vec3 light = normalize(vec3(cos(visual_time * 0.8), 0.75, sin(visual_time * 0.8)));
    float sheen = pow(max(dot(d, light), 0.0), 32.0);
    float front = mix(-1.15, 1.25, clamp(age / 0.16, 0.0, 1.0));
    float across = d.x * 0.85 + d.y * 0.35 + d.z * 0.4;
    float sweep = (1.0 - smoothstep(0.02, 0.07, abs(across - front))) * (1.0 - smoothstep(0.15, 0.20, age));
    float visible = smoothstep(-0.03, 0.04, front - across);
    ALBEDO = mix(vec3(0.76, 0.49, 0.14), vec3(1.0, 0.93, 0.63), sheen);
    ROUGHNESS = 0.18;
    SPECULAR = 0.8;
    CLEARCOAT = 0.6;
    EMISSION = vec3(0.95, 0.69, 0.25) * (rim * 0.25 + sheen * 0.5 + sweep * 0.65);
    ALPHA = min(0.62, (0.016 + rim * 0.40 + sheen * 0.24) * visible + sweep * 0.42) * smoothstep(0.0, 0.08, effect.a);
}
