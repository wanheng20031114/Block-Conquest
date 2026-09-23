shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform float visual_time = 0.0;
varying float flame_seed;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x), mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}
void vertex() {
	flame_seed = fract(sin(float(INSTANCE_ID) * 12.9898) * 43758.5453);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
	float h = 1.0 - UV.y;
	float turbulence = noise(vec2(UV.x * 5.0 + flame_seed * 21.0, h * 7.0 - visual_time * 4.5));
	float sway = sin(h * 6.0 - visual_time * (5.0 + flame_seed * 4.0) + flame_seed * 20.0) * h * 0.16;
	float width = pow(1.0 - h, 1.1) * (0.27 + flame_seed * 0.12);
	float flame = 1.0 - smoothstep(width * 0.4, width + 0.035, abs(UV.x - 0.5 + sway) + (turbulence - 0.5) * 0.16);
	flame *= smoothstep(0.0, 0.20, h) * (1.0 - smoothstep(0.62 + flame_seed * 0.2, 1.0, h));
	vec3 hot = mix(vec3(1.0, 0.64, 0.075), vec3(0.86, 0.10, 0.012), clamp(h + turbulence * 0.2, 0.0, 1.0));
	ALBEDO = hot;
	EMISSION = hot * 0.8;
	ALPHA = flame * COLOR.a * 0.84;
}
