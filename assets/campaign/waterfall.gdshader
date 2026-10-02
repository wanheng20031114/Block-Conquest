shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/campaign/unfold.gdshaderinc"

varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(unfold_column(world_position, MODEL_MATRIX[3].xyz), 1.0)).xyz;
}
void fragment() {
	float streak = sin(world_position.y * 9.0 + TIME * 4.2 + sin(world_position.x * 12.0));
	float foam = smoothstep(0.75, 1.0, streak) * 0.25;
	ALBEDO = vec3(0.13, 0.45, 0.48) + foam;
	ROUGHNESS = 0.25;
	SPECULAR = 0.75;
}
