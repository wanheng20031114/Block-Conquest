shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 tint;
void vertex() { tint = INSTANCE_CUSTOM; }
void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (1.0 - smoothstep(0.15, 0.5, abs(UV.y - 0.5)));
}
