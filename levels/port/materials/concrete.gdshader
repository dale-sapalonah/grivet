// Cast concrete for barriers and the warehouse: mottled, with formwork joints
// on walls, rain streaks running down, and grime splashed up from the ground.
// World space, projected on the dominant face axis.
shader_type spatial;

#include "res://levels/port/materials/port_common.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.5, 0.49, 0.46, 1.0);
uniform vec4 grime_color : source_color = vec4(0.2, 0.19, 0.17, 1.0);
uniform float panel_width = 2.4;  // formwork joints; 0 = none
uniform float panel_height = 1.2;
uniform float grime_height = 0.7;
// Tint by vertex colour (sRGB), e.g. painted bands on baked meshes.
uniform bool use_vertex_color = false;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool top = n.y > 0.5;
	vec2 uv = top ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	float mottle = noise2(uv * 0.09);
	float fine = noise2(uv * 1.3 + 0.21);
	vec3 color = base_color.rgb * (0.8 + 0.3 * mottle) * (0.9 + 0.2 * fine);
	if (use_vertex_color) {
		color *= pow(COLOR.rgb, vec3(2.2));
	}
	float roughness = 0.88;

	if (!top) {
		// Rain streaks: noise stretched vertically.
		float streak = noise2(vec2(uv.x * 0.9, uv.y * 0.06 + 0.5));
		color *= 1.0 - 0.3 * smoothstep(0.55, 0.8, streak);
		// Grime from the ground up.
		float grime = 1.0 - smoothstep(0.0, grime_height, world_position.y + 0.25 * (fine - 0.5));
		color = mix(color, grime_color.rgb, grime * 0.7);
		if (panel_width > 0.0) {
			float joint = min(grid_distance(uv.x, panel_width), grid_distance(uv.y, panel_height));
			color *= mix(0.6, 1.0, smoothstep(0.008, 0.02, joint));
		}
	}
	// Pitted, trowelled surface: small bumps that shade with the light.
	vec2 slope = noise_slope(uv * 2.2, 0.02) * 0.01;
	vec3 tangent_u = top ? vec3(1, 0, 0) : (n.x > 0.5 ? vec3(0, 0, 1) : vec3(1, 0, 0));
	vec3 tangent_v = top ? vec3(0, 0, 1) : vec3(0, 1, 0);
	NORMAL = bend_normal(NORMAL, -(tangent_u * slope.x + tangent_v * slope.y) + detail_bend(uv, tangent_u, tangent_v), VIEW_MATRIX);
	ALBEDO = color;
	ROUGHNESS = detail_rough(uv, roughness);
}
