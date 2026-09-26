shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect_data;
varying vec3 dome_direction;
void vertex() {
	effect_data = INSTANCE_CUSTOM;
	dome_direction = normalize(VERTEX);
}
void fragment() {
	vec3 dome = normalize(dome_direction);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.8);
	// Broad moving reflections restore the original blue bubble without hiding the roof.
	vec3 light_sweep = normalize(vec3(cos(visual_time * 0.7), 0.9, sin(visual_time * 0.7)));
	float sheen = pow(max(dot(dome, light_sweep), 0.0), 28.0);
	float band = pow(0.5 + 0.5 * sin(UV.y * 36.0 - visual_time * 2.2), 12.0);
	float pulse = 0.94 + 0.06 * sin(visual_time * 1.8);
	float fade = smoothstep(0.0, 0.09, effect_data.a);
	ALBEDO = mix(vec3(0.26, 0.63, 0.76), vec3(0.83, 0.96, 1.0), sheen);
	ROUGHNESS = 0.16;
	SPECULAR = 0.75;
	CLEARCOAT = 0.65;
	EMISSION = vec3(0.30, 0.74, 0.9) * (rim * 0.3 + band * 0.055) + vec3(0.7, 0.92, 1.0) * sheen * 0.75;
	ALPHA = (0.025 + rim * 0.43 * pulse + band * 0.018 + sheen * 0.3) * fade;
}
