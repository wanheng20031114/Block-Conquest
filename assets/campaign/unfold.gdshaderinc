// Native AnimationPlayer drives this per-scene material clock. In the editor,
// the default displays the finished map. Every layer of a column stays joined.
uniform float build_time = 1.6;

vec3 unfold_column(vec3 world_position, vec3 column_center) {
	// Fine pavers and their supporting quarter/half-unit terrain blocks must
	// share a clock. Per-instance centers would lift a paver through the earth.
	vec2 column = (floor(column_center.xz * 2.0) + 0.5) * 0.5;
	float delay = 0.05 + 0.45 * clamp((column.x + 28.0) / 56.0, 0.0, 1.0)
		+ 0.07 * clamp((column.y + 12.0) / 24.0, 0.0, 1.0);
	float progress = smoothstep(0.0, 0.9, build_time - delay);
	float height = mix(0.007, 1.0, progress);
	world_position.y = -2.5 + (world_position.y + 2.5) * height;
	return world_position;
}
