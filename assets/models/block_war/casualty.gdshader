shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying vec4 casualty;
void vertex() {
	casualty = INSTANCE_CUSTOM;
}
void fragment() {
	vec3 uniform_color = casualty.rgb * 0.72 + vec3(0.07, 0.06, 0.05);
	vec3 base = mix(COLOR.rgb, uniform_color, step(0.75, COLOR.a));
	float flash = 1.0 - smoothstep(0.0, 0.20, casualty.a);
	ALBEDO = mix(base, vec3(1.0, 0.74, 0.31), flash * 0.5);
	EMISSION = vec3(1.0, 0.42, 0.08) * flash * 0.4;
	ROUGHNESS = 0.9;
	ALPHA = 1.0 - smoothstep(0.48, 1.0, casualty.a);
}
