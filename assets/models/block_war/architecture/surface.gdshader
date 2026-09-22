shader_type spatial;

uniform float metalness = 0.0;
uniform float surface_roughness = 0.78;
uniform float tint_strength = 0.0;
instance uniform vec4 team_tint : source_color = vec4(0.58, 0.42, 0.33, 1.0);

void fragment() {
	// Broad sculpted forms carry the detail; clean colors keep the arena readable.
	float dye_shade = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.14, 0.88, 1.12);
	ALBEDO = mix(COLOR.rgb, team_tint.rgb * dye_shade, tint_strength);
	METALLIC = metalness;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.32;
}
