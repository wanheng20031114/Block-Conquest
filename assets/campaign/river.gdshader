shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/campaign/unfold.gdshaderinc"

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(unfold_column(world_position, MODEL_MATRIX[3].xyz), 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float waves = sin(p.x * 3.8 + p.y * 2.1 + TIME * 1.15);
	float cross_wave = sin(p.y * 6.8 - p.x * 1.3 - TIME * 1.6);
	float ribbons = smoothstep(0.92, 1.0, waves) * smoothstep(0.6, 1.0, sin(p.y * 1.9 - p.x * 1.4));
	ALBEDO = mix(vec3(0.12, 0.43, 0.46), vec3(0.32, 0.65, 0.65), 0.28 + waves * 0.10) + ribbons * 0.09;
	NORMAL_MAP = vec3(0.5 + waves * 0.026, 0.5 + cross_wave * 0.018, 1.0);
	NORMAL_MAP_DEPTH = 0.65;
	ROUGHNESS = 0.23;
	METALLIC = 0.35;
	SPECULAR = 0.8;
}
