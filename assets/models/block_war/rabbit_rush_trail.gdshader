shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float along = (p.y + 1.0) * 0.5;
	// A narrow lance with a sharp forward tip and a longer transparent tail.
	float width = pow(max(sin(along * 3.1415926), 0.0), 1.6) * mix(0.7, 0.25, along);
	float slash = 1.0 - smoothstep(width * 0.55, width + 0.04, abs(p.x));
	float fade = smoothstep(0.0, 0.18, along) * (1.0 - smoothstep(0.78, 1.0, along));
	float core = 1.0 - smoothstep(0.0, 0.10, abs(p.x));
	ALBEDO = mix(COLOR.rgb, vec3(1.0, 0.34, 0.17), core * 0.26);
	EMISSION = ALBEDO * 0.34;
	ALPHA = slash * fade * COLOR.a * 0.90;
}
