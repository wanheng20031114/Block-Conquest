shader_type canvas_item;
render_mode unshaded;

// Paper veils reserve quiet reading space without framing the landscape in a panel.
void fragment() {
	float header = (1.0 - smoothstep(0.02, 0.23, UV.y));
	header *= mix(0.42, 0.96, 1.0 - smoothstep(0.30, 0.73, UV.x));
	float footer = smoothstep(0.69, 0.87, UV.y) * 0.98;
	COLOR = vec4(vec3(0.976, 0.965, 0.92), max(header, footer));
}
