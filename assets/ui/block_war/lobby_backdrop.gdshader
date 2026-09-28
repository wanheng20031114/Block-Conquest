shader_type canvas_item;
render_mode unshaded;

uniform vec2 pointer = vec2(0.5);
uniform float pointer_presence = 0.0;

float soft_cloud(vec2 p, vec2 center, vec2 radius) {
	vec2 q = (p - center) / radius;
	return exp(-dot(q, q) * 2.0);
}

void fragment() {
	vec2 p = UV;
	vec3 paper = mix(vec3(0.81, 0.88, 0.80), vec3(0.965, 0.950, 0.861), smoothstep(0.0, 1.0, p.y));
	// Broad, continuous cloud shadows. No resetting sprite loop or sparkling UI.
	float cloud = soft_cloud(p, vec2(0.67 + sin(TIME * 0.075) * 0.23, 0.22), vec2(0.35, 0.22));
	cloud += soft_cloud(p, vec2(0.92 + cos(TIME * 0.052) * 0.25, 0.73), vec2(0.30, 0.19));
	paper -= cloud * vec3(0.027, 0.020, 0.019);
	float light = soft_cloud(p, pointer, vec2(0.19, 0.31));
	paper += light * pointer_presence * vec3(0.027, 0.021, 0.012);
	vec2 grid = floor((FRAGCOORD.xy + vec2(TIME * 0.6, 0.0)) / 60.0);
	paper += mod(grid.x + grid.y, 2.0) * 0.006 * (1.0 - p.y);
	COLOR = vec4(paper, 1.0);
}
