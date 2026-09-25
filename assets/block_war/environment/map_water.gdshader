shader_type spatial;
render_mode cull_disabled;

uniform float flow_time = 0.0;
uniform sampler2D surface_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.265, 0.45, 0.435, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.315, 0.345, 1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.z * 1.3 - flow_time * 1.25) * 0.012;
}

void fragment() {
	vec2 p = world_position.xz;
	// Baked against the union shoreline: no false banks at island junctions.
	float shore = COLOR.r;
	float current = texture(surface_noise, p / vec2(21.0, 37.0) - vec2(0.0, flow_time * 0.004)).r;
	float ripples = smoothstep(0.70, 0.88, texture(surface_noise, p / vec2(5.0, 11.0) - vec2(0.0, flow_time * 0.009)).r);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shore * 0.64 + current * 0.16);
	ALBEDO = mix(ALBEDO, shallow_color.rgb, ripples * 0.018);
	ROUGHNESS = 0.64;
	SPECULAR = 0.18;
	NORMAL_MAP = vec3(0.5 + sin(p.y * 1.6 - flow_time) * 0.018, 0.5 + sin(p.x * 2.0 + flow_time * 0.5) * 0.022, 1.0);
	NORMAL_MAP_DEPTH = 0.24;
}
