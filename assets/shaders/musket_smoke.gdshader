shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;

// A shared low-poly tube forms the smoke left along the actual bullet path.
// Instance uniforms avoid material copies and use simulation time, so pause freezes it.
instance uniform float smoke_age = 0.0;
instance uniform float trace_length = 1.0;

void vertex() {
	float distance_along = UV.y * trace_length;
	float swell = 0.75 + 0.25 * sin(distance_along * 11.0);
	VERTEX.xz *= swell * (1.0 + smoke_age * 0.8);
	VERTEX.x += sin(distance_along * 7.0) * smoke_age * 0.5;
	VERTEX.z += cos(distance_along * 5.0) * smoke_age * 0.4;
}

void fragment() {
	float distance_along = UV.y * trace_length;
	float wisps = 0.18 + 0.82 * smoothstep(-0.6, 0.85,
		sin(distance_along * 13.0 + smoke_age * 2.0) + 0.45 * sin(distance_along * 31.0 + UV.x * 6.283));
	float ends = smoothstep(0.0, 0.025, UV.y) * smoothstep(0.0, 0.025, 1.0 - UV.y);
	float soft_edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.7);
	ALBEDO = vec3(0.76, 0.78, 0.77);
	ALPHA = 0.68 * wisps * ends * soft_edge * (1.0 - smoke_age);
}
