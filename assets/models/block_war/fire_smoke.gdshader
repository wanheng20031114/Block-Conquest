shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
#include "res://assets/models/block_war/terrain_height.gdshaderinc"

uniform float opacity : hint_range(0.0, 1.0) = 0.32;
uniform float emitter_surface_height = 0.0;

void vertex() {
	vec4 origin = MODEL_MATRIX[3];
	if (terrain_enabled) {
		origin.y += terrain_height(origin.xz) - emitter_surface_height;
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), origin);
}

void fragment() {
	float puff = 1.0 - smoothstep(0.12, 0.50, length(UV - vec2(0.5)));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * puff * opacity;
}
