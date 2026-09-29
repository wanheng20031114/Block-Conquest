shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x), mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float billow = noise(p * 3.8) * 0.65 + noise(p * 7.6) * 0.35;
	float body = 1.0 - smoothstep(0.08, 1.0, length(p) + (billow - 0.5) * 0.28);
	ALBEDO = vec3(0.57, 0.54, 0.44) * (0.80 + billow * 0.20);
	ALPHA = body * (0.65 + billow * 0.35) * COLOR.a * 0.48;
}
