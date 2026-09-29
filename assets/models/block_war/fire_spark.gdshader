shader_type spatial;
render_mode blend_mix, unshaded, shadows_disabled;
#include "res://assets/models/block_war/terrain_height.gdshaderinc"

uniform float emitter_surface_height = 0.0;
uniform vec4 spark_color : source_color = vec4(1.0, 0.48, 0.08, 1.0);
uniform vec4 spark_emission : source_color = vec4(1.0, 0.24, 0.02, 1.0);

void vertex() {
	if (terrain_enabled) {
		vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
		world.y += terrain_height(MODEL_MATRIX[3].xz) - emitter_surface_height;
		VERTEX = (inverse(MODEL_MATRIX) * world).xyz;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * spark_color.rgb;
	EMISSION = spark_emission.rgb * 1.8;
	ALPHA = COLOR.a;
}
