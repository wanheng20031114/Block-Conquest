shader_type canvas_item;
render_mode unshaded;

uniform vec2 viewport_size = vec2(1600.0, 900.0);
uniform int spotlight_count = 0;
uniform vec4 spotlights[8];
uniform vec4 veil_color : source_color = vec4(0.055, 0.085, 0.064, 0.70);
uniform vec4 rim_color : source_color = vec4(0.98, 0.84, 0.48, 0.52);

float rounded_rectangle(vec2 point, vec4 rect) {
	vec2 half_size = max(rect.zw * 0.5, vec2(1.0));
	float radius = min(20.0, min(half_size.x, half_size.y));
	vec2 q = abs(point - rect.xy - half_size) - half_size + radius;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

void fragment() {
	vec2 point = UV * viewport_size;
	float distance = 100000.0;
	for (int index = 0; index < 8; index++) {
		if (index < spotlight_count) {
			distance = min(distance, rounded_rectangle(point, spotlights[index]));
		}
	}
	float veil = smoothstep(-2.0, 16.0, distance);
	float rim = (1.0 - smoothstep(1.0, 3.0, abs(distance))) * (0.80 + sin(TIME * 2.0) * 0.12);
	float halo = (1.0 - smoothstep(2.0, 22.0, abs(distance))) * 0.10;
	vec3 shade = mix(veil_color.rgb, rim_color.rgb, clamp(rim + halo, 0.0, 1.0));
	COLOR = vec4(shade, max(veil_color.a * veil, rim_color.a * (rim + halo)));
}
