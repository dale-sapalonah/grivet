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

// Fragment NORMAL is in view space; bend it with a world-space offset.
vec3 bend_normal(vec3 view_normal, vec3 world_offset, mat4 view_matrix) {
	return normalize(view_normal + mat3(view_matrix) * world_offset);
}
