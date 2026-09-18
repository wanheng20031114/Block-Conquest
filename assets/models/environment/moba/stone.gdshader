shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D grain : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec2 surface_uv;

void vertex() {
	surface_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float wear = dot(texture(grain, surface_uv / 1.7).rgb, vec3(0.3, 0.5, 0.2));
	// ArrayMesh paint and per-instance stone variations are authored in sRGB.
	vec3 stone = mix(COLOR.rgb / 12.92, pow((COLOR.rgb + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb));
	ALBEDO = stone * mix(0.80, 1.15, smoothstep(0.10, 0.40, wear));
	ROUGHNESS = 0.96;
	SPECULAR = 0.0;
}
