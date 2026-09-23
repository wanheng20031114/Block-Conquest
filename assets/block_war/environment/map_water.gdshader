shader_type spatial;
render_mode cull_disabled;

uniform float flow_time = 0.0;
uniform vec4 region = vec4(-10.0, -10.0, 20.0, 20.0);
uniform vec4 shallow_color : source_color = vec4(0.265, 0.45, 0.435, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.315, 0.345, 1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.z * 1.3 - flow_time * 1.25) * 0.012;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 edge = min(p - region.xy, region.xy + region.zw - p);
	float shore = 1.0 - smoothstep(0.1, 2.2, min(edge.x, edge.y));
	float ripples = sin(p.x * 1.5 + sin(p.y * 0.9 - flow_time * 0.6)) * 0.5 + 0.5;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shore * 0.7 + ripples * 0.12);
	ROUGHNESS = 0.64;
	SPECULAR = 0.18;
	NORMAL_MAP = vec3(0.5 + sin(p.y * 1.6 - flow_time) * 0.04, 0.5 + sin(p.x * 2.0 + flow_time * 0.5) * 0.04, 1.0);
	NORMAL_MAP_DEPTH = 0.24;
}
