shader_type spatial;
render_mode cull_disabled;
uniform float age = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.65, 0.18, 1.0);
void vertex() {
	VERTEX.z += sin(UV.x * 4.5 - age * 14.0) * UV.x * 0.12;
}
void fragment() {
	float trim = step(0.10, UV.y) * step(UV.y, 0.90);
	float chevron = 1.0 - smoothstep(0.045, 0.065, abs(UV.x - (0.38 + abs(UV.y - 0.5) * 0.8)));
	ALBEDO = mix(vec3(1.0, 0.93, 0.75), tint.rgb, trim * (1.0 - chevron));
	ROUGHNESS = 0.82;
}
