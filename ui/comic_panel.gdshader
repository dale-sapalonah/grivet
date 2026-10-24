// Illustrated look for the title panels: posterised colour, inked outlines
// where colour or brightness jumps, and halftone dots in the shadows - the
// painted-poster style of crime-sandbox box art, from a live 3D render.
shader_type canvas_item;

uniform float levels = 5.0;
uniform float ink_threshold = 0.16;
uniform float saturation = 1.35;
uniform float dot_size = 5.0;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 color = texture(TEXTURE, UV).rgb;
	// Sobel on brightness and colour: ink where they change sharply.
	float tl = luma(texture(TEXTURE, UV + px * vec2(-1, -1)).rgb);
	float t = luma(texture(TEXTURE, UV + px * vec2(0, -1)).rgb);
	float tr = luma(texture(TEXTURE, UV + px * vec2(1, -1)).rgb);
	float l = luma(texture(TEXTURE, UV + px * vec2(-1, 0)).rgb);
	float r = luma(texture(TEXTURE, UV + px * vec2(1, 0)).rgb);
	float bl = luma(texture(TEXTURE, UV + px * vec2(-1, 1)).rgb);
	float b = luma(texture(TEXTURE, UV + px * vec2(0, 1)).rgb);
	float br = luma(texture(TEXTURE, UV + px * vec2(1, 1)).rgb);
	float gx = (tr + 2.0 * r + br) - (tl + 2.0 * l + bl);
	float gy = (bl + 2.0 * b + br) - (tl + 2.0 * t + tr);
	float edge = smoothstep(ink_threshold, ink_threshold * 1.8, length(vec2(gx, gy)));
	// Punchier colour, flattened into a few painted bands.
	float y = luma(color);
	color = mix(vec3(y), color, saturation);
	color = floor(color * levels + 0.5) / levels;
	// Halftone dots in the darker tones.
	vec2 cell = fract(FRAGCOORD.xy / dot_size) - 0.5;
	float dots = step(length(cell), (1.0 - smoothstep(0.1, 0.45, y)) * 0.55);
	color *= 1.0 - 0.35 * dots;
	COLOR = vec4(mix(color, vec3(0.02, 0.015, 0.01), edge), 1.0);
}
