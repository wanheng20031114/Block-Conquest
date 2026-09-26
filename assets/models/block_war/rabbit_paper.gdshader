shader_type spatial;
render_mode cull_disabled;
uniform float visual_time = 0.0;
uniform float release = 0.0;
uniform vec4 paper_color : source_color = vec4(0.93, 0.86, 0.65, 1.0);
void vertex() {
	float tip = smoothstep(0.35, 1.3, abs(VERTEX.x));
	VERTEX.z += tip * sin(visual_time * 2.0 + VERTEX.x * 2.8) * 0.025;
	VERTEX.z += release * tip * tip * 0.65;
	VERTEX.y += release * tip * 0.2;
}
void fragment() {
	float fold = 0.94 + 0.06 * step(0.45, fract(UV.x * 5.0));
	ALBEDO = paper_color.rgb * fold;
	ROUGHNESS = 0.95;
}
