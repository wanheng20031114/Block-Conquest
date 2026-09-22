shader_type spatial;
render_mode cull_disabled;

instance uniform vec4 team_color : source_color = vec4(0.75, 0.51, 0.22, 1.0);
uniform float visual_time = 0.0;

void vertex() {
	float free_edge = clamp(VERTEX.x / 1.65, 0.0, 1.0);
	VERTEX.z += (sin(visual_time * 1.75 - VERTEX.x * 4.5) * 0.075 + sin(visual_time * 2.7 + VERTEX.y * 6.0) * 0.025) * free_edge;
	VERTEX.y += sin(visual_time * 1.8 + VERTEX.x * 2.9) * 0.023 * free_edge;
}

void fragment() {
	float border = 1.0 - step(0.045, min(UV.y, 1.0 - UV.y));
	border = max(border, 1.0 - step(0.035, 1.0 - UV.x));
	float crest = 1.0 - step(0.16, abs(UV.x - 0.38) + abs(UV.y - 0.5) * 0.58);
	ALBEDO = mix(team_color.rgb, vec3(0.66, 0.49, 0.25), max(border, crest));
	ROUGHNESS = 0.92;
}
