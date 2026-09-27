shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
varying vec4 effect;
varying vec3 local_direction;
void vertex() { effect = INSTANCE_CUSTOM; local_direction = normalize(VERTEX); }
void fragment() {
    float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.4);
    float turn = (1.0 - effect.a) * 1.2;
    float glint = pow(max(dot(normalize(local_direction), normalize(vec3(-0.6 + sin(turn) * 0.25, 0.75, 0.4))), 0.0), 48.0);
    float base = pow(max(0.0, -local_direction.y), 5.0);
    ALBEDO = vec3(0.60, 0.87, 0.78);
    ROUGHNESS = 0.3;
    SPECULAR = 0.55;
    EMISSION = vec3(0.32, 0.60, 0.46) * (glint * 0.22 + base * 0.06);
    ALPHA = (0.008 + rim * 0.15 + glint * 0.26 + base * 0.08) * smoothstep(0.0, 0.06, effect.a);
}
