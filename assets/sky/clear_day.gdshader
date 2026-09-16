shader_type sky;

uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
// Linear HDR data baked by Godot, not an sRGB display image.
uniform sampler2D lighting_panorama : filter_linear_mipmap, repeat_enable;

void sky() {
	// Background art must not retint every existing unit and ground material.
	// Both passes are static: no clock, camera-position dependency or cloud raymarch.
	if (AT_CUBEMAP_PASS) {
		COLOR = texture(lighting_panorama, SKY_COORDS).rgb;
	} else {
		// Wrap longitude only: vertical wrapping would sample the nadir at the zenith.
		float half_pixel = 0.5 / float(textureSize(panorama, 0).y);
		vec2 uv = vec2(SKY_COORDS.x, clamp(SKY_COORDS.y, half_pixel, 1.0 - half_pixel));
		// Longitude derivatives diverge at the pole. An implicit mip level would
		// average the entire panorama into a pale dot while looking straight up.
		COLOR = textureLod(panorama, uv, 0.0).rgb;
	}
}
