shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_base : source_color = vec4(0.47, 0.49, 0.29, 1.0);
uniform vec4 grass_shade : source_color = vec4(0.365, 0.405, 0.265, 1.0);
uniform vec4 grass_light : source_color = vec4(0.60, 0.585, 0.34, 1.0);
varying vec3 world_position;

#include "res://assets/block_war/environment/meadow_surface.gdshaderinc"

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 grass = painted_meadow(world_position.xz, grass_base.rgb, grass_shade.rgb, grass_light.rgb);
	ALBEDO = mix(grass, grass_shade.rgb * 0.85, meadow_blades(world_position.xz) * 0.24);
	ROUGHNESS = 0.96;
}
