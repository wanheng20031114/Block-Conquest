shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_shadow : source_color = vec4(0.325, 0.435, 0.178, 1.0);
uniform vec4 grass_meadow : source_color = vec4(0.36, 0.465, 0.20, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.397, 0.497, 0.223, 1.0);
uniform vec4 soil_color : source_color = vec4(0.50, 0.465, 0.315, 1.0);
uniform vec4 bank_soil_color : source_color = vec4(0.42, 0.43, 0.335, 1.0);
varying vec3 world_position;

#include "res://assets/block_war/environment/meadow_surface.gdshaderinc"
#include "res://assets/block_war/environment/woodland_paths.gdshaderinc"

const vec2 SITES[13] = vec2[13](
	vec2(-30.0, 0.0), vec2(30.0, 0.0),
	vec2(-29.0, -19.0), vec2(-29.0, 19.0), vec2(29.0, -19.0), vec2(29.0, 19.0),
	vec2(-21.0, 0.0), vec2(21.0, 0.0), vec2(-23.0, -13.0), vec2(23.0, 13.0),
	vec2(0.0, -19.0), vec2(0.0, 19.0), vec2(0.0, 0.0));

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0));
}

float paths(vec2 p) {
	float d = segment_distance(p, vec2(-30.0, 3.0), vec2(-21.0, 3.5));
	d = woodland_path_join(d, segment_distance(p, vec2(30.0, 3.0), vec2(21.0, 3.5)));
	d = woodland_path_join(d, segment_distance(p, vec2(-29.0, -16.0), vec2(-24.0, -10.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-24.0, -10.0), vec2(-15.0, -14.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(29.0, -16.0), vec2(15.0, -14.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-29.0, 22.0), vec2(-21.0, 19.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-21.0, 19.0), vec2(-15.0, 14.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(29.0, 22.0), vec2(24.0, 17.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(24.0, 17.0), vec2(15.0, 14.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-9.0, -14.0), vec2(0.0, -15.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(0.0, -15.0), vec2(9.0, -14.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-9.0, 14.0), vec2(-5.0, 20.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(9.0, 14.0), vec2(5.0, 20.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(-5.0, 20.0), vec2(0.0, 22.0)));
	d = woodland_path_join(d, segment_distance(p, vec2(5.0, 20.0), vec2(0.0, 22.0)));
	return d;
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_position.xz;
	float fringe = meadow_edge_noise(p);
	vec3 color = painted_meadow(p, grass_meadow.rgb, grass_shadow.rgb, grass_sunlit.rgb);
	float woodland = max(smoothstep(37.0, 49.0, abs(p.x)), smoothstep(28.0, 40.0, abs(p.y)));
	color = mix(color, grass_shadow.rgb, woodland * 0.4);
	float yard = 0.0;
	float door_distance = 1000.0;
	for (int i = 0; i < 13; i++) {
		door_distance = min(door_distance, length(p - SITES[i]));
		vec2 q = (p - SITES[i]) / vec2(2.65, 2.38);
		float footprint = length(q);
		float settlement = 1.0 - smoothstep(0.78, 1.21, footprint + fringe * 0.08);
		float doorway = 1.0 - smoothstep(0.48, 1.35, segment_distance(p, SITES[i] + vec2(0.0, 0.8), SITES[i] + vec2(0.0, 3.2)) + fringe * 0.24);
		yard = max(yard, max(settlement, doorway));
	}
	float bridge_distance = min(
		min(woodland_bridge_distance(p, vec4(-15.0, -17.2, 6.0, 6.4)),
			woodland_bridge_distance(p, vec4(9.0, -17.2, 6.0, 6.4))),
		min(woodland_bridge_distance(p, vec4(-15.0, 10.8, 6.0, 6.4)),
			woodland_bridge_distance(p, vec4(9.0, 10.8, 6.0, 6.4))));
	float bend_weight = smoothstep(3.3, 6.5, door_distance) * smoothstep(1.0, 4.5, bridge_distance);
	vec2 path_point = p + woodland_path_bend(p) * bend_weight;
	float worn = woodland_path_coverage(paths(path_point), p, fringe);
	float earth = max(worn, yard);
	color = mix(color, grass_shadow.rgb * 0.76, meadow_blades(p) * (1.0 - earth) * 0.42);
	color = mix(color, soil_color.rgb, earth);
	// All authored colours use the same sRGB-to-linear uniform conversion.
	color = mix(color, bank_soil_color.rgb, smoothstep(0.28, 1.2, -world_position.y));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
