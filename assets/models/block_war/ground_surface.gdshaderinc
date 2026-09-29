#include "res://assets/models/block_war/terrain_height.gdshaderinc"

varying vec3 terrain_world;
varying float terrain_clearance;

vec3 ground_effect_world(vec3 vertex, mat4 model, float clearance) {
	vec3 world = (model * vec4(vertex, 1.0)).xyz;
	if (terrain_enabled) {
		world.y = terrain_height(world.xz) + clearance;
	}
	return world;
}

bool ground_effect_gap(vec3 world, float clearance) {
	// Effect planes use their own grid. Clip any chord that cuts across a steep
	// terrain bend, rather than leaving a floating patch above the baked surface.
	return terrain_enabled && abs(world.y - clearance - terrain_height(world.xz)) > 0.08;
}
