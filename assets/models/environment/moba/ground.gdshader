shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D earth : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D woodland : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D variation : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_color : source_color = vec4(0.49, 0.64, 0.47, 1.0);
uniform vec4 earth_color : source_color = vec4(0.74, 0.66, 0.49, 1.0);
uniform float texture_strength : hint_range(0.0, 1.0) = 0.36;
varying vec2 world_uv;

// Large aligned blocks retain a little voxel character. Mirrored sampling keeps
// painted edges continuous, while the palette limits the contrast of each block.
vec2 mirrored(vec2 p) {
	return 1.0 - abs(fract(p * 0.5) * 2.0 - 1.0);
}

void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_uv;
	float broad = texture(variation, p / 61.0).r;
	vec3 grass = mix(grass_color.rgb, texture(meadow, mirrored(p / 8.0)).rgb, texture_strength);
	vec3 soil = mix(earth_color.rgb, texture(earth, mirrored(p / 9.0)).rgb, texture_strength);
	vec3 shade_grass = mix(grass_color.rgb * 0.96, texture(woodland, mirrored(p / 8.0)).rgb, texture_strength);
	// Vertex red stores signed road distance, green stores woodland coverage.
	float road = smoothstep(0.43, 0.54, COLOR.r);
	float forest = smoothstep(0.2, 0.9, COLOR.g);
	grass = mix(grass, shade_grass, forest * 0.45);
	grass *= mix(0.98, 1.02, broad);
	ALBEDO = mix(grass, soil, road);
	ROUGHNESS = 0.96;
	SPECULAR = 0.0;
}
