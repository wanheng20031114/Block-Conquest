shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform float age = 0.0;
uniform float windup_time = 0.8;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = clamp(age / 1.15, 0.0, 1.0);
	float angle = atan(p.y, p.x);
	float grain = sin(angle * 21.0 + r * 49.0) * sin(r * 68.0 - age * 12.0);
	float inside = 1.0 - smoothstep(edge - 0.015, edge + 0.025, r);
	float front = exp(-abs(r - edge) * 25.0) * inside;
	float cracks = pow(max(0.0, sin(r * 75.0 + grain * 2.0)), 9.0);
	float heat = (front * 0.9 + cracks * 0.26) * (1.0 - smoothstep(1.95, 2.35, age));
	ALBEDO = mix(vec3(0.12, 0.065, 0.025), vec3(1.0, 0.20, 0.015), heat);
	EMISSION = vec3(1.0, 0.32, 0.035) * heat * 1.8;
	ALPHA = inside * (0.24 + heat * 0.7) * (1.0 - smoothstep(2.35, 3.0, age)) * (1.0 - smoothstep(0.97, 1.02, r));
	if (age < 0.0) {
		float charge = clamp(1.0 + age / windup_time, 0.0, 1.0);
		float boundary = (1.0 - smoothstep(0.008, 0.023, abs(r - 0.97)));
		float embers = pow(max(0.0, sin(p.x * 49.0) * sin(p.y * 57.0 + 1.7)), 12.0);
		float core = exp(-r * 7.0) * (0.15 + charge * 0.4);
		ALBEDO = vec3(0.72, 0.27, 0.035);
		EMISSION = vec3(1.0, 0.43, 0.08) * (boundary * 0.65 + core);
		ALPHA = boundary * (0.48 + charge * 0.3) + core + embers * 0.045 * (1.0 - smoothstep(0.8, 1.0, r));
	}
}
