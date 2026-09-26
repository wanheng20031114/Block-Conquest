shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 half_size = vec2(40.0, 28.0);
uniform vec4 meadow : source_color = vec4(0.36, 0.465, 0.20, 1.0);
uniform vec4 grass_shadow : source_color = vec4(0.325, 0.435, 0.178, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.397, 0.497, 0.223, 1.0);
uniform vec4 soil : source_color = vec4(0.50, 0.465, 0.315, 1.0);
uniform int site_count = 0;
uniform vec2 sites[64];
uniform int path_count = 0;
uniform vec4 paths[64];
uniform int bridge_count = 0;
uniform vec4 bridge_regions[16];
varying vec3 world_position;

#include "res://assets/block_war/environment/meadow_surface.gdshaderinc"
#include "res://assets/block_war/environment/woodland_paths.gdshaderinc"

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / max(dot(d, d), 0.01), 0.0, 1.0));
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_position.xz;
	float fringe = meadow_edge_noise(p);
	vec3 color = painted_meadow(p, meadow.rgb, grass_shadow.rgb, grass_sunlit.rgb);
	float edge = max(smoothstep(half_size.x - 3.0, half_size.x + 9.0, abs(p.x)),
		smoothstep(half_size.y, half_size.y + 12.0, abs(p.y)));
	color = mix(color, grass_shadow.rgb, edge * 0.4);
	float yard = 0.0;
	float door_distance = 1000.0;
	for (int i = 0; i < site_count; i++) {
		door_distance = min(door_distance, length(p - sites[i]));
		float footprint = length((p - sites[i]) / vec2(2.65, 2.38));
		float settlement = 1.0 - smoothstep(0.78, 1.21, footprint + fringe * 0.08);
		float doorway = 1.0 - smoothstep(0.48, 1.35, segment_distance(p, sites[i] + vec2(0.0, 0.8), sites[i] + vec2(0.0, 3.2)) + fringe * 0.24);
		yard = max(yard, max(settlement, doorway));
	}
	float bridge_distance = 1000.0;
	for (int i = 0; i < bridge_count; i++) {
		bridge_distance = min(bridge_distance, woodland_bridge_distance(p, bridge_regions[i]));
	}
	float bend_weight = smoothstep(3.3, 6.5, door_distance) * smoothstep(1.0, 4.5, bridge_distance);
	vec2 path_point = p + woodland_path_bend(p) * bend_weight;
	float path_distance = 1000.0;
	for (int i = 0; i < path_count; i++) {
		path_distance = woodland_path_join(path_distance, segment_distance(path_point, paths[i].xy, paths[i].zw));
	}
	float trail = woodland_path_coverage(path_distance, p, fringe);
	float earth = max(yard, trail);
	color = mix(color, grass_shadow.rgb * 0.76, meadow_blades(p) * (1.0 - earth) * 0.42);
	color = mix(color, soil.rgb, earth);
	color = mix(color, soil.rgb * 0.68, smoothstep(0.2, 1.5, -world_position.y));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
