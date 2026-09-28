shader_type spatial;
render_mode cull_disabled;

uniform float visual_time = 0.0;
uniform vec2 ripple_at = vec2(0.0);
uniform float ripple_age = 10.0;
uniform vec2 ferry_at = vec2(0.0);
uniform vec2 ferry_direction = vec2(0.0, 1.0);
uniform sampler2D surface_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
// Authored island footprints: x/z center followed by x/z half-size.
// Their union keeps foam off the seams between neighboring terrain blocks.
uniform vec4 shore_rects[4];
varying vec2 water_at;

float bank_distance(vec2 p) {
	float distance_to_bank = 100.0;
	for (int i = 0; i < 4; i++) {
		vec2 q = abs(p - shore_rects[i].xy) - shore_rects[i].zw;
		float distance_to_rect = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
		distance_to_bank = min(distance_to_bank, distance_to_rect);
	}
	return max(distance_to_bank, 0.0);
}

void vertex() {
	water_at = VERTEX.xz;
	VERTEX.y += sin(VERTEX.x * 1.8 + VERTEX.z * 1.5 + visual_time) * 0.008;
}

void fragment() {
	float t = visual_time;
	vec2 drift = vec2(t * 0.008, -t * 0.006);
	float distance_to_bank = bank_distance(water_at);
	float broad = texture(surface_noise, water_at / 32.0 + drift * 0.35).r;
	float flow = texture(surface_noise, water_at / vec2(9.0, 11.0) + drift).r;
	float swell = 0.5 + 0.5 * sin(water_at.x * 2.9 + water_at.y * 3.5 - t * 0.63 + flow * 4.0);
	float foam_width = 0.045 + flow * 0.06 + pow(swell, 1.5) * 0.17;
	float edge_softness = max(fwidth(distance_to_bank) * 0.8, 0.008);
	float contact = 1.0 - smoothstep(foam_width - edge_softness, foam_width + edge_softness, distance_to_bank);
	// A broken, softer wash trails the continuous ivory contact line.
	float wash_at = foam_width + 0.18 + sin(t * 0.63 + flow * 5.0) * 0.07;
	float wash = 1.0 - smoothstep(0.012, 0.035 + edge_softness, abs(distance_to_bank - wash_at));
	wash *= smoothstep(0.46, 0.68, flow) * 0.28;
	float foam = clamp(contact + wash, 0.0, 1.0);
	float shallows = exp(-distance_to_bank * 2.6);
	vec3 water_color = vec3(0.36, 0.64, 0.64) + (broad - 0.5) * vec3(0.05, 0.04, 0.025);
	water_color = mix(water_color, vec3(0.47, 0.71, 0.65), shallows * 0.65);
	// Stretched coherent noise makes sparse drifting glints, without a tiled grid.
	float streak = texture(surface_noise, water_at / vec2(25.0, 2.4) + drift * 0.45).r;
	float fleck = smoothstep(0.76, 0.86, streak) * smoothstep(0.50, 0.69, flow);
	float distance_to_click = length(water_at - ripple_at);
	float wave = exp(-pow((distance_to_click - ripple_age * 2.9) / 0.11, 2.0));
	float ring = wave * (1.0 - smoothstep(0.15, 1.3, ripple_age));
	vec2 from_ferry = water_at - ferry_at;
	float behind = -dot(from_ferry, ferry_direction);
	float across = abs(dot(from_ferry, vec2(-ferry_direction.y, ferry_direction.x)));
	float wake = exp(-pow((across - 0.22 - behind * 0.23) / 0.065, 2.0));
	wake *= smoothstep(0.1, 0.4, behind) * (1.0 - smoothstep(0.5, 1.6, behind));
	water_color = mix(water_color, vec3(0.68, 0.83, 0.77), min(0.85, fleck * 0.24 + ring * 0.58 + wake * 0.55));
	vec3 foam_color = vec3(0.83, 0.89, 0.78);
	ALBEDO = mix(water_color, foam_color, foam * 0.92);
	EMISSION = foam_color * contact * 0.06;
	// Native depth absorption reveals only the submerged bank, then fades it
	// into the existing mint water. Inverse projection also handles this ortho camera.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#endif
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float thickness = max(VERTEX.z - scene_view.z / scene_view.w, 0.0);
	float absorption = 1.0 - exp(-thickness * 5.5);
	ALPHA = mix(0.32 + absorption * 0.68, 1.0, foam);
	vec2 slope = vec2(cos(water_at.x * 1.1 + t * 0.7), sin(water_at.y * 1.8 - t * 0.6)) * 0.018 * (1.0 - foam);
	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);
	ROUGHNESS = mix(0.40, 0.78, foam);
	SPECULAR = 0.18;
}
