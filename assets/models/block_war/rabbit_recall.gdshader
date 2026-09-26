shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float visual_time = 0.0;
uniform vec4 wave_color : source_color = vec4(0.73, 0.95, 0.86, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float waves = 0.0;
	for (int i = 0; i < 3; i++) {
		float phase = (visual_time - float(i) * 0.22) / 1.15;
		float enabled = step(0.0, phase) * (1.0 - step(1.0, phase));
		float front = mix(0.08, 0.98, clamp(phase, 0.0, 1.0));
		float line = 1.0 - smoothstep(0.012, 0.026, abs(radius - front));
		waves += line * enabled * (1.0 - smoothstep(0.65, 1.0, phase));
	}
	float boundary = (1.0 - smoothstep(0.010, 0.018, abs(radius - 0.99)));
	boundary *= (0.36 + 0.24 * sin(atan(p.y, p.x) * 16.0)) * (1.0 - smoothstep(0.9, 1.65, visual_time));
	ALBEDO = mix(wave_color.rgb, vec3(0.96, 0.99, 0.90), 0.55);
	EMISSION = ALBEDO * 0.35;
	ALPHA = min(0.85, waves * 0.76 + boundary) * (1.0 - smoothstep(0.985, 1.0, radius));
}
