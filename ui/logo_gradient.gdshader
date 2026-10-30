// The title logo's fill: a sunset gradient down each line of text, orange at
// the top to gold at the bottom; the black outline and shadow stay as drawn.
shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(1.0, 0.45, 0.08, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.86, 0.3, 1.0);
// Height of the text line in pixels (the label's).
uniform float line_height = 200.0;

varying float down;

void vertex() {
	down = VERTEX.y / line_height;
}

void fragment() {
	vec4 glyph = COLOR * texture(TEXTURE, UV);
	// The fill is drawn white, the outline and shadow dark: tint only the fill.
	if (dot(COLOR.rgb, vec3(0.333)) > 0.5) {
		glyph.rgb = mix(top_color.rgb, bottom_color.rgb, clamp(down, 0.0, 1.0));
	}
	COLOR = glyph;
}
