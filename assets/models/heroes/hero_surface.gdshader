shader_type spatial;
render_mode cull_back;
instance uniform vec4 garment_color : source_color = vec4(0.10,0.54,0.67,1.0);
instance uniform vec4 face_color : source_color = vec4(0.94,0.84,0.63,1.0);
instance uniform vec4 boot_color : source_color = vec4(0.34,0.22,0.15,1.0);
instance uniform vec4 team_color : source_color = vec4(0.10,0.54,0.67,1.0);
void fragment() {
    vec3 tint = COLOR.rgb;
    float tag = COLOR.a;
    if (tag > 0.85) tint = team_color.rgb;
    else if (tag > 0.35 && tag < 0.45) tint = boot_color.rgb;
    else if (tag > 0.25 && tag < 0.35) tint = garment_color.rgb;
    else if (tag > 0.15 && tag < 0.25) tint = face_color.rgb;
    else if (tag > 0.05 && tag < 0.15) tint = garment_color.rgb;
    ALBEDO = tint;
    METALLIC = (tag > 0.48 && tag < 0.55) ? 0.45 : 0.0;
    ROUGHNESS = METALLIC > 0.0 ? 0.62 : 0.87;
}
