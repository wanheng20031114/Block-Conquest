shader_type spatial;
uniform vec3 base_tint : source_color = vec3(0.46, 0.30, 0.12);
varying float pulse;

void vertex() {
	pulse = INSTANCE_CUSTOM.r;
}

void fragment() {
	ALBEDO = mix(base_tint, vec3(1.0, 0.88, 0.52), pulse * 0.8);
	METALLIC = 0.68;
	ROUGHNESS = 0.30;
	EMISSION = vec3(1.0, 0.67, 0.20) * pulse * 1.8;
}
