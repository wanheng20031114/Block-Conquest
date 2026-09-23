shader_type canvas_item;

// A feathered veil has no frame, corners, border or hard panel silhouette.
void fragment() {
	vec2 edge = smoothstep(vec2(0.0), vec2(0.15, 0.3), UV) *
		smoothstep(vec2(0.0), vec2(0.15, 0.3), vec2(1.0) - UV);
	COLOR = vec4(1.0, 0.99, 0.93, edge.x * edge.y * 0.53);
}
