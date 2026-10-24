// Soldier body: vertex colours (sRGB) for skin, gear, boots and metal; pieces
// flagged with COLOR.a = 0.5 are plain cloth (weave only); COLOR.a = 1 are
// uniform cloth and get a procedural camouflage
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
	float specular = 0.4;
	if (COLOR.a > 0.25) {
		if (COLOR.a > 0.75) {
			float n = noise(local_position * camo_scale) * 0.65 + noise(local_position * camo_scale * 2.3) * 0.35;
			base = n < 0.42 ? camo_a.rgb : (n < 0.6 ? camo_b.rgb : camo_c.rgb);
		}
		// Woven cloth: a fine rip-stop grid that catches light, and creases.
		vec3 q = local_position * 260.0;
		float weave = (sin(q.x + q.y) * sin(q.y - q.z)) * 0.5 + 0.5;
		float crease = noise(local_position * 28.0);
		base *= (0.86 + 0.14 * weave) * (0.85 + 0.25 * crease);
		NORMAL = normalize(NORMAL + (vec3(weave, crease, weave) - 0.5) * 0.18);
		roughness = cloth_roughness;
		specular = 0.25;
	} else if (base.r > base.b * 1.2 && base.r > 0.06 && base.r < 0.45 && base.g < base.r * 0.85) {
		// Skin (warm, mid-dark): a soft sheen and slight pores.
		roughness = 0.5;
		specular = 0.45;
		base *= 0.94 + 0.06 * noise(local_position * 160.0);
	}
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
