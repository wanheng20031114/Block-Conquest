shader_type spatial;
render_mode cull_disabled;

instance uniform vec4 team_color : source_color = vec4(0.75, 0.51, 0.22, 1.0);
instance uniform int building_level : hint_range(1, 4) = 1;
uniform float visual_time = 0.0;

void vertex() {
	float free_edge = clamp(VERTEX.x / 2.25, 0.0, 1.0);
	VERTEX.z += (sin(visual_time * 1.75 - VERTEX.x * 4.5) * 0.075 + sin(visual_time * 2.7 + VERTEX.y * 6.0) * 0.025) * free_edge;
	VERTEX.y += sin(visual_time * 1.8 + VERTEX.x * 2.9) * 0.023 * free_edge;
}

void fragment() {
	float border = 1.0 - step(0.045, min(UV.y, 1.0 - UV.y));
	border = max(border, 1.0 - step(0.035, 1.0 - UV.x));
	// Equally sized, separated rank diamonds remain readable from the game camera.
	float crest_distance = 10.0;
	float crest_spacing = building_level == 4 ? 0.225 : 0.285;
	float crest_width = building_level == 4 ? 0.088 : 0.112;
	for (int i = 0; i < 4; i++) {
		if (i < building_level) {
			float center_x = 0.5 + (float(i) - float(building_level - 1) * 0.5) * crest_spacing;
			vec2 crest_uv = abs((UV - vec2(center_x, 0.5)) / vec2(crest_width, 0.37));
			crest_distance = min(crest_distance, crest_uv.x + crest_uv.y);
		}
	}
	float aa = max(fwidth(crest_distance) * 0.65, 0.001);
	float outline = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, crest_distance);
	float crest = 1.0 - smoothstep(0.72 - aa, 0.72 + aa, crest_distance);
	vec3 ivory = vec3(0.96, 0.94, 0.82);
	ALBEDO = mix(team_color.rgb, vec3(0.66, 0.49, 0.25), border);
	ALBEDO = mix(ALBEDO, vec3(0.035, 0.055, 0.05), outline);
	ALBEDO = mix(ALBEDO, ivory, crest);
	EMISSION = ivory * crest * 0.12;
	ROUGHNESS = 0.92;
}
