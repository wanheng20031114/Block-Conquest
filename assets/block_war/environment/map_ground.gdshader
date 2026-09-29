shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 half_size = vec2(40.0, 28.0);
uniform vec4 meadow : source_color = vec4(0.36, 0.465, 0.20, 1.0);
uniform vec4 grass_shadow : source_color = vec4(0.325, 0.435, 0.178, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.397, 0.497, 0.223, 1.0);
uniform vec4 soil : source_color = vec4(0.50, 0.465, 0.315, 1.0);
uniform bool natural_terrain = false;
uniform vec4 cliff_shadow : source_color = vec4(0.28, 0.30, 0.245, 1.0);
uniform vec4 cliff_sunlit : source_color = vec4(0.47, 0.445, 0.35, 1.0);
uniform int site_count = 0;
uniform vec2 sites[64];
uniform int path_count = 0;
uniform vec4 paths[64];
uniform int bridge_count = 0;
uniform vec4 bridge_regions[16];
varying vec3 world_position;
varying vec3 terrain_normal;

#include "res://assets/block_war/environment/meadow_surface.gdshaderinc"
#include "res://assets/block_war/environment/woodland_paths.gdshaderinc"

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / max(dot(d, d), 0.01), 0.0, 1.0));
}

vec2 cliff_seed(vec2 cell) {
	vec3 seed = fract(vec3(cell.x, cell.y, cell.x) * vec3(0.1031, 0.1030, 0.0973));
	seed += dot(seed, seed.yzx + 33.33);
	return fract((seed.xx + seed.yz) * seed.zy);
}

vec3 cliff_face(vec2 point) {
	// Metre-scale broken rock faces. A gentle domain warp removes the regular
	// cell alignment without introducing fine stripes or a noisy stone surface.
	vec2 warp = vec2(texture(meadow_noise, point / 75.0).r,
		texture(meadow_noise, point / 75.0 + vec2(0.31, 0.67)).r) - 0.5;
	vec2 p = mat2(vec2(0.94, 0.34), vec2(-0.34, 0.94)) * point / 2.8 + warp * 0.7;
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 10.0;
	float second = 10.0;
	float tone = 0.5;
	vec2 face_offset = vec2(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(z));
			vec2 seed = cliff_seed(cell + neighbor);
			vec2 offset = neighbor + 0.12 + seed * 0.76 - local;
			float distance = dot(offset, offset);
			if (distance < nearest) {
				second = nearest;
				nearest = distance;
				tone = seed.x;
				face_offset = offset;
			} else {
				second = min(second, distance);
			}
		}
	}
	float edge_distance = sqrt(second) - sqrt(nearest);
	float crack = 1.0 - smoothstep(0.018, 0.055, edge_distance);
	// Only broken portions of a boundary show a shallow seam; the full cell
	// outline would make the cliff look like fitted paving stones.
	crack *= smoothstep(0.43, 0.67, warp.x + 0.5);
	// A broad, faint plane inside each face keeps the rock from reading as
	// flat fitted tiles. Its colour stays inside the established earth palette.
	float plane = dot(face_offset, vec2(0.035, -0.065));
	vec3 rock = mix(cliff_shadow.rgb, cliff_sunlit.rgb, 0.36 + tone * 0.32 + plane);
	return rock * (1.0 - crack * 0.12);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

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
		// The authored road already reaches the front steps. An extra forward
		// capsule here protrudes through its far shoulder as a blind spur.
		yard = max(yard, settlement);
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
	if (natural_terrain) {
		float exposed = 1.0 - smoothstep(0.67, 0.88, normalize(terrain_normal).y);
		if (exposed > 0.001) {
			// Two vertical world projections retain the same face size on north,
			// south and side walls. No height multiplier stretches the texture.
			vec2 weights = pow(abs(terrain_normal.xz), vec2(4.0));
			weights /= max(weights.x + weights.y, 0.0001);
			vec3 rock = cliff_face(world_position.zy) * weights.x
				+ cliff_face(world_position.xy + vec2(13.7, 8.3)) * weights.y;
			color = mix(color, rock, exposed);
		}
	}
	color = mix(color, soil.rgb * 0.68, smoothstep(0.2, 1.5, -world_position.y));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
