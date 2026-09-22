shader_type spatial;

instance uniform vec4 team_color : source_color = vec4(1.0, 0.65, 0.18, 1.0);
uniform float surface_roughness = 0.48;

void fragment() {
	float dye_shade = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.16, 0.86, 1.12);
	ALBEDO = team_color.rgb * dye_shade;
	METALLIC = 0.2;
	ROUGHNESS = surface_roughness;
}
