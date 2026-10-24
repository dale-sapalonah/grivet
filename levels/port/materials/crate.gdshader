// Wooden shipping crate: horizontal boards with dark gaps inside a frame of
// edge boards, grain, and a little weathering. In the box's own coordinates.
shader_type spatial;

#include "res://levels/port/materials/port_common.gdshaderinc"

instance uniform vec3 box_size = vec3(1.2, 1.2, 1.2);
instance uniform float seed = 0.0;

uniform vec4 wood : source_color = vec4(0.5, 0.37, 0.23, 1.0);
uniform float board_width = 0.15;
uniform float frame_width = 0.09;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 p = local_position + box_size * 0.5;
	vec3 n = abs(local_normal);
	vec2 uv;
	vec2 size;
	if (n.y > 0.5) {
		uv = p.xz; size = box_size.xz;
	} else if (n.x > 0.5) {
		uv = p.zy; size = box_size.zy;
	} else {
		uv = p.xy; size = box_size.xy;
	}
	vec2 edge = min(uv, size - uv);
	bool frame = min(edge.x, edge.y) < frame_width;
	float board = floor(uv.y / board_width);
	float grain_axis = frame && edge.x < edge.y ? uv.y : uv.x;
	float across = frame && edge.x < edge.y ? uv.x : uv.y;
	float grain = noise2(vec2(grain_axis * 0.25, across * 6.0) + board * 0.37 + seed);
	float tone = 0.8 + 0.35 * hash12(vec2(board, seed + (frame ? 7.0 : 0.0)));
	vec3 color = wood.rgb * tone * (0.8 + 0.35 * grain);
	if (frame) {
		color *= 1.08;
	} else {
		float gap = 1.0 - smoothstep(0.004, 0.008, grid_distance(uv.y, board_width));
		color *= 1.0 - 0.75 * gap;
	}
	color *= 1.0 - 0.3 * smoothstep(0.6, 0.85, noise2(uv * 0.8 + seed));
	ALBEDO = color;
	ROUGHNESS = 0.85;
}
