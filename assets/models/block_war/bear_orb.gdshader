shader_type spatial;
uniform float visual_time = 0.0;
varying vec4 effect;
void vertex() { effect = INSTANCE_CUSTOM; }
void fragment() {
    vec2 tiles = floor(UV * vec2(18.0, 12.0));
    float hostile = effect.g;
    float bands = 0.5 + 0.5 * sin(tiles.y * 1.25 + tiles.x * 0.55 - visual_time * mix(2.0, 4.5, hostile));
    float core = smoothstep(0.58, 0.9, bands);
    vec3 low = mix(vec3(0.66, 0.32, 0.065), vec3(0.71, 0.10, 0.025), hostile);
    vec3 high = mix(vec3(1.0, 0.78, 0.30), vec3(1.0, 0.54, 0.16), hostile);
    ALBEDO = mix(low, high, core);
    EMISSION = mix(low, high, core) * (0.25 + effect.r * 0.7);
    METALLIC = 0.12;
    ROUGHNESS = 0.19;
    SPECULAR = 0.85;
    CLEARCOAT = 0.8;
}
