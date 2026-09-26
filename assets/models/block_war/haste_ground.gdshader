shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float visual_time = 0.0;
varying vec4 field_data;
void vertex() { field_data = INSTANCE_CUSTOM; }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float fade = smoothstep(0.0, 0.065, field_data.a);
	// A readable outer boundary and three drifting, broken wind strokes.
	// No filled luminous disc: the terrain and marching silhouettes stay clear.
	float rim = (1.0 - smoothstep(0.014, 0.027, abs(r - 0.978)));
	float breaks = 0.45 + 0.55 * smoothstep(-0.2, 0.4, cos(angle * 5.0 + visual_time * 0.45));
	float spiral = abs(sin(angle * 2.0 - r * 7.5 + visual_time * 1.1));
	float strokes = (1.0 - smoothstep(0.015, 0.065, spiral)) * smoothstep(0.15, 0.4, r) * (1.0 - smoothstep(0.74, 0.96, r));
	vec3 mint = vec3(0.64, 0.85, 0.71);
	ALBEDO = mix(mint, field_data.rgb, 0.25);
	EMISSION = ALBEDO * 0.22;
	ALPHA = (rim * breaks * 0.58 + strokes * 0.20) * fade;
}
