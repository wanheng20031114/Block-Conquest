shader_type spatial;

uniform sampler2D ground_detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 grass_dark : source_color = vec4(0.19, 0.32, 0.19, 1.0);
uniform vec4 grass_light : source_color = vec4(0.33, 0.45, 0.26, 1.0);
uniform vec4 soil_color : source_color = vec4(0.49, 0.43, 0.29, 1.0);
varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - (a + d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0)));
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = world_position.xz;
	float broad = sin(p.x * 0.13 + sin(p.y * 0.17) * 1.6) * cos(p.y * 0.16 + sin(p.x * 0.21) * 0.8);
	float large = 0.48 + broad * 0.28 + sin(p.x * 0.43 + p.y * 0.27) * sin(p.y * 0.34) * 0.08 + noise(p * 1.8) * 0.08;
	vec3 color = mix(grass_dark.rgb, grass_light.rgb, smoothstep(0.16, 0.87, large));
	float road = min(segment_distance(p, vec2(-30.0, 3.0), vec2(-22.0, 5.0)), segment_distance(p, vec2(30.0, 3.0), vec2(22.0, 5.0)));
	road = min(road, segment_distance(p, vec2(-24.0, -12.0), vec2(-15.0, -14.0)));
	road = min(road, segment_distance(p, vec2(24.0, 15.0), vec2(15.0, 14.0)));
	road = min(road, segment_distance(p, vec2(-28.0, 18.0), vec2(-15.0, 14.0)));
	road = min(road, segment_distance(p, vec2(28.0, -16.0), vec2(15.0, -14.0)));
	road = min(road, segment_distance(p, vec2(-9.0, -14.0), vec2(9.0, -14.0)));
	road = min(road, segment_distance(p, vec2(-9.0, 14.0), vec2(9.0, 14.0)));
	float worn = 1.0 - smoothstep(0.6, 2.5, road + (noise(p * 1.2) - 0.5) * 1.3);
	color = mix(color, soil_color.rgb, worn * (0.45 + noise(p * 0.65) * 0.25));
	vec3 detail = texture(ground_detail, p / 5.5).rgb;
	ALBEDO = color * mix(vec3(0.78), vec3(1.18), detail);
	ROUGHNESS = 0.97;
}
