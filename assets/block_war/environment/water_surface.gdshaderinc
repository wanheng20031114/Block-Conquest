// Opaque water stays in Godot's native SSR/depth pass. The authored shore
// supplies shallows without a screen/depth-reading transparency pass.
uniform float flow_time = 0.0;
uniform sampler2D surface_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normals : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.30, 0.64, 0.57, 1.0);
uniform vec4 deep_color : source_color = vec4(0.085, 0.34, 0.40, 1.0);
uniform vec4 foam_color : source_color = vec4(0.79, 0.90, 0.80, 1.0);
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.38;
varying vec3 world_position;

void paint_water(vec2 p, float shore_distance, out vec3 color, out vec3 normal, out float roughness) {
	vec2 drift = vec2(flow_time * 0.012, -flow_time * 0.018);
	float broad = texture(surface_noise, p / 87.0 + drift * 0.10).r;
	float flow = texture(surface_noise, p / vec2(19.0, 33.0) + drift * 0.24).r;
	float shallows = exp(-max(shore_distance, 0.0) * 0.85);
	color = mix(deep_color.rgb, shallow_color.rgb, clamp(shallows * 0.72 + broad * 0.20, 0.0, 1.0));
	vec2 first = texture(wave_normals, p / vec2(17.0, 25.0) + drift).xy * 2.0 - 1.0;
	vec2 second = texture(wave_normals, p.yx / vec2(29.0, 19.0) - drift * 0.63).yx * 2.0 - 1.0;
	vec2 slope = first * 0.26 + second * 0.16;
	normal = normalize(vec3(slope.x, 1.0, slope.y));
	float fringe = 1.0 - smoothstep(0.07, 0.26, shore_distance + (flow - 0.5) * 0.18);
	float wash_distance = 0.43 + sin(flow_time * 0.75 + flow * 5.0) * 0.14;
	float wash = (1.0 - smoothstep(0.025, 0.10, abs(shore_distance - wash_distance)))
		* smoothstep(0.48, 0.69, flow) * 0.23;
	// Sparse long highlights avoid a regular grid of sine-wave stripes.
	float streak = texture(surface_noise, p / vec2(25.0, 5.5) + drift * 0.43).r;
	float glints = smoothstep(0.78, 0.86, streak) * smoothstep(0.51, 0.67, flow);
	float foam = clamp(fringe * (0.54 + flow * 0.35) + wash, 0.0, 0.9);
	color = mix(color, foam_color.rgb, foam);
	color = mix(color, foam_color.rgb, glints * 0.15 * (1.0 - shallows));
	roughness = mix(0.19 + flow * 0.09, 0.66, foam);
}
