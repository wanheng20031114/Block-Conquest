shader_type spatial;
render_mode specular_disabled;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_shadow : source_color = vec4(0.14, 0.28, 0.115, 1.0);
uniform vec4 grass_meadow : source_color = vec4(0.24, 0.40, 0.14, 1.0);
uniform vec4 grass_sunlit : source_color = vec4(0.32, 0.47, 0.16, 1.0);
uniform vec4 dry_grass : source_color = vec4(0.48, 0.47, 0.245, 1.0);
uniform vec4 soil_color : source_color = vec4(0.48, 0.38, 0.245, 1.0);
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
	float d = segment_distance(p, vec2(-30.0, 4.0), vec2(-21.0, 4.6));
	d = min(d, segment_distance(p, vec2(30.0, 4.0), vec2(21.0, 4.6)));
	d = min(d, segment_distance(p, vec2(-29.0, -16.0), vec2(-24.0, -10.0)));
	d = min(d, segment_distance(p, vec2(-24.0, -10.0), vec2(-15.0, -14.0)));
	d = min(d, segment_distance(p, vec2(29.0, -16.0), vec2(15.0, -14.0)));
	d = min(d, segment_distance(p, vec2(-29.0, 23.0), vec2(-21.0, 19.0)));
	d = min(d, segment_distance(p, vec2(-21.0, 19.0), vec2(-15.0, 14.0)));
	d = min(d, segment_distance(p, vec2(29.0, 23.0), vec2(24.0, 17.0)));
	d = min(d, segment_distance(p, vec2(24.0, 17.0), vec2(15.0, 14.0)));
	d = min(d, segment_distance(p, vec2(-9.0, -14.0), vec2(0.0, -15.0)));
	d = min(d, segment_distance(p, vec2(0.0, -15.0), vec2(9.0, -14.0)));
	d = min(d, segment_distance(p, vec2(-9.0, 14.0), vec2(-5.0, 20.0)));
	d = min(d, segment_distance(p, vec2(9.0, 14.0), vec2(5.0, 20.0)));
	d = min(d, segment_distance(p, vec2(-5.0, 20.0), vec2(0.0, 23.0)));
	d = min(d, segment_distance(p, vec2(5.0, 20.0), vec2(0.0, 23.0)));
	return d;
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 p = world_position.xz;
	// Quiet lawn planes: broad color drift, a soft mowing grid, no grain texture.
	float broad = texture(meadow_noise, p / 176.0 + vec2(0.31, 0.12)).r;
	float patches = texture(meadow_noise, p / 42.0 + vec2(0.71, 0.36)).r;
	float fine = texture(meadow_noise, p / 8.0).r;
	float meadow = smoothstep(0.1, 0.9, broad);
	vec3 color = mix(grass_meadow.rgb, grass_sunlit.rgb, meadow);
	float mowing = sin(p.x * 3.14159265 / 3.8) * sin(p.y * 3.14159265 / 3.8);
	float checker = smoothstep(-0.055, 0.055, mowing);
	color *= mix(0.94, 1.035, checker);
	float forest_edge = max(smoothstep(28.0, 43.0, abs(p.x) + (broad - 0.5) * 9.0), smoothstep(22.0, 34.0, abs(p.y) + (patches - 0.5) * 6.0));
	color = mix(color, grass_shadow.rgb, forest_edge * 0.65);
	float bank_distance = min(abs(abs(p.x) - 9.0), abs(abs(p.x) - 15.0));
	float moist_bank = (1.0 - smoothstep(0.35, 2.8, bank_distance + (patches - 0.5) * 1.1));
	color = mix(color, grass_shadow.rgb, moist_bank * 0.16);
	float worn = 1.0 - smoothstep(0.30, 1.60, paths(p) + (patches - 0.5) * 1.6 + (fine - 0.5) * 0.35);
	float yard = 0.0;
	for (int i = 0; i < 13; i++) {
		vec2 q = abs((p - SITES[i]) / vec2(2.05, 1.72));
		float footprint = pow(pow(q.x, 4.0) + pow(q.y, 4.0), 0.25);
		float settlement = 1.0 - smoothstep(0.76, 1.48, footprint + (patches - 0.5) * 0.52);
		float doorway = 1.0 - smoothstep(0.4, 1.12, segment_distance(p, SITES[i] + vec2(0.0, 0.82), SITES[i] + vec2(0.25, 3.5)) + (fine - 0.5) * 0.38);
		yard = max(yard, max(settlement * 0.77, doorway * 0.9));
	}
	float exposed = max(worn * 0.23, yard);
	color = mix(color, dry_grass.rgb, smoothstep(0.12, 0.58, exposed) * 0.18);
	color = mix(color, soil_color.rgb, exposed * 0.75);
	ALBEDO = color * (0.986 + patches * 0.028);
	ROUGHNESS = 0.96;
}
