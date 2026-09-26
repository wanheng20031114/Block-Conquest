shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect_data;
void vertex() { effect_data = INSTANCE_CUSTOM; }
void fragment() {
	float ribs = pow(abs(cos(UV.x * 12.0 * 3.14159)), 32.0);
	float lower = exp(-abs(UV.y - 0.9) * 45.0);
	float crest = exp(-abs(UV.y - 0.15) * 50.0);
	float rise = fract(visual_time * 0.23 + UV.x * 2.0);
	float glint = exp(-abs(UV.y - (1.0 - rise)) * 40.0) * ribs;
	float fade = smoothstep(0.0, 0.15, effect_data.a);
	ALBEDO = mix(vec3(0.73, 0.85, 0.84), effect_data.rgb, 0.23);
	EMISSION = ALBEDO * (lower * 0.4 + glint * 0.3);
	ALPHA = (0.025 + ribs * 0.18 + lower * 0.46 + crest * 0.055 + glint * 0.24) * fade;
}
