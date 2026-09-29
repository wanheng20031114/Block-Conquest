// Mirrors WarMapDefinition.surface_height, including inclusive shared edges.
uniform int terrain_zone_count = 0;
uniform vec4 terrain_regions[16];
uniform vec3 terrain_profiles[16];

float terrain_height(vec2 point) {
	float height = 0.0;
	bool found = false;
	for (int i = 0; i < terrain_zone_count; i++) {
		vec4 region = terrain_regions[i];
		vec2 offset = point - region.xy;
		if (offset.x < 0.0 || offset.y < 0.0 || offset.x > region.z || offset.y > region.w) {
			continue;
		}
		vec3 profile = terrain_profiles[i];
		float ratio = profile.z < 0.5 ? offset.x / region.z : offset.y / region.w;
		float candidate = mix(profile.x, profile.y, clamp(ratio, 0.0, 1.0));
		height = found ? max(height, candidate) : candidate;
		found = true;
	}
	return height;
}
