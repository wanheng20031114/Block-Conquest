shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://assets/models/block_war/militia_motion.gdshaderinc"

void fragment() {
	float heraldry = step(0.75, COLOR.a);
	float metal = step(0.25, COLOR.a) * (1.0 - heraldry);
	ALBEDO = mix(COLOR.rgb, faction_color, heraldry);
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.6);
	vec3 rush_red = vec3(0.85, 0.035, 0.025);
	// Keep faction cloth recognizable; the fast red edge belongs to the buff.
	ALBEDO = mix(ALBEDO, rush_red, rushing * (0.10 + rim * 0.22) * (1.0 - heraldry * 0.75));
	EMISSION = rush_red * rushing * (0.06 + rim * 0.34);
	METALLIC = metal * 0.24;
	ROUGHNESS = mix(0.88, 0.62, metal);
}
