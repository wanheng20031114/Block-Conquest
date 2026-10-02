shader_type spatial;
render_mode cull_disabled, diffuse_burley;

void vertex() {
	float free_edge = UV.x;
	VERTEX.z += (sin(TIME * 4.1 - UV.x * 5.0 + NODE_POSITION_WORLD.x) * 0.09 + sin(TIME * 2.9 + UV.y * 3.0) * 0.018) * free_edge;
}

void fragment() {
	vec3 cloth = vec3(0.19, 0.43, 0.47);
	float border = step(0.89, UV.y) + (1.0 - step(0.08, UV.y));
	float sigil = 1.0 - step(0.15, abs(UV.x - 0.49) + abs(UV.y - 0.5));
	ALBEDO = mix(cloth, vec3(0.89, 0.72, 0.36), clamp(border + sigil, 0.0, 1.0));
	ROUGHNESS = 1.0;
}
