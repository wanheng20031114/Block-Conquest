// Low-frequency displacement bends connected road spines together, so their
// junctions remain connected. Callers fade this out at doors and bridge decks.
vec2 woodland_path_bend(vec2 p) {
	vec2 uv = p / 460.0;
	vec2 bend = vec2(texture(meadow_noise, uv + vec2(0.17, 0.63)).r,
		texture(meadow_noise, uv + vec2(0.71, 0.29)).r) - vec2(0.5);
	bend *= 3.6;
	return bend * min(1.0, 1.4 / max(length(bend), 0.001));
}

float woodland_bridge_distance(vec2 p, vec4 region) {
	return length(max(max(region.xy - p, p - region.xy - region.zw), vec2(0.0)));
}

// A rounded union softens the inside corner where two spines meet.
float woodland_path_join(float a, float b) {
	float h = max(0.75 - abs(a - b), 0.0) / 0.75;
	return min(a, b) - h * h * 0.1875;
}

float woodland_path_coverage(float distance_to_path, vec2 p, float fringe) {
	// Uneven wear changes width slowly. Fine noise breaks only the soft shoulder;
	// a continuous earth-coloured centre keeps the path readable through grass.
	float wear = texture(meadow_noise, p / 74.0 + vec2(0.56, 0.32)).r - 0.5;
	return 1.0 - smoothstep(0.48, 1.42, distance_to_path + wear * 0.55 + fringe * 0.24);
}
