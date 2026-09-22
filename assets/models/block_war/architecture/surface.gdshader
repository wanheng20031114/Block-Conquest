shader_type spatial;

uniform float metalness = 0.0;
uniform float surface_roughness = 0.78;
uniform float tint_strength = 0.0;
instance uniform vec4 team_tint : source_color = vec4(0.33, 0.47, 0.50, 1.0);

void fragment() {
	// Broad sculpted forms carry the detail; clean colors keep the arena readable.
	// Retain each baked tile's shade while replacing its hue with ownership color.
	float dye_shade = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.23, 0.52, 1.0);
	ALBEDO = mix(COLOR.rgb, team_tint.rgb * dye_shade, tint_strength);
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.26;
}
