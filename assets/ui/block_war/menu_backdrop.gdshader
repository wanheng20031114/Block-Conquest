shader_type canvas_item;
render_mode unshaded;
void fragment() {
    vec2 p = UV;
    vec3 mint = vec3(0.78, 0.87, 0.80);
    vec3 cream = vec3(0.96, 0.95, 0.85);
    float wash = smoothstep(0.0, 0.95, p.y) * 0.65 + (1.0 - p.x) * 0.18;
    vec3 paper = mix(mint, cream, wash);
    // Menu-only paper tiles drift gently, echoing GodotGameUI's living backdrop.
    vec2 drift = vec2(TIME * 1.2, sin(TIME * 0.08) * 8.0);
    vec2 grid = floor((FRAGCOORD.xy + drift) / 48.0);
    float checker = mod(grid.x + grid.y, 2.0);
    paper += checker * 0.012 * (1.0 - p.y);
    float light = sin(p.x * 3.8 + p.y * 2.1 - TIME * 0.12);
    paper += light * 0.007;
    COLOR = vec4(paper, 1.0);
}
