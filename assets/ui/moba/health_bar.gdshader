shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled;
instance uniform float health : hint_range(0.0, 1.0) = 1.0;
instance uniform vec4 bar_color : source_color = vec4(.53, .75, .33, 1.0);

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float compact = 1.0;
	// Perspective bars keep a modest angular size; the RTS view preserves its bars.
	if (abs(PROJECTION_MATRIX[3][3]) < .5) {
		compact = clamp(distance(origin, INV_VIEW_MATRIX[3].xyz) * .025, .12, .7);
	}
	mat4 billboard = mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz) * compact, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz) * compact, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
}

void fragment() {
	vec2 edge = abs(UV - vec2(.5));
	float border = max(step(.488, edge.x), step(.445, edge.y));
	float amount = step(UV.x, mix(.012, .988, clamp(health, 0.0, 1.0)));
	ALBEDO = mix(mix(vec3(.15,.19,.2), bar_color.rgb, amount), vec3(.1,.13,.14), border);
	ALPHA = 1.0;
}
