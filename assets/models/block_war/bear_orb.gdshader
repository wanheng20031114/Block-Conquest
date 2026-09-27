shader_type spatial;
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
    vec2 tiles = floor(UV * vec2(18.0, 12.0));
    float bands = 0.5 + 0.5 * sin(tiles.y * 1.25 + tiles.x * 0.55 - visual_time * 2.0);
    float core = smoothstep(0.58, 0.9, bands);
    ALBEDO = mix(vec3(0.66, 0.32, 0.065), vec3(1.0, 0.78, 0.30), core);
    EMISSION = mix(vec3(0.64, 0.29, 0.03), vec3(1.0, 0.76, 0.28), core) * (0.25 + effect.r * 0.7);
    METALLIC = 0.12;
    ROUGHNESS = 0.19;
    SPECULAR = 0.85;
    CLEARCOAT = 0.8;
}
