shader_type spatial;
render_mode diffuse_burley;

// Entire connected lobes move together. The trunk/root remains planted.
void vertex() {
	vec3 drift = vec3(sin(TIME * 0.9 + NODE_POSITION_WORLD.x * 0.39) * 0.018, 0.0,
		cos(TIME * 0.73 + NODE_POSITION_WORLD.z * 0.47) * 0.010);
	// Cancel each block's scale so adjacent crown prisms keep identical motion.
	VERTEX += inverse(mat3(MODEL_MATRIX)) * drift;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
