shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform float visual_time = 0.0;
varying vec4 field_data;
void vertex() { field_data = INSTANCE_CUSTOM; }
void fragment() {
 vec2 p = UV * 2.0 - 1.0;
 float r = length(p);
 float a = atan(p.y, p.x);
 float fade = smoothstep(0.0, 0.10, field_data.a);
 float rim = (1.0 - smoothstep(0.013, 0.025, abs(r - 0.975))) * (0.45 + 0.55 * step(0.1, sin(a * 12.0)));
 vec2 grid = p * 4.0;
 vec2 cell = floor(grid);
 vec2 q = fract(grid) - 0.5;
 float sway = sin(visual_time * 2.0 + cell.x * 1.3 + cell.y) * 0.12;
 float stem = abs(q.x - q.y * (0.5 + sway));
 float blade = (1.0 - smoothstep(0.025, 0.07, stem)) * smoothstep(-0.26, -0.12, q.y) * (1.0 - smoothstep(0.08, 0.3, q.y));
 float rhythm = 0.45 + 0.55 * smoothstep(-0.6, 0.6, sin(visual_time * 1.9 - cell.x + cell.y * 0.6));
 ALBEDO = mix(vec3(0.73, 0.83, 0.49), field_data.rgb, 0.3);
 EMISSION = ALBEDO * 0.05;
 ALPHA = (rim * 0.55 + blade * rhythm * 0.38 * (1.0 - smoothstep(0.7, 0.94, r))) * fade;
}
