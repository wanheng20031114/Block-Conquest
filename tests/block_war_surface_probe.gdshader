shader_type canvas_item;
render_mode unshaded;
#include "res://assets/models/block_war/terrain_height.gdshaderinc"

uniform vec2 probe_point = vec2(0.0);

void fragment() {
	// The HDR viewport returns the real metre value without display tonemapping.
	COLOR = vec4(terrain_height(probe_point), 0.0, 0.0, 1.0);
}
