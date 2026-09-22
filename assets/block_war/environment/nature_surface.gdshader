shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float flow_time = 0.0;
uniform float wind_amount = 0.09;
uniform float wind_start = 1.1;
uniform float wind_full = 5.8;
uniform float surface_roughness = 0.96;
instance uniform vec3 nature_tint : source_color = vec3(1.0);
varying vec4 painted_color;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float flex = smoothstep(wind_start, wind_full, VERTEX.y);
	float breeze = sin(flow_time * 0.73 + world.x * 0.23 + world.z * 0.16);
	VERTEX.x += breeze * wind_amount * flex;
	VERTEX.z += sin(flow_time * 0.91 + world.z * 0.20) * wind_amount * 0.52 * flex;
	painted_color = COLOR;
}

void fragment() {
	// Broad clean colour planes keep the arena readable from the fixed camera.
	ALBEDO = painted_color.rgb * nature_tint;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.10;
}
