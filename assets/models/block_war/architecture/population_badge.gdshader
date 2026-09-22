shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}

// Four equal circular petals and a central disk form one unbroken silhouette.
// Mirroring both axes deliberately keeps every petal identical.
float flower_distance(vec2 p) {
	float petals = length(abs(p) - vec2(0.38)) - 0.46;
	return min(petals, length(p) - 0.34);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float distance = flower_distance(p);
	float aa = max(fwidth(distance), 0.002);
	float face = 1.0 - smoothstep(-aa, aa, distance);
	float shadow = (1.0 - smoothstep(-0.02, 0.08, flower_distance(p - vec2(0.0, 0.055)))) * 0.20;
	float alpha = face + shadow * (1.0 - face);
	float rim = smoothstep(-0.06, 0.0, distance);
	vec3 porcelain = mix(vec3(1.0, 0.995, 0.975), vec3(0.84, 0.86, 0.82), rim * 0.24);
	ALBEDO = mix(vec3(0.10, 0.15, 0.12), porcelain, face / max(alpha, 0.001));
	ALPHA = alpha;
}
