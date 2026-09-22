shader_type spatial;
render_mode cull_disabled;
uniform float flow_time = 0.0;
varying vec4 painted_color;
void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float bend = smoothstep(1.25, 6.0, VERTEX.y);
	VERTEX.x += sin(flow_time * 0.72 + world.x * 0.16 + world.z * 0.14) * 0.075 * bend;
	VERTEX.z += sin(flow_time * 0.93 + world.z * 0.19) * 0.042 * bend;
	painted_color = COLOR;
}
void fragment() {
	ALBEDO = painted_color.rgb * vec3(0.82, 1.03, 0.91);
	ROUGHNESS = 0.91;
}
