shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect_data;
varying vec3 dome_direction;
varying vec3 dome_view_direction;
void vertex() {
	effect_data = INSTANCE_CUSTOM;
	dome_direction = normalize(VERTEX);
	dome_view_direction = (MODELVIEW_MATRIX * vec4(dome_direction, 0.0)).xyz;
}
void fragment() {
	vec3 dome = normalize(dome_direction);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.8);
	// A single diagonal wipe lays down the shell. It never expands from the roof.
	float age = effect_data.r;
	float progress = clamp(age / 0.26, 0.0, 1.0);
	vec3 view_dome = normalize(dome_view_direction);
	float across = dot(view_dome.xy, normalize(vec2(1.0, 0.42))) + view_dome.z * 0.45;
	float front = mix(-0.96, 1.30, progress);
	float behind = front - across;
	float sweep_life = 1.0 - smoothstep(0.23, 0.30, age);
	float crest = (1.0 - smoothstep(0.015, 0.065, abs(behind))) * sweep_life;
	float wake = smoothstep(-0.025, 0.015, behind) * (1.0 - smoothstep(0.045, 0.24, behind)) * sweep_life;
	float revealed = smoothstep(-0.06, 0.035, behind);
	float settled = smoothstep(0.16, 0.34, age);
	// Broad moving reflections restore the original blue bubble without hiding the roof.
	vec3 light_sweep = normalize(vec3(cos(visual_time * 0.7), 0.9, sin(visual_time * 0.7)));
	float sheen = pow(max(dot(dome, light_sweep), 0.0), 28.0);
	float band = pow(0.5 + 0.5 * sin(UV.y * 36.0 - visual_time * 2.2), 12.0);
	float pulse = 0.94 + 0.06 * sin(visual_time * 1.8);
	float fade = smoothstep(0.0, 0.09, effect_data.a);
	vec3 sweep_color = vec3(0.56, 0.88, 1.0);
	ALBEDO = mix(mix(vec3(0.26, 0.63, 0.76), vec3(0.83, 0.96, 1.0), sheen * settled), sweep_color, crest * 0.8);
	ROUGHNESS = 0.16;
	SPECULAR = 0.75;
	CLEARCOAT = 0.65;
	EMISSION = (vec3(0.30, 0.74, 0.9) * (rim * 0.3 + band * 0.055) + vec3(0.7, 0.92, 1.0) * sheen * 0.75) * settled;
	EMISSION += sweep_color * (crest * 0.75 + wake * 0.1);
	float shell_alpha = (0.025 + rim * 0.43 * pulse + (band * 0.018 + sheen * 0.3) * settled) * revealed;
	ALPHA = min(0.72, shell_alpha + crest * 0.38 + wake * 0.095) * fade;
}
