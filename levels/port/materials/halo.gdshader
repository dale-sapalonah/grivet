// Light halo: an additive camera-facing quad with a soft radial falloff. Gives
// lamps their bloom without a full-screen glow pass (2-3 ms on the HD 630).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.24, 1.0);
uniform float intensity = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float core = pow(max(0.0, 1.0 - d), 6.0);
	float falloff = pow(max(0.0, 1.0 - d), 2.2) * 0.35;
	ALBEDO = color.rgb * (core + falloff) * intensity;
}
