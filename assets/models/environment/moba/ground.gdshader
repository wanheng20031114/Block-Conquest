shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D meadow : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D earth : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D woodland : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D variation : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(0.82, 0.94, 0.76, 1.0);
uniform vec4 earth_tint : source_color = vec4(0.91, 0.89, 0.82, 1.0);
varying vec2 world_uv;

// Mirroring makes independently painted tile edges continuous. A second, rotated
// grass sample and a much larger noise scale keep the repeat from becoming a grid.
vec2 mirrored(vec2 p) {
	return 1.0 - abs(fract(p * 0.5) * 2.0 - 1.0);
}

void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_uv;
	float broad = texture(variation, p / 47.0).r;
	float edge = texture(variation, p / 5.7).r;
	vec3 grass_a = texture(meadow, mirrored(p / 4.6)).rgb;
	vec2 rotated = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec3 grass_b = texture(meadow, mirrored(rotated / 7.3 + vec2(0.37, 0.19))).rgb;
	vec3 grass = mix(grass_a, grass_b, 0.3) * grass_tint.rgb;
	grass *= mix(0.83, 1.18, smoothstep(0.2, 0.8, broad));
	vec3 soil = texture(earth, mirrored(rotated / 5.1)).rgb * earth_tint.rgb;
	vec3 leaves = texture(woodland, mirrored(p / 5.6)).rgb;
	// Vertex red stores signed road distance, green stores woodland coverage.
	float road = smoothstep(0.40, 0.57, COLOR.r + (edge - 0.5) * 0.13);
	float forest = smoothstep(0.12, 0.87, COLOR.g + (broad - 0.5) * 0.5);
	grass = mix(grass, leaves * 0.91, forest * 0.82);
	// Two shallow wheel-worn strips follow the authored approach lanes.
	float ax = abs(p.x);
	float t = clamp((ax - 12.0) / 23.0, 0.0, 1.0);
	float lane = 10.0 * t * t * (3.0 - 2.0 * t);
	lane *= 1.0 - clamp((ax - 77.0) / 17.0, 0.0, 1.0);
	float lateral = abs(abs(p.y) - lane);
	float track = 1.0 - smoothstep(0.14, 0.40, abs(lateral - 1.12));
	track *= smoothstep(20.0, 29.0, ax) * (1.0 - smoothstep(84.0, 94.0, ax));
	soil *= 1.0 - track * mix(0.03, 0.16, edge);
	ALBEDO = mix(grass, soil, road);
	ROUGHNESS = 0.96;
	SPECULAR = 0.0;
}
