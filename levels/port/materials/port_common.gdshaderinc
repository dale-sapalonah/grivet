// Shared helpers for the port's procedural surfaces. Noise comes from one
// generated, tiling noise texture (noise.tres) rather than math noise: a
// texture read is far cheaper than hashing on an integrated GPU.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

float noise2(vec2 uv) {
	return texture(noise_tex, uv).r;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Distance (m) to the nearest line of a grid with the given spacing.
float grid_distance(float x, float spacing) {
	return abs(fract(x / spacing + 0.5) - 0.5) * spacing;
}

// Slope of the noise at `uv` (per unit uv): the gradient for bump detail.
vec2 noise_slope(vec2 uv, float step_size) {
	float here = noise2(uv);
	return vec2(noise2(uv + vec2(step_size, 0.0)) - here, noise2(uv + vec2(0.0, step_size)) - here) / step_size;
}

// Optional authored PBR detail (PbrLibrary fills these from assets/textures/
// when files exist): a tiling normal map and roughness map, projected with the
// surface's own two in-plane axes. Strength 0 = procedural only.
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_strength = 0.0;
uniform float detail_roughness_mix = 0.0;
uniform float detail_tiling = 0.5;  // repeats per metre

// World-space normal offset from the detail normal map at `uv` (metres).
vec3 detail_bend(vec2 uv, vec3 axis_u, vec3 axis_v) {
	if (detail_strength <= 0.0) {
		return vec3(0.0);
	}
	vec3 n = texture(detail_normal, uv * detail_tiling).xyz * 2.0 - 1.0;
	return (axis_u * n.x + axis_v * n.y) * detail_strength;
}

float detail_rough(vec2 uv, float roughness) {
	return mix(roughness, texture(detail_roughness, uv * detail_tiling).r, detail_roughness_mix);
}

// Fragment NORMAL is in view space; bend it with a world-space offset.
vec3 bend_normal(vec3 view_normal, vec3 world_offset, mat4 view_matrix) {
	return normalize(view_normal + mat3(view_matrix) * world_offset);
}
