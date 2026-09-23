shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 half_size = vec2(40.0, 28.0);
uniform vec4 meadow : source_color = vec4(0.29, 0.405, 0.235, 1.0);
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
	vec3 color = meadow.rgb * (0.82 + 0.42 * broad);
	float edge = max(smoothstep(half_size.x - 2.0, half_size.x + 14.0, abs(p.x)), smoothstep(half_size.y - 2.0, half_size.y + 14.0, abs(p.y)));
	color *= 1.0 - edge * 0.38;
	float yard = 0.0;
	for (int i = 0; i < site_count; i++) {
		yard = max(yard, 1.0 - smoothstep(2.0, 4.2, length(p - sites[i]) + (detail - 0.5) * 0.7));
	}
	float trail = 0.0;
	for (int i = 0; i < path_count; i++) {
		trail = max(trail, 1.0 - smoothstep(0.5, 1.6, segment_distance(p, paths[i].xy, paths[i].zw) + (patches - 0.5) * 1.3));
	}
	color = mix(color, soil.rgb * (0.94 + patches * 0.12), max(yard * 0.88, trail * 0.54));
	color = mix(color, soil.rgb * 0.68, smoothstep(0.2, 1.5, -world_position.y));
	ALBEDO = color * (0.97 + detail * 0.06);
	ROUGHNESS = 0.95;
}
