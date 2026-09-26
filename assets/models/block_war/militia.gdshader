shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 faction_color;
varying float rushing;

void vertex() {
	faction_color = INSTANCE_CUSTOM.rgb * 0.72 + vec3(0.07, 0.06, 0.05);
	rushing = INSTANCE_CUSTOM.a < 0.0 ? 1.0 : 0.0;
	float phase = rushing > 0.5 ? -INSTANCE_CUSTOM.a - 1.0 : INSTANCE_CUSTOM.a;
	// UV2.x identifies the left leg, right leg and free arm of the saved mesh.
	// The spear is in the static group: its shaft always remains parallel to +Y.
	float part = UV2.x;
	if (part > 0.5 && part < 3.5) {
		vec3 pivot = vec3(-0.155, 0.75, 0.0);
		float direction = 1.0;
		float amplitude = 0.49;
		if (part > 1.5 && part < 2.5) {
			pivot.x = 0.155;
			direction = -1.0;
		}
		if (part > 2.5) {
			pivot = vec3(-0.34, 1.28, 0.0);
			direction = -1.0;
			amplitude = 0.13;
		}
		float angle = sin(phase) * amplitude * direction;
		float c = cos(angle);
		float s = sin(angle);
		mat3 turn = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
		VERTEX = pivot + turn * (VERTEX - pivot);
		NORMAL = turn * NORMAL;
	}
	VERTEX.y += abs(sin(phase)) * 0.055;
}

void fragment() {
	float heraldry = step(0.75, COLOR.a);
	float metal = step(0.25, COLOR.a) * (1.0 - heraldry);
	ALBEDO = mix(COLOR.rgb, faction_color, heraldry);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	vec3 rush_red = vec3(0.85, 0.035, 0.025);
	// Keep faction cloth recognizable; the fast red edge belongs to the buff.
	ALBEDO = mix(ALBEDO, rush_red, rushing * (0.10 + rim * 0.22) * (1.0 - heraldry * 0.75));
	EMISSION = rush_red * rushing * (0.06 + rim * 0.34);
	METALLIC = metal * 0.24;
	ROUGHNESS = mix(0.88, 0.62, metal);
}
