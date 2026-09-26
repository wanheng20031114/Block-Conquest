shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float width = (1.0 - p.y * p.y) * 0.8;
	float ribbon = 1.0 - smoothstep(width * 0.2, width, abs(p.x));
	float tip = 1.0 - smoothstep(0.55, 1.0, abs(p.y));
	ALBEDO = COLOR.rgb;
	ALPHA = ribbon * tip * COLOR.a * 0.65;
}
