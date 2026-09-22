shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(2.0, 1.12);
	vec2 q = abs(p) - vec2(0.83, 0.39);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.14;
	float edge = smoothstep(-0.045, -0.005, distance);
	ALBEDO = mix(vec3(0.96, 0.925, 0.81), vec3(0.77, 0.735, 0.63), edge * 0.38);
	ALPHA = (1.0 - smoothstep(-0.012, 0.012, distance)) * 0.96;
}
