shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform float age = 0.0;
uniform float expansion_time = 0.28;
uniform float ignition_ratio = 0.1;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float edge = mix(ignition_ratio, 1.0, clamp(age / expansion_time, 0.0, 1.0));
	float angle = atan(p.y, p.x);
	float grain = sin(angle * 21.0 + r * 49.0) * sin(r * 68.0 - age * 12.0);
	float inside = 1.0 - smoothstep(edge - 0.015, edge + 0.025, r);
	float front = exp(-abs(r - edge) * 25.0) * inside;
	float cracks = pow(max(0.0, sin(r * 75.0 + grain * 2.0)), 9.0);
	float heat = (front * 0.9 + cracks * 0.26) * (1.0 - smoothstep(1.95, 2.35, age));
	ALBEDO = mix(vec3(0.12, 0.065, 0.025), vec3(1.0, 0.20, 0.015), heat);
	EMISSION = vec3(1.0, 0.32, 0.035) * heat * 1.8;
	ALPHA = inside * (0.24 + heat * 0.7) * (1.0 - smoothstep(2.35, 3.0, age)) * (1.0 - smoothstep(0.97, 1.02, r));
}
