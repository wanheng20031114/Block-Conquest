// RF stores real metres. Match the baked mesh and WarTerrainSurface.sample()
// exactly; bilinear texture filtering would curve each pair of flat triangles.
uniform bool terrain_enabled = false;
uniform vec2 terrain_origin = vec2(0.0);
uniform float terrain_cell_size = 0.5;
uniform ivec2 terrain_size = ivec2(0);
uniform sampler2D terrain_heights : filter_nearest, repeat_disable;

float terrain_height(vec2 point) {
	if (!terrain_enabled) {
		return 0.0;
	}
	vec2 grid = (point - terrain_origin) / terrain_cell_size;
	vec2 last = vec2(terrain_size - ivec2(1));
	if (grid.x < 0.0 || grid.y < 0.0 || grid.x > last.x || grid.y > last.y) {
		return 0.0;
	}
	ivec2 cell = min(ivec2(floor(grid)), terrain_size - ivec2(2));
	vec2 fraction = grid - vec2(cell);
	float a = texelFetch(terrain_heights, cell, 0).r;
	float b = texelFetch(terrain_heights, cell + ivec2(1, 0), 0).r;
	float c = texelFetch(terrain_heights, cell + ivec2(0, 1), 0).r;
	float d = texelFetch(terrain_heights, cell + ivec2(1, 1), 0).r;
	if (fraction.x + fraction.y <= 1.0) {
		return a + (b - a) * fraction.x + (c - a) * fraction.y;
	}
	return d + (c - d) * (1.0 - fraction.x) + (b - d) * (1.0 - fraction.y);
}
