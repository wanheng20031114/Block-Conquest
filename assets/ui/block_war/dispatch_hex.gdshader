shader_type canvas_item;
render_mode unshaded;

instance uniform vec2 frame_size = vec2(70.0, 62.0);
instance uniform float selection : hint_range(0.0, 1.0) = 0.0;
instance uniform float phase : hint_range(0.0, 1.0) = 1.0;
instance uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
instance uniform float focus_amount : hint_range(0.0, 1.0) = 0.0;
instance uniform float availability : hint_range(0.0, 1.0) = 1.0;
uniform vec4 line_color : source_color = vec4(0.98, 0.97, 0.87, 0.82);
uniform vec4 accent_color : source_color = vec4(1.0, 0.87, 0.53, 1.0);

// Signed edge distance and shortest perimeter travel from the top midpoint.
// Tracing both directions reaches the bottom midpoint at travel == 1.
vec2 hex_edge(vec2 p, vec2 half_size) {
	vec2 vertices[6] = vec2[6](
		vec2(-half_size.x * 0.5, -half_size.y), vec2(half_size.x * 0.5, -half_size.y),
		vec2(half_size.x, 0.0), vec2(half_size.x * 0.5, half_size.y),
		vec2(-half_size.x * 0.5, half_size.y), vec2(-half_size.x, 0.0));
	float perimeter = 2.0 * half_size.x + 4.0 * length(vec2(half_size.x * 0.5, half_size.y));
	float distance_to_edge = 1000.0;
	float nearest_at = 0.0;
	float walked = 0.0;
	float inside = 1.0;
	for (int i = 0; i < 6; i++) {
		vec2 a = vertices[i];
		vec2 edge = vertices[(i + 1) % 6] - a;
		vec2 from_a = p - a;
		float along = clamp(dot(from_a, edge) / dot(edge, edge), 0.0, 1.0);
		float d = length(from_a - edge * along);
		if (d < distance_to_edge) {
			distance_to_edge = d;
			nearest_at = walked + length(edge) * along;
		}
		inside *= step(0.0, edge.x * from_a.y - edge.y * from_a.x);
		walked += length(edge);
	}
	float travel = fract((nearest_at - half_size.x * 0.5) / perimeter + 1.0);
	return vec2(distance_to_edge * (1.0 - 2.0 * inside), min(travel, 1.0 - travel) * 2.0);
}

vec4 over(vec4 base, vec4 top) {
	float alpha = top.a + base.a * (1.0 - top.a);
	return vec4((top.rgb * top.a + base.rgb * base.a * (1.0 - top.a)) / max(alpha, 0.0001), alpha);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * frame_size;
	vec2 half_size = frame_size * 0.5 - vec2(2.5);
	vec2 edge = hex_edge(p, half_size);
	float aa = max(fwidth(edge.x) * 0.65, 0.55);
	float spread = smoothstep(0.48, 0.91, phase);
	float painted = (1.0 - smoothstep(spread - 0.018, spread + 0.02, edge.y)) * step(0.46, phase);
	painted = mix(painted, 1.0, smoothstep(0.90, 0.98, phase)) * selection;
	float width = mix(1.45 + hover_amount * 0.25, 2.15, painted);
	float stroke = 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, abs(edge.x));
	float shadow = (1.0 - smoothstep(1.4, 2.8, abs(edge.x))) * 0.17;
	float front = exp(-abs(edge.y - spread) * 85.0) * painted * (1.0 - smoothstep(0.88, 1.0, phase));
	vec3 ink = mix(line_color.rgb, accent_color.rgb, painted);
	ink = mix(ink, vec3(1.0, 0.98, 0.82), front * 0.6);
	vec4 result = over(vec4(0.09, 0.16, 0.08, shadow),
		vec4(ink, stroke * mix(line_color.a + hover_amount * 0.10, 1.0, painted)));
	float focus_line = (1.0 - smoothstep(0.35, 1.15, abs(edge.x + 3.6))) * focus_amount * 0.82;
	result = over(result, vec4(line_color.rgb, focus_line));

	// 0–40 ms: gather at the foot. 40–106 ms: rush up the left edge,
	// clear of the numeral. 106–200 ms: divide and flood the outline.
	float gather = smoothstep(0.0, 0.18, phase);
	float rise = smoothstep(0.18, 0.48, phase);
	vec2 seed = vec2(-half_size.x * sin(rise * 3.14159265), mix(half_size.y - 2.0, -half_size.y, rise));
	vec2 direction = normalize(vec2(-half_size.x * 3.14159265 * cos(rise * 3.14159265), -2.0 * half_size.y));
	vec2 across = vec2(-direction.y, direction.x);
	vec2 offset = p - seed;
	float flying = sin(rise * 3.14159265);
	vec2 radius = vec2(mix(2.0, 3.5, gather), 3.0 + flying * 3.0);
	float body_distance = length(vec2(dot(offset, across), dot(offset, direction)) / radius);
	float seed_life = (1.0 - smoothstep(0.47, 0.62, phase)) * selection;
	float body = (1.0 - smoothstep(0.65, 1.10, body_distance)) * seed_life;
	float halo = (1.0 - smoothstep(0.6, 1.65, body_distance)) * seed_life * 0.12;
	float bead_spread = (1.0 - gather) * 9.0;
	vec2 foot = vec2(0.0, half_size.y - 2.0);
	float beads = min(length(p - foot - vec2(bead_spread, 0.0)), length(p - foot + vec2(bead_spread, 0.0)));
	float bead_alpha = (1.0 - smoothstep(1.0, 2.1, beads)) * (1.0 - gather) * selection;
	result = over(result, vec4(accent_color.rgb, max(halo, bead_alpha)));
	result = over(result, vec4(mix(accent_color.rgb, vec3(1.0, 0.97, 0.79), 0.25), body));
	COLOR = vec4(result.rgb, result.a * availability) * COLOR;
}
