shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float visual_time = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform vec4 ring_color : source_color = vec4(0.88, 0.34, 0.16, 1.0);
varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float angle = atan(local_position.z, local_position.x);
	float dash = fract(angle * 1.909859 + visual_time * 0.26);
	float stroke = smoothstep(0.02, 0.10, dash) * (1.0 - smoothstep(0.71, 0.83, dash));
	float glint = pow(max(0.0, cos(angle - visual_time * 2.8)), 12.0);
	float pulse = 0.82 + 0.18 * sin(visual_time * 5.2);
	ALBEDO = mix(ring_color.rgb, vec3(1.0, 0.85, 0.46), glint * 0.75);
	ALPHA = stroke * opacity * pulse;
}
