shader_type spatial;
render_mode cull_disabled;

uniform float flow_time = 0.0;
uniform vec4 shallow_color : source_color = vec4(0.18, 0.43, 0.38, 1.0);
uniform vec4 deep_color : source_color = vec4(0.08, 0.28, 0.30, 1.0);
uniform vec4 foam_color : source_color = vec4(0.60, 0.79, 0.68, 1.0);
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_position.z * 1.5 - flow_time * 1.6) * 0.024;
}

void fragment() {
	vec2 p = world_position.xz;
	float center = p.x < 0.0 ? -12.0 : 12.0;
	float across = abs(p.x - center) / 3.1;
	float current = noise(vec2(p.x * 2.1, p.y * 0.48 - flow_time * 0.32));
	float ribbons = pow(0.5 + 0.5 * sin(p.x * 9.0 + sin(p.y * 0.62 - flow_time * 0.45) + current * 2.4), 13.0);
	float ripples = smoothstep(0.81, 0.95, noise(vec2(p.x * 3.0, p.y * 1.9 - flow_time * 0.7)));
	float shore = smoothstep(0.48, 0.94, across);
	float foam = shore * smoothstep(0.58, 0.85, current) * (0.58 + 0.42 * sin(p.y * 2.0 - flow_time));
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, shore * 0.73 + current * 0.23);
	ALBEDO = mix(ALBEDO, foam_color.rgb, clamp(foam * 0.53 + ribbons * 0.015 + ripples * 0.08, 0.0, 0.55));
	ROUGHNESS = 0.36;
	METALLIC = 0.13;
	NORMAL_MAP = vec3(0.5 + sin(p.y * 2.2 - flow_time) * 0.055, 0.5 + sin(p.x * 2.4 + flow_time * 0.6) * 0.075, 1.0);
	NORMAL_MAP_DEPTH = 0.35;
}
