shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://assets/models/block_war/ground_surface.gdshaderinc"

uniform float age = 0.0;
uniform int kind = 0; // 0: landing, 1: building preparation.
uniform float strength = 1.0;
uniform vec4 tint : source_color = vec4(0.93, 0.65, 0.62, 1.0);

void vertex() {
	terrain_clearance = 0.12;
	terrain_world = ground_effect_world(VERTEX, MODEL_MATRIX, terrain_clearance);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(terrain_world, 1.0)).xyz;
}

void fragment() {
	if (ground_effect_gap(terrain_world, terrain_clearance)) { discard; }
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float rim = 1.0 - smoothstep(0.012, 0.035, abs(r - 0.98));
	float dashes = smoothstep(-0.18, 0.18, cos(angle * 16.0 - age * 0.7));
	if (kind == 1) {
		float fade = smoothstep(0.0, 0.12, strength);
		float shimmer = 0.72 + sin(age * 2.5) * 0.15;
		ALBEDO = tint.rgb;
		ALPHA = rim * dashes * shimmer * 0.42 * fade;
	} else {
		float fall = clamp(age / 0.65, 0.0, 1.0);
		float after = max(age - 0.65, 0.0);
		float shadow = (1.0 - smoothstep(0.18 + fall * 0.40, 0.72 + fall * 0.26, r)) * 0.22;
		float pre = 1.0 - step(0.65, age);
		float impact = (1.0 - smoothstep(0.025, 0.12, abs(r - clamp(after * 2.0, 0.0, 0.98)))) * (1.0 - smoothstep(0.25, 0.65, after));
		float glow = exp(-r * 4.0) * (1.0 - smoothstep(0.0, 0.18, after)) * (1.0 - pre);
		ALBEDO = mix(tint.rgb, vec3(0.21, 0.17, 0.16), pre * shadow * 2.0);
		EMISSION = tint.rgb * (impact * 0.20 + glow * 0.25);
		ALPHA = pre * (rim * dashes * (0.36 + fall * 0.20) + shadow) + (1.0 - pre) * (impact * 0.52 + glow * 0.20);
	}
}
