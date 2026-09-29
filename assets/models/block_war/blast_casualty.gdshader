shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;
varying vec4 body;

void vertex() {
	body = INSTANCE_CUSTOM;
	float part = UV2.x;
	// The authored militia's legs and free arm swing independently during flight.
	// The final limp pose settles before the quick fade, retaining its team coat.
	if (part > 0.5 && part < 3.5) {
		vec3 pivot = vec3(-0.155, 0.75, 0.0);
		float side = 1.0;
		float amplitude = 0.95;
		if (part > 1.5 && part < 2.5) { pivot.x = 0.155; side = -1.0; }
		if (part > 2.5) { pivot = vec3(-0.34, 1.28, 0.0); amplitude = 1.5; }
		float flight = min(body.a / 0.7, 1.0);
		float swing = sin(flight * 13.0 + part * 1.4) * amplitude;
		float angle = mix(swing, side * 0.48, smoothstep(0.56, 0.76, body.a));
		float c = cos(angle);
		float s = sin(angle);
		mat3 rotation = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
		VERTEX = pivot + rotation * (VERTEX - pivot);
		NORMAL = rotation * NORMAL;
	}
}

void fragment() {
	vec3 uniform_color = body.rgb * 0.72 + vec3(0.07, 0.06, 0.05);
	ALBEDO = mix(COLOR.rgb, uniform_color, step(0.75, COLOR.a));
	float flash = 1.0 - smoothstep(0.0, 0.1, body.a);
	EMISSION = vec3(0.7, 0.39, 0.13) * flash * 0.35;
	ROUGHNESS = 0.92;
	ALPHA = 1.0 - smoothstep(0.83, 1.0, body.a);
}
