shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled;
uniform float progress = 0.0;
void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 1.6);
	vec3 warm = mix(vec3(1.0, 0.49, 0.12), vec3(1.0, 0.9, 0.57), 1.0 - progress);
	ALBEDO = warm;
	EMISSION = warm * (1.0 - progress) * 1.5;
	ALPHA = (0.30 + rim * 0.35) * (1.0 - progress) * (1.0 - progress);
}
