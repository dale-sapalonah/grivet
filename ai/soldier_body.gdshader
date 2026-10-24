// Soldier body: vertex colours (sRGB) for skin, gear, boots and metal; pieces
// flagged with COLOR.a = 1 are uniform cloth and get a procedural camouflage
// pattern in the part's own space (so it travels with the ragdoll), plus a
// little fabric grain. One material for the whole soldier: few draw calls.
shader_type spatial;

uniform vec4 camo_a : source_color = vec4(0.33, 0.36, 0.26, 1.0);
uniform vec4 camo_b : source_color = vec4(0.22, 0.24, 0.17, 1.0);
uniform vec4 camo_c : source_color = vec4(0.45, 0.42, 0.32, 1.0);
uniform float camo_scale = 11.0;
uniform float cloth_roughness = 0.88;
uniform float gear_roughness = 0.65;

varying vec3 local_position;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	float roughness = gear_roughness;
	if (COLOR.a > 0.5) {
		float n = noise(local_position * camo_scale) * 0.65 + noise(local_position * camo_scale * 2.3) * 0.35;
		base = n < 0.42 ? camo_a.rgb : (n < 0.6 ? camo_b.rgb : camo_c.rgb);
		base *= 0.9 + 0.1 * noise(local_position * 90.0);
		roughness = cloth_roughness;
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
}
