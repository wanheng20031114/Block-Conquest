shader_type spatial;
render_mode cull_disabled;

uniform float visual_time = 0.0;
instance uniform vec4 cloth_color : source_color = vec4(0.31, 0.48, 0.36, 1.0);
instance uniform float response = 0.0;

void vertex() {
	float edge = clamp(VERTEX.x / 1.35, 0.0, 1.0);
	float amplitude = 0.13 + response * 0.10;
	VERTEX.z += sin(visual_time * 2.8 - VERTEX.x * 4.1) * amplitude * edge;
	VERTEX.y += sin(visual_time * 1.6 + VERTEX.x * 2.7) * 0.045 * edge;
}

void fragment() {
	vec2 p = abs(UV - vec2(0.49, 0.5));
	float diamond = 1.0 - smoothstep(0.18, 0.20, p.x + p.y * 0.72);
	ALBEDO = mix(cloth_color.rgb, vec3(0.95, 0.90, 0.71), diamond);
	ROUGHNESS = 0.95;
}
