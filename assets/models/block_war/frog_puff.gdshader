shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float lobes = 0.09 * sin(p.x * 8.0 + p.y * 3.0) + 0.06 * cos(p.y * 11.0 - p.x * 2.0);
    float volume = 1.0 - smoothstep(0.05, 0.97, length(p) + lobes);
    ALBEDO = COLOR.rgb * (0.78 + 0.22 * (1.0 - UV.y));
    ALPHA = volume * COLOR.a * 0.24;
}
