shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
	float height = 1.0 - UV.y;
	float sector = floor(UV.x * 8.0);
	float across = fract(UV.x * 8.0) - 0.5;
	float travel = fract(visual_time * 0.6 + sector * 0.37);
	float arrow = smoothstep(0.035, 0.008, abs(height - (1.0 - travel) - abs(across) * 0.40));
	arrow *= (1.0 - smoothstep(0.14, 0.30, abs(across))) * smoothstep(0.0, 0.12, travel) * (1.0 - smoothstep(0.65, 1.0, travel));
	float split = pow(max(0.0, cos(UV.x * 8.0 * 6.283185 + sin(height * 17.0) * 0.35)), 90.0);
	split *= smoothstep(0.15, 0.25, height) * (1.0 - smoothstep(0.45, 0.68, height));
	float fade = smoothstep(0.0, 0.30, effect.b) * smoothstep(0.0, 0.08, effect.a);
	ALBEDO = mix(vec3(0.94, 0.13, 0.045), vec3(1.0, 0.61, 0.20), effect.g * 0.8);
	ALPHA = (arrow * 0.64 + split * 0.22) * fade;
}
