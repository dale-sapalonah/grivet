// Port yard ground: weathered asphalt with darker repair patches, worn yellow
// lane lines and white bay ticks, betel nut stains, and rain puddles (dark, mirror-smooth: they
// pick up the sodium lamps and the dusk sky). World space, so any floor box.
shader_type spatial;

#include "res://levels/port/materials/port_common.gdshaderinc"

uniform vec4 asphalt : source_color = vec4(0.21, 0.21, 0.215, 1.0);
uniform vec4 patch_color : source_color = vec4(0.14, 0.14, 0.145, 1.0);
uniform vec4 paint_yellow : source_color = vec4(0.78, 0.62, 0.18, 1.0);
uniform vec4 paint_white : source_color = vec4(0.72, 0.72, 0.68, 1.0);
uniform vec4 buai_red : source_color = vec4(0.36, 0.05, 0.03, 1.0);
uniform float lane_spacing = 16.0;
uniform float puddles = 0.34;  // higher = more water

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float large = noise2(p * 0.011);
	float mid = noise2(p * 0.047 + 0.31);
	float fine = noise2(p * 0.83 + 0.7);

	vec3 color = mix(patch_color.rgb, asphalt.rgb, smoothstep(0.38, 0.5, large));
	color *= 0.8 + 0.4 * fine;
	float roughness = 0.82 + 0.12 * fine;

	// Lane markings: dashed yellow centre lines, white ticks marking bays.
	float lane = grid_distance(p.x + 8.0, lane_spacing);
	float dash = step(0.45, fract(p.y / 4.0));
	float wear = smoothstep(0.32, 0.5, noise2(p * 0.37 + 0.13));
	float yellow = (1.0 - smoothstep(0.06, 0.075, lane)) * dash * wear;
	float tick = (1.0 - smoothstep(0.05, 0.065, grid_distance(p.y, 6.4)))
			* (1.0 - smoothstep(1.2, 1.22, abs(lane - 2.4))) * wear;
	color = mix(color, paint_yellow.rgb, yellow * 0.85);
	color = mix(color, paint_white.rgb, tick * 0.7);
	roughness = mix(roughness, 0.6, max(yellow, tick));

	// Betel nut (buai) spit: red splashes, thicker in some stretches.
	float buai = smoothstep(0.84, 0.9, noise2(p * 1.9 + 4.1)) * smoothstep(0.5, 0.68, noise2(p * 0.05 + 2.3));
	color = mix(color, buai_red.rgb, buai * 0.85);

	// Puddles collect in the low patches.
	float water = smoothstep(1.0 - puddles, 1.0 - puddles + 0.04, mid * 0.75 + (1.0 - large) * 0.25);
	float damp = smoothstep(1.0 - puddles - 0.08, 1.0 - puddles, mid * 0.75 + (1.0 - large) * 0.25);
	color *= 1.0 - 0.35 * damp - 0.25 * water;
	roughness = mix(roughness, 0.45, damp);
	roughness = mix(roughness, 0.03, water);

	ALBEDO = color;
	ROUGHNESS = roughness;
	SPECULAR = mix(0.5, 0.7, water);
}
