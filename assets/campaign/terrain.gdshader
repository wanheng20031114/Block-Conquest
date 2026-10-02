shader_type spatial;
render_mode diffuse_burley;
#include "res://assets/campaign/unfold.gdshaderinc"

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world = unfold_column(world, MODEL_MATRIX[3].xyz);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
}
