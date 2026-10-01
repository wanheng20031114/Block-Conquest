shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 faction_color;
void vertex() {
	faction_color = INSTANCE_CUSTOM.rgb * 0.72 + vec3(0.07, 0.06, 0.05);
	float fall = min(INSTANCE_CUSTOM.a, 1.0);
	float part = UV2.x;
	if (part > 0.5 && part < 3.5) {
		vec3 pivot = vec3(part < 1.5 ? -0.155 : 0.155, 0.75, 0.0);
		float angle = (0.14 + sin(fall * 3.141593) * 0.17);
		if (part > 2.5) { pivot = vec3(-0.34, 1.28, 0.0); angle *= -0.8; }
		float c = cos(angle);
		float s = sin(angle);
		mat3 turn = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
		VERTEX = pivot + turn * (VERTEX - pivot);
		NORMAL = turn * NORMAL;
	}
}
void fragment() {
	float heraldry = step(0.75, COLOR.a);
	float metal = step(0.25, COLOR.a) * (1.0 - heraldry);
	ALBEDO = mix(COLOR.rgb, faction_color, heraldry);
	METALLIC = metal * 0.24;
	ROUGHNESS = mix(0.88, 0.62, metal);
}
