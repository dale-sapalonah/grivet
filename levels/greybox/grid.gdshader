// World-space measuring grid for greybox geometry: 1 m cells, so heights
// and gaps can be read by eye. Projects on the dominant face axis.
shader_type spatial;

uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(0.25, 0.25, 0.25, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.02;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = n.y > 0.5 ? world_position.xz : (n.x > 0.5 ? world_position.zy : world_position.xy);
	vec2 distance_to_line = abs(fract(uv / cell_size - 0.5) - 0.5) * cell_size;
	float on_line = 1.0 - step(line_width, min(distance_to_line.x, distance_to_line.y));
	ALBEDO = mix(base_color.rgb, line_color.rgb, on_line);
	ROUGHNESS = 0.85;
}
