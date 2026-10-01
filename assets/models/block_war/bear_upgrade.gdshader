shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
	float progress = effect.r;
	float height = 1.0 - UV.y;
	float front = smoothstep(0.08, 0.95, progress);
	float wave = smoothstep(0.08, 0.015, abs(height - front));
	float column = abs(fract(UV.x * 8.0 + 0.5) - 0.5);
	float chevron = smoothstep(0.027, 0.005, abs(height - front + column * 0.32)) * (1.0 - smoothstep(0.20, 0.25, column));
	float fade = smoothstep(0.04, 0.18, progress) * (1.0 - smoothstep(0.70, 1.0, progress));
	ALBEDO = mix(vec3(0.97, 0.63, 0.19), vec3(1.0, 0.94, 0.60), chevron);
	ALPHA = (wave * 0.16 + chevron * 0.52) * fade;
}
