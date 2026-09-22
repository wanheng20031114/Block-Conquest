shader_type spatial;
render_mode cull_disabled;

uniform float flow_time = 0.0;
uniform vec4 shallow_color : source_color = vec4(0.265, 0.45, 0.435, 1.0);
uniform vec4 deep_color : source_color = vec4(0.16, 0.315, 0.345, 1.0);
uniform vec4 foam_color : source_color = vec4(0.61, 0.715, 0.655, 1.0);
varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.z * 1.3 - flow_time * 1.25) * 0.012;
}

void fragment() {
	vec2 p = world_position.xz;
	float center = p.x < 0.0 ? -12.0 : 12.0;
	float side = -sign(p.x - center);
	float approach = smoothstep(3.7, 5.4, abs(abs(p.y) - 14.0));
	float reach = 0.08 + (0.67 + 0.38 * sin(p.y * 0.25 + center * 0.42) + side * 0.26 * cos(p.y * 0.64)) * approach;
	float shore_distance = 3.0 - reach - 0.59 - abs(p.x - center);
	float current = noise(vec2(p.x * 1.5, p.y * 0.45 - flow_time * 0.19));
	float shore = 1.0 - smoothstep(0.0, 0.90, shore_distance);
	float streaks = pow(0.5 + 0.5 * sin(p.x * 9.2 + sin(p.y * 0.43 - flow_time * 0.62)), 24.0);
	float ripples = smoothstep(0.84, 0.97, noise(vec2(p.x * 3.0, p.y * 1.5 - flow_time * 0.48)));
	float foam = (1.0 - smoothstep(0.01, 0.16, abs(shore_distance - 0.08))) * (0.53 + 0.47 * current);
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shore * 0.64 + current * 0.25);
	ALBEDO = mix(ALBEDO, foam_color.rgb, foam * 0.18 + streaks * current * 0.007 + ripples * 0.035);
	ROUGHNESS = 0.62;
	SPECULAR = 0.18;
	NORMAL_MAP = vec3(0.5 + sin(p.y * 1.6 - flow_time) * 0.045, 0.5 + sin(p.x * 2.0 + flow_time * 0.5) * 0.055, 1.0);
	NORMAL_MAP_DEPTH = 0.26;
}
