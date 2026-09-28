shader_type spatial;

instance uniform vec4 team_tint : source_color = vec4(0.22, 0.62, 0.48, 1.0);

void fragment() {
	float facet = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.28, 0.65, 1.25);
	ALBEDO = team_tint.rgb * facet;
	EMISSION = team_tint.rgb * facet * 0.45;
	METALLIC = 0.12;
	ROUGHNESS = 0.34;
}
