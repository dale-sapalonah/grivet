// Shipping containers: a box made of `cells` containers (a whole stacked wall
// can be one box, one draw call) each gets its own paint colour, corrugated
// side walls, a frame with corner posts, cargo doors with locking bars at the
// ends, seams where boxes stack, and rust and dirt. Coordinates are the box's
// own, so containers keep their look wherever they sit.
shader_type spatial;

#include "res://levels/port/materials/port_common.gdshaderinc"

instance uniform vec3 box_size = vec3(6.1, 2.6, 2.44);
instance uniform vec3 cells = vec3(1.0, 1.0, 1.0);
instance uniform float seed = 0.0;

uniform vec4 rust_color : source_color = vec4(0.3, 0.14, 0.07, 1.0);
uniform float corrugation_pitch = 0.28;

varying vec3 local_position;
varying vec3 local_normal;

const vec3 PAINT[8] = vec3[](
	vec3(0.45, 0.12, 0.08),  // oxide red
	vec3(0.1, 0.22, 0.4),    // blue
	vec3(0.16, 0.3, 0.2),    // green
	vec3(0.5, 0.5, 0.48),    // grey
	vec3(0.62, 0.32, 0.1),   // orange
	vec3(0.6, 0.58, 0.52),   // off white
	vec3(0.32, 0.1, 0.1),    // maroon
	vec3(0.12, 0.3, 0.33)    // teal
);

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 cell_size = box_size / cells;
	vec3 q = (local_position + box_size * 0.5) / cell_size;
	vec3 id = clamp(floor(q), vec3(0.0), cells - 1.0);
	vec3 f = (q - id) * cell_size;  // metres inside this container
	bool long_x = cell_size.x >= cell_size.z;
	float length_m = long_x ? cell_size.x : cell_size.z;
	float width_m = long_x ? cell_size.z : cell_size.x;
	float along = long_x ? f.x : f.z;
	float across = long_x ? f.z : f.x;

	float pick = hash12(vec2(dot(id, vec3(1.0, 7.0, 13.0)) + seed * 31.0, seed + 0.5));
	vec3 paint = PAINT[int(pick * 7.999)];
	vec3 n = abs(local_normal);
	bool top = n.y > 0.5;
	bool end_face = long_x ? n.x > 0.5 : n.z > 0.5;
	float u = top ? along : (end_face ? across : along);
	float face_width = top ? length_m : (end_face ? width_m : length_m);
	float v = f.y;

	vec3 long_axis = long_x ? vec3(1, 0, 0) : vec3(0, 0, 1);
	vec3 short_axis = long_x ? vec3(0, 0, 1) : vec3(1, 0, 0);
	vec3 world_u = normalize((MODEL_MATRIX * vec4(end_face && !top ? short_axis : long_axis, 0.0)).xyz);
	vec3 bend = vec3(0.0);
	float frame = 0.0;
	vec3 color = paint;
	if (!top) {
		float edge_u = min(u, face_width - u);
		float edge_v = min(v, cell_size.y - v);
		frame = 1.0 - step(0.11, min(edge_u, edge_v * 1.3));
		if (end_face) {
			// Two doors with vertical locking bars.
			float bars = 1.0 - smoothstep(0.012, 0.02, grid_distance(u - face_width * 0.25 + 0.15, face_width * 0.25));
			float split = 1.0 - smoothstep(0.006, 0.012, abs(u - face_width * 0.5));
			color *= 1.0 - 0.45 * split;
			color = mix(color, vec3(0.08), bars * (1.0 - frame) * 0.7);
			bend = world_u * sin(u * TAU / 0.5) * 0.12;
		} else {
			// Trapezoidal corrugation.
			float wave = clamp(sin(u * TAU / corrugation_pitch) * 1.8, -1.0, 1.0);
			bend = world_u * cos(u * TAU / corrugation_pitch) * 0.45 * (1.0 - frame);
			color *= 0.93 + 0.07 * wave;
		}
		color *= mix(1.0, 0.7, frame);
		// Seams where containers meet.
		float seam = 1.0 - step(0.012, min(edge_u, edge_v));
		color *= 1.0 - 0.85 * seam;
		// Dirt settles low on each box; rust streaks run down from the top rail.
		color *= mix(0.65, 1.0, smoothstep(0.0, 0.9, v));
		vec2 streak_uv = vec2((u + id.x * 3.1 + id.z * 5.7 + seed) * 0.7, v * 0.05 + id.y * 0.3);
		float rust = smoothstep(0.55, 0.8, noise2(streak_uv)) * smoothstep(0.2, 2.4, v);
		rust = max(rust, smoothstep(0.62, 0.8, noise2(vec2(u, v) * 0.6 + id.xy * 0.37 + seed)) * 0.8);
		color = mix(color, rust_color.rgb, rust * 0.75);
	} else {
		// Roof panels with shallow ribs.
		bend = world_u * cos(along * TAU / 0.9) * 0.15;
		float rust = smoothstep(0.5, 0.75, noise2(vec2(along, across) * 0.5 + id.xz * 0.41 + seed));
		color = mix(color * 0.85, rust_color.rgb, rust * 0.6);
	}
	ALBEDO = color * (0.9 + 0.2 * noise2(local_position.xy * 1.7 + local_position.z));
	NORMAL = bend_normal(NORMAL, bend, VIEW_MATRIX);
	ROUGHNESS = 0.6;
	METALLIC = 0.25;
}
