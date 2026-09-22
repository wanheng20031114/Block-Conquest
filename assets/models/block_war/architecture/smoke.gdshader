shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	float puff = 1.0 - smoothstep(0.12, 0.50, length(UV - vec2(0.5)));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * puff * 0.20;
}
