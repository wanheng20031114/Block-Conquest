shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 half_size = vec2(40.0, 28.0);
uniform vec4 meadow : source_color = vec4(0.29, 0.405, 0.235, 1.0);
uniform vec4 grass_shadow : source_color = vec4(0.16, 0.265, 0.205, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.395, 0.485, 0.295, 1.0);
uniform vec4 soil : source_color = vec4(0.49, 0.445, 0.355, 1.0);
uniform int site_count = 0;
uniform vec2 sites[64];
uniform int path_count = 0;
uniform vec4 paths[64];
varying vec3 world_position;

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / max(dot(d, d), 0.01), 0.0, 1.0));
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_position.xz;
	float broad = texture(meadow_noise, p / 99.0 + vec2(0.23, 0.17)).r;
	float patches = texture(meadow_noise, p / 22.0 + vec2(0.41, 0.76)).r;
	float detail = texture(meadow_noise, p / 5.8).r;
	vec3 color = mix(meadow.rgb, grass_sunlit.rgb, smoothstep(0.22, 0.79, broad));
	color = mix(color, grass_shadow.rgb, smoothstep(0.58, 0.86, patches) * 0.24);
	float edge = max(smoothstep(half_size.x - 9.0, half_size.x + 4.0, abs(p.x) + (patches - 0.5) * 7.0), smoothstep(half_size.y - 4.0, half_size.y + 8.0, abs(p.y) + (broad - 0.5) * 7.0));
	color = mix(color, grass_shadow.rgb, edge * 0.82);
	float yard = 0.0;
	for (int i = 0; i < site_count; i++) {
		float footprint = length((p - sites[i]) / vec2(2.65, 2.38));
		float settlement = 1.0 - smoothstep(0.74, 1.39, footprint + (detail - 0.5) * 0.3);
		float doorway = 1.0 - smoothstep(0.6, 1.35, segment_distance(p, sites[i] + vec2(0.0, 0.8), sites[i] + vec2(0.0, 3.2)));
		yard = max(yard, max(settlement * 0.84, doorway * 0.81));
	}
	float trail = 0.0;
	for (int i = 0; i < path_count; i++) {
		trail = max(trail, 1.0 - smoothstep(0.72, 1.82, segment_distance(p, paths[i].xy, paths[i].zw) + (patches - 0.5) * 1.8 + (detail - 0.5) * 0.28));
	}
	color = mix(color, soil.rgb * (0.97 + patches * 0.07), max(yard, trail * 0.60));
	color = mix(color, soil.rgb * 0.68, smoothstep(0.2, 1.5, -world_position.y));
	ALBEDO = color * (0.97 + detail * 0.06);
	ROUGHNESS = 0.95;
}
