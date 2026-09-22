shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;
uniform float visual_time = 0.0;

void fragment() {
	float center = 1.0 - smoothstep(0.12, 0.62, distance(UV, vec2(0.5)));
	float glow = 0.82 + sin(visual_time * 4.5 + UV.x * 6.0) * 0.11 + sin(visual_time * 7.7) * 0.07;
	float width = 0.24 * (0.4 + UV.y);
	float sway = sin(visual_time * 2.7 + UV.y * 6.0) * 0.055 * (1.0 - UV.y);
	float flame = 1.0 - smoothstep(width * 0.45, width, abs(UV.x - 0.5 + sway));
	flame *= smoothstep(0.0, 0.24, UV.y) * (1.0 - smoothstep(0.85, 1.0, UV.y));
	ALBEDO = mix(vec3(0.55, 0.09, 0.01), vec3(1.0, 0.48, 0.08), center);
	EMISSION = ALBEDO * glow * 1.6;
	ALPHA = flame * 0.82;
}
