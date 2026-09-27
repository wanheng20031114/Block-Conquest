shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    ALBEDO = COLOR.rgb;
    ALPHA = (1.0 - smoothstep(0.15, 1.0, length(p))) * COLOR.a * 0.15;
}
