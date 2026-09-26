// World-space colour masses shared by all six battlefields.
vec3 painted_meadow(vec2 p, vec3 base, vec3 shade, vec3 sunlight) {
	vec2 warp = vec2(texture(meadow_noise, p / 173.0).r,
		texture(meadow_noise, p / 173.0 + vec2(0.39, 0.71)).r) - 0.5;
	vec2 q = p + warp * 11.0;
	float broad = texture(meadow_noise, q / 145.0 + vec2(0.23, 0.17)).r;
	float patches = texture(meadow_noise, q / 61.0 + vec2(0.41, 0.76)).r;
	float flecks = texture(meadow_noise, p / 13.0).r;
	float contour = broad * 0.74 + patches * 0.26 + (flecks - 0.5) * 0.045;
	vec3 color = mix(shade, base, smoothstep(0.355, 0.395, contour));
	color = mix(color, sunlight, smoothstep(0.535, 0.575, contour) * 0.76);
	return color * (0.985 + patches * 0.03);
}

float meadow_segment(vec2 p, vec2 a, vec2 b) {
	vec2 d = b - a;
	return length(p - a - d * clamp(dot(p - a, d) / dot(d, d), 0.0, 1.0));
}

// Sparse V-shaped blades, antialiased in world space and faded at distance.
float meadow_blades(vec2 p) {
	vec2 cell = floor(p / 1.35);
	vec2 seed = fract(sin(vec2(dot(cell, vec2(127.1, 311.7)),
		dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
	vec2 q = (fract(p / 1.35) - 0.5) * 1.35 - (seed - 0.5) * 0.65;
	float blade = min(meadow_segment(q, vec2(0.0, 0.10), vec2(-0.10, -0.09)),
		meadow_segment(q, vec2(0.0, 0.10), vec2(0.12, -0.13)));
	float pixel = max(length(fwidth(p)), 0.005);
	return (1.0 - smoothstep(0.017, 0.017 + pixel * 0.75, blade))
		* step(0.82, seed.x) * (1.0 - smoothstep(0.10, 0.23, pixel));
}
