shader_type canvas_item;
render_mode unshaded;
void fragment() {
    vec2 p = UV;
    vec3 mint = vec3(0.78, 0.87, 0.80);
    vec3 cream = vec3(0.96, 0.95, 0.85);
    float wash = smoothstep(0.0, 0.95, p.y) * 0.65 + (1.0 - p.x) * 0.18;
    vec3 paper = mix(mint, cream, wash);
    vec2 grid = floor(FRAGCOORD.xy / 48.0);
    float checker = mod(grid.x + grid.y, 2.0);
    paper += checker * 0.012 * (1.0 - p.y);
    COLOR = vec4(paper, 1.0);
}
