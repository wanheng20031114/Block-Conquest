shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float visual_time = 0.0;
uniform float remaining_ratio = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float progress_angle = mod(angle + 1.5707963 + 6.2831853, 6.2831853) / 6.2831853;
	float countdown = 1.0 - smoothstep(remaining_ratio - 0.006, remaining_ratio, progress_angle);
	float rim = 1.0 - smoothstep(0.018, 0.033, abs(radius - 0.91));
	float wake = pow(0.5 + 0.5 * cos(angle * 2.0 - visual_time * 3.2), 8.0);
	float inner = (1.0 - smoothstep(0.017, 0.028, abs(radius - 0.72))) * wake;
	float ticks = step(0.85, cos(angle * 15.0));
	float marks = ticks * smoothstep(0.77, 0.82, radius) * (1.0 - smoothstep(0.86, 0.88, radius));
	ALBEDO = mix(vec3(0.49, 0.89, 0.70), vec3(0.98, 0.85, 0.43), step(remaining_ratio, 0.2));
	EMISSION = ALBEDO * 0.35;
	ALPHA = min(0.85, rim * (0.16 + countdown * 0.63) + inner * 0.65 + marks * countdown * 0.45);
}
