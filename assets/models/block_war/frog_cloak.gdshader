shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;
#include "res://assets/models/block_war/militia_motion.gdshaderinc"

void fragment() {
    float cloth = step(0.75, COLOR.a);
    float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
    ALBEDO = mix(COLOR.rgb, faction_color, cloth) * 0.5 + vec3(0.24, 0.32, 0.28);
    ROUGHNESS = 0.85;
    SPECULAR = 0.1;
    // A quiet contour follows the actual animated mesh. No outline billboard,
    // visible shadow or bright rushing edge reveals the hidden formation.
    ALPHA = 0.025 + rim * 0.12;
}
