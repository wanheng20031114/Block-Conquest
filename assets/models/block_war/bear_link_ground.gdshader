shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"
uniform float visual_time = 0.0;
varying vec4 effect;

void vertex() {
	terrain_clearance = 0.115;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
	effect = INSTANCE_CUSTOM;
}

float stroke(float distance, float width) {
	float aa = max(fwidth(distance), 0.003);
	return 1.0 - smoothstep(width - aa, width + aa, abs(distance));
}

void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float response = effect.r > 0.001 ? exp(-pow((effect.g - (1.0 - effect.r) * 1.5) * 5.0, 2.0)) : 0.0;
	float fade = smoothstep(0.0, 0.045, effect.b) * smoothstep(0.0, 0.018, 1.0 - effect.b);
	float breath = 0.91 + 0.09 * sin(visual_time * 2.2);
	float ring = stroke(r - 0.80, 0.015);
	float outer = stroke(r - 0.91, 0.011) * smoothstep(0.15, 0.30, abs(sin(angle * 6.0)));
	// Paired bracket marks and a port beneath the clasp identify the two ends.
	float bracket = stroke(r - 0.85, 0.037) * pow(max(0.0, cos(angle * 4.0)), 30.0);
	float port = stroke(abs(p.x) + abs(p.y + 0.80) - 0.10, 0.019);
	float shadow = stroke(r - 0.80, 0.040) + stroke(r - 0.91, 0.032);
	float wave = stroke(r - mix(0.64, 0.99, 1.0 - response), 0.022) * response;
	float glow = exp(-pow((r - 0.85) * 10.0, 2.0)) * (0.09 + response * 0.14);
	float ink = clamp(ring + outer * 0.7 + bracket + port + wave, 0.0, 1.0);
	ALBEDO = mix(vec3(0.24, 0.16, 0.055), vec3(1.0, 0.81, 0.40), ink);
	ALBEDO = mix(ALBEDO, vec3(1.0, 0.94, 0.69), response * ink * 0.75);
	ALPHA = clamp(shadow * 0.32 + ink * 0.76 + glow, 0.0, 0.94) * fade * breath;
}
