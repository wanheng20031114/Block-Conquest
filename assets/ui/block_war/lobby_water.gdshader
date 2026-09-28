shader_type spatial;
render_mode cull_disabled;

uniform float visual_time = 0.0;
uniform vec2 ripple_at = vec2(0.0);
uniform float ripple_age = 10.0;
uniform vec2 ferry_at = vec2(0.0);
uniform vec2 ferry_direction = vec2(0.0, 1.0);
varying vec2 water_at;

void vertex() {
	water_at = VERTEX.xz;
	VERTEX.y += sin(VERTEX.x * 1.8 + VERTEX.z * 1.5 + visual_time * 1.0) * 0.012;
}

void fragment() {
	float t = visual_time;
	float current = sin(water_at.x * 2.8 + sin(water_at.y * 1.3 - t * 0.24) * 0.7 - t * 1.35);
	float fleck = smoothstep(0.89, 0.99, current) * smoothstep(0.28, 0.65, sin(water_at.y * 5.4 + water_at.x * 0.3));
	float distance_to_click = length(water_at - ripple_at);
	float wave = exp(-pow((distance_to_click - ripple_age * 2.9) / 0.11, 2.0));
	float ring = wave * (1.0 - smoothstep(0.15, 1.3, ripple_age));
	vec2 from_ferry = water_at - ferry_at;
	float behind = -dot(from_ferry, ferry_direction);
	float across = abs(dot(from_ferry, vec2(-ferry_direction.y, ferry_direction.x)));
	float wake = exp(-pow((across - 0.22 - behind * 0.23) / 0.065, 2.0));
	wake *= smoothstep(0.1, 0.4, behind) * (1.0 - smoothstep(0.5, 1.6, behind));
	ALBEDO = mix(vec3(0.36, 0.64, 0.64), vec3(0.68, 0.83, 0.77), min(0.9, fleck * 0.48 + ring * 0.58 + wake * 0.5));
	ROUGHNESS = 0.33;
	SPECULAR = 0.22;
}
