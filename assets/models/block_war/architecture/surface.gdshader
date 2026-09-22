shader_type spatial;

uniform float metalness = 0.0;
uniform float surface_roughness = 0.88;
uniform float grain_strength = 0.055;
uniform float tint_strength = 0.0;
instance uniform vec4 team_tint : source_color = vec4(0.58, 0.42, 0.33, 1.0);
varying vec3 sculpture_position;

float grain(vec3 p) {
	return fract(sin(dot(floor(p), vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	sculpture_position = VERTEX;
}

void fragment() {
	float speckle = (grain(sculpture_position * 115.0) - 0.5) * grain_strength;
	float dye_shade = clamp(dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722)) / 0.095, 0.62, 1.45);
	ALBEDO = mix(COLOR.rgb, team_tint.rgb * dye_shade, tint_strength) * (1.0 + speckle);
	METALLIC = metalness;
	ROUGHNESS = clamp(surface_roughness + speckle * 0.4, 0.0, 1.0);
}
