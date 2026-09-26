shader_type sky;

// Static cloud masses update the radiance cubemap only when edited. Animated
// water normals supply movement; TIME here would rebake the sky every frame.
uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform vec4 zenith : source_color = vec4(0.43, 0.66, 0.79, 1.0);
uniform vec4 horizon : source_color = vec4(0.78, 0.85, 0.80, 1.0);
uniform vec4 cloud_light : source_color = vec4(0.92, 0.94, 0.86, 1.0);
uniform vec4 ground : source_color = vec4(0.35, 0.405, 0.285, 1.0);

void sky() {
	float height = max(EYEDIR.y, 0.0);
	vec3 color = mix(horizon.rgb, zenith.rgb, pow(height, 0.38));
	vec2 cloud_uv = EYEDIR.xz / max(EYEDIR.y + 0.38, 0.1) * 0.17;
	float clouds = texture(cloud_noise, cloud_uv).r * 0.76
		+ texture(cloud_noise, cloud_uv * 2.3 + vec2(0.31, 0.62)).r * 0.24;
	float cover = smoothstep(0.49, 0.69, clouds) * smoothstep(0.01, 0.22, height);
	color = mix(color, cloud_light.rgb, cover * 0.82);
	COLOR = mix(ground.rgb * 0.55, color * 0.85, smoothstep(-0.14, 0.025, EYEDIR.y));
}
