shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

void vertex() {
	// Screen-facing punctuation stays legible at the tactical camera angle.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	float phase = INSTANCE_CUSTOM.a;
	float angle = sin(phase * 1.7) * 0.10;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	VERTEX.y += sin(phase * 0.8) * 0.045;
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	// A warm exclamation mark echoes the cast effect, with a narrow dark edge.
	float bar = max(abs(p.x) - mix(0.10, 0.145, clamp((0.15 - p.y) / 0.5, 0.0, 1.0)), abs(p.y + 0.13) - 0.23);
	float dot = length((p - vec2(0.0, 0.31)) * vec2(1.0, 1.60)) - 0.13;
	float shape = min(bar, dot);
	float aa = max(fwidth(shape), 0.005);
	float ink = 1.0 - smoothstep(-aa, aa, shape);
	ALBEDO = mix(vec3(0.055, 0.016, 0.004), vec3(1.0, 0.20, 0.025), ink);
	EMISSION = vec3(0.15, 0.018, 0.001) * ink;
	ALPHA = 1.0 - smoothstep(0.035 - aa, 0.035 + aa, shape);
}
