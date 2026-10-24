// Port Moresby ground off the tarmac: red-brown laterite with gravel, tyre
// ruts and puddles, or (grass = 1) a patchy, sun-burnt playing field. World
// space, so any floor box.
shader_type spatial;

#include "res://levels/port/materials/port_common.gdshaderinc"

uniform vec4 laterite : source_color = vec4(0.42, 0.24, 0.14, 1.0);
uniform vec4 laterite_dark : source_color = vec4(0.26, 0.15, 0.09, 1.0);
uniform vec4 gravel : source_color = vec4(0.5, 0.46, 0.4, 1.0);
uniform vec4 grass_green : source_color = vec4(0.2, 0.32, 0.11, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.45, 0.4, 0.2, 1.0);
uniform float grass = 0.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float large = noise2(p * 0.02);
	float mid = noise2(p * 0.11 + 0.4);
	float fine = noise2(p * 1.4 + 0.9);
	vec3 color;
	float roughness;
	if (grass > 0.5) {
		// Mown stripes, bare patches near the posts and wherever play wears it.
		float stripe = step(0.5, fract(p.y / 4.0));
		color = mix(grass_dry.rgb, grass_green.rgb, smoothstep(0.3, 0.6, large + 0.15 * stripe));
		color = mix(color, laterite.rgb, smoothstep(0.7, 0.85, mid) * 0.7);
		color *= 0.8 + 0.35 * fine;
		roughness = 0.95;
	} else {
		color = mix(laterite_dark.rgb, laterite.rgb, smoothstep(0.3, 0.7, large));
		color = mix(color, gravel.rgb, smoothstep(0.6, 0.75, fine) * 0.6);
		// Tyre ruts running along the road (z).
		float rut = smoothstep(0.35, 0.0, abs(fract(p.x / 2.2) - 0.5) - 0.3) * smoothstep(0.4, 0.7, noise2(vec2(p.x * 0.3, p.y * 0.02)));
		color *= 1.0 - 0.25 * rut;
		color *= 0.82 + 0.3 * fine;
		roughness = 0.9;
		float water = smoothstep(0.7, 0.74, mid * 0.7 + (1.0 - large) * 0.3);
		color = mix(color, color * 0.55, water);
		roughness = mix(roughness, 0.05, water);
	}
	vec2 slope = noise_slope(p * 2.0, 0.02) * 0.015;
	NORMAL = bend_normal(NORMAL, vec3(-slope.x, 0.0, -slope.y) + detail_bend(p, vec3(1, 0, 0), vec3(0, 0, 1)), VIEW_MATRIX);
	ALBEDO = color;
	ROUGHNESS = detail_rough(p, roughness);
}
