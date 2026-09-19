shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D meadow : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform sampler2D earth : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D woodland : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform sampler2D variation : filter_linear_mipmap, repeat_enable;
uniform vec4 grass_color : source_color = vec4(0.49, 0.64, 0.47, 1.0);
uniform vec4 earth_color : source_color = vec4(0.74, 0.66, 0.49, 1.0);
uniform float texture_strength : hint_range(0.0, 1.0) = 0.36;
uniform uint grass_pattern_seed = 73u;
varying vec2 world_uv;

// Mirroring closes the painted source edges. Randomized sampling below removes
// its periodic arrangement without introducing more colors or finer detail.
vec2 mirrored(vec2 p) {
	return 1.0 - abs(fract(p * 0.5) * 2.0 - 1.0);
}

uint pattern_hash(uint value) {
	value = (value ^ (value >> 16u)) * 2246822519u;
	value = (value ^ (value >> 13u)) * 3266489917u;
	return value ^ (value >> 16u);
}

vec3 patch_random(vec2 key) {
	uint id = uint(int(key.x)) * 1597334677u ^ uint(int(key.y)) * 3812015801u ^ grass_pattern_seed;
	return vec3(float(pattern_hash(id) >> 8u), float(pattern_hash(id ^ 1013904223u) >> 8u), float(pattern_hash(id ^ 1664525u) >> 8u)) / 16777216.0;
}

vec3 grass_patch(sampler2D source, vec2 p, vec2 dx, vec2 dy, vec2 key) {
	vec3 random = patch_random(key);
	// Quarter turns keep the block edges aligned with the world, never diagonal.
	int turn = int(floor(random.z * 4.0));
	vec2 axis = turn == 0 ? vec2(1.0, 0.0) : turn == 1 ? vec2(0.0, 1.0) : turn == 2 ? vec2(-1.0, 0.0) : vec2(0.0, -1.0);
	mat2 rotation = mat2(axis, vec2(-axis.y, axis.x));
	float scale = mix(0.85, 1.18, random.x);
	vec2 uv = rotation * p * scale + random.xy * 23.0;
	vec2 mirror_sign = 1.0 - 2.0 * step(vec2(0.5), fract(uv * 0.5));
	// Derivatives come from continuous world coordinates, not discontinuous cell
	// IDs/offsets. This avoids false mip levels at patch edges when panning/zooming.
	// A modest half-level mip bias keeps the painted block boundaries clear.
	// Mipmaps and anisotropic filtering still handle distant/oblique surfaces.
	return textureGrad(source, mirrored(uv), (rotation * dx) * scale * mirror_sign * 0.7071, (rotation * dy) * scale * mirror_sign * 0.7071).rgb;
}

vec3 grass_pattern(sampler2D source, vec2 world, vec2 dx, vec2 dy) {
	vec2 lattice = world / 3.5;
	vec2 cell = floor(lattice);
	vec2 f = fract(lattice);
	vec2 a;
	vec2 b;
	vec2 c;
	vec3 weights;
	// Adjacent triangles share the same vertex seeds and weights. Their third
	// sample reaches zero on the edge, so a tile boundary cannot create a seam.
	if (f.x + f.y < 1.0) {
		a = cell;
		b = cell + vec2(1.0, 0.0);
		c = cell + vec2(0.0, 1.0);
		weights = vec3(1.0 - f.x - f.y, f.x, f.y);
	} else {
		a = cell + vec2(1.0);
		b = cell + vec2(0.0, 1.0);
		c = cell + vec2(1.0, 0.0);
		weights = vec3(f.x + f.y - 1.0, 1.0 - f.x, 1.0 - f.y);
	}
	// Favor the dominant source to retain crisp, simple block shapes.
	weights *= weights;
	weights *= weights;
	weights /= weights.x + weights.y + weights.z;
	vec2 p = world / 8.0;
	return grass_patch(source, p, dx, dy, a) * weights.x
		+ grass_patch(source, p, dx, dy, b) * weights.y
		+ grass_patch(source, p, dx, dy, c) * weights.z;
}

void vertex() {
	world_uv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = world_uv;
	vec2 dx = dFdx(p / 8.0);
	vec2 dy = dFdy(p / 8.0);
	float broad = texture(variation, p / 61.0).r;
	vec3 grass = mix(grass_color.rgb, grass_pattern(meadow, p, dx, dy), texture_strength);
	vec3 soil = mix(earth_color.rgb, texture(earth, mirrored(p / 9.0)).rgb, texture_strength);
	vec3 shade_grass = mix(grass_color.rgb * 0.96, grass_pattern(woodland, p, dx, dy), texture_strength);
	// Vertex red stores signed road distance, green stores woodland coverage.
	float road = smoothstep(0.43, 0.54, COLOR.r);
	float forest = smoothstep(0.2, 0.9, COLOR.g);
	grass = mix(grass, shade_grass, forest * 0.45);
	grass *= mix(0.98, 1.02, broad);
	ALBEDO = mix(grass, soil, road);
	ROUGHNESS = 0.96;
	SPECULAR = 0.0;
}
