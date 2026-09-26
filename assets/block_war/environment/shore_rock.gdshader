shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D meadow_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 dry_stone : source_color = vec4(0.63, 0.65, 0.53, 1.0);
uniform vec4 wet_stone : source_color = vec4(0.29, 0.43, 0.385, 1.0);
uniform float water_height = -1.18;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float grain = texture(meadow_noise, world_position.xz / 24.0).r;
	float dry = smoothstep(water_height + 0.05, water_height + 0.63,
		world_position.y + (grain - 0.5) * 0.09);
	ALBEDO = mix(wet_stone.rgb, dry_stone.rgb, dry) * (0.94 + grain * 0.12);
	ROUGHNESS = mix(0.42, 0.94, dry);
	SPECULAR = 0.20;
}
