shader_type canvas_item;
render_mode unshaded;

// One scene-authored BackBufferCopy is shared by all visible backpack panels.
uniform sampler2D backdrop : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 panel_size = vec2(460.0, 710.0);
uniform float corner_radius = 14.0;

void fragment() {
	vec2 half_size = panel_size * 0.5;
	vec2 edge = abs((UV - 0.5) * panel_size) - half_size + corner_radius;
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - corner_radius;
	float mask = 1.0 - smoothstep(-0.8, 0.8, distance_to_edge);
	vec3 scene = textureLod(backdrop, SCREEN_UV, 2.3).rgb;
	vec3 slate = mix(vec3(0.14, 0.23, 0.32), vec3(0.075, 0.13, 0.21), UV.y);
	vec3 surface = mix(scene, slate, 0.84);
	float lip = (1.0 - smoothstep(0.0, 1.4, abs(distance_to_edge + 1.0))) * (0.12 + 0.1 * (1.0 - UV.y));
	COLOR = vec4(surface + vec3(0.48, 0.66, 0.80) * lip, mask * COLOR.a);
}
