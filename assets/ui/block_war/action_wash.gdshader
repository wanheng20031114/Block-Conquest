shader_type canvas_item;
uniform float veil_opacity : hint_range(0.0, 1.0) = 0.53;

// A feathered veil has no frame, corners, border or hard panel silhouette.
void fragment() {
	vec2 edge = smoothstep(vec2(0.0), vec2(0.15, 0.3), UV) *
		smoothstep(vec2(0.0), vec2(0.15, 0.3), vec2(1.0) - UV);
	COLOR = vec4(vec3(1.0), edge.x * edge.y * veil_opacity);
}
