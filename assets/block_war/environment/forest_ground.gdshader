shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_shadow : source_color = vec4(0.16, 0.265, 0.205, 1.0);
uniform vec4 grass_meadow : source_color = vec4(0.29, 0.405, 0.235, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.395, 0.485, 0.295, 1.0);
uniform vec4 soil_color : source_color = vec4(0.49, 0.445, 0.355, 1.0);
uniform vec4 bank_soil_color : source_color = vec4(0.36, 0.37, 0.29, 1.0);
varying vec3 world_position;

const vec2 SITES[13] = vec2[13](
	vec2(-30.0, 0.0), vec2(30.0, 0.0),
	vec2(-29.0, -19.0), vec2(-29.0, 19.0), vec2(29.0, -19.0), vec2(29.0, 19.0),
	vec2(-21.0, 0.0), vec2(21.0, 0.0), vec2(-23.0, -13.0), vec2(23.0, 13.0),
	vec2(0.0, -19.0), vec2(0.0, 19.0), vec2(0.0, 0.0));

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0));
}

float paths(vec2 p) {
	float d = segment_distance(p, vec2(-30.0, 3.0), vec2(-21.0, 3.5));
	d = min(d, segment_distance(p, vec2(30.0, 3.0), vec2(21.0, 3.5)));
	d = min(d, segment_distance(p, vec2(-29.0, -16.0), vec2(-24.0, -10.0)));
	d = min(d, segment_distance(p, vec2(-24.0, -10.0), vec2(-15.0, -14.0)));
	d = min(d, segment_distance(p, vec2(29.0, -16.0), vec2(15.0, -14.0)));
	d = min(d, segment_distance(p, vec2(-29.0, 22.0), vec2(-21.0, 19.0)));
	d = min(d, segment_distance(p, vec2(-21.0, 19.0), vec2(-15.0, 14.0)));
	d = min(d, segment_distance(p, vec2(29.0, 22.0), vec2(24.0, 17.0)));
	d = min(d, segment_distance(p, vec2(24.0, 17.0), vec2(15.0, 14.0)));
	d = min(d, segment_distance(p, vec2(-9.0, -14.0), vec2(0.0, -15.0)));
	d = min(d, segment_distance(p, vec2(0.0, -15.0), vec2(9.0, -14.0)));
	d = min(d, segment_distance(p, vec2(-9.0, 14.0), vec2(-5.0, 20.0)));
	d = min(d, segment_distance(p, vec2(9.0, 14.0), vec2(5.0, 20.0)));
	d = min(d, segment_distance(p, vec2(-5.0, 20.0), vec2(0.0, 22.0)));
	d = min(d, segment_distance(p, vec2(5.0, 20.0), vec2(0.0, 22.0)));
	return d;
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_position.xz;
	float broad = texture(meadow_noise, p / 99.0 + vec2(0.23, 0.17)).r;
	float patches = texture(meadow_noise, p / 22.0 + vec2(0.41, 0.76)).r;
	float detail = texture(meadow_noise, p / 5.8 + vec2(0.1, 0.4)).r;
	vec3 color = mix(grass_meadow.rgb, grass_sunlit.rgb, smoothstep(0.22, 0.79, broad));
	color = mix(color, grass_shadow.rgb, smoothstep(0.58, 0.86, patches) * 0.24);
	float woodland = max(smoothstep(31.0, 44.0, abs(p.x) + (patches - 0.5) * 7.0), smoothstep(24.0, 36.0, abs(p.y) + (broad - 0.5) * 7.0));
	color = mix(color, grass_shadow.rgb, woodland * 0.82);
	float worn = 1.0 - smoothstep(0.72, 1.82, paths(p) + (patches - 0.5) * 1.8 + (detail - 0.5) * 0.28);
	float yard = 0.0;
	for (int i = 0; i < 13; i++) {
		vec2 q = (p - SITES[i]) / vec2(2.65, 2.38);
		float footprint = length(q);
		float settlement = 1.0 - smoothstep(0.74, 1.39, footprint + (detail - 0.5) * 0.3);
		float doorway = 1.0 - smoothstep(0.6, 1.35, segment_distance(p, SITES[i] + vec2(0.0, 0.8), SITES[i] + vec2(0.0, 3.2)));
		yard = max(yard, max(settlement * 0.84, doorway * 0.81));
	}
	float earth = max(worn * 0.60, yard);
	color = mix(color, soil_color.rgb * (0.97 + patches * 0.07), earth);
	float bank_distance = min(abs(abs(p.x) - 9.0), abs(abs(p.x) - 15.0));
	float bank = (1.0 - smoothstep(0.25, 1.35, bank_distance)) * (1.0 - worn);
	color = mix(color, grass_shadow.rgb, bank * 0.16);
	color *= 0.96 + detail * 0.08;
	// All authored colours use the same sRGB-to-linear uniform conversion.
	color = mix(color, bank_soil_color.rgb, smoothstep(0.28, 1.2, -world_position.y));
	ALBEDO = color;
	ROUGHNESS = 0.95;
}
