class_name MarketProduce
extends Node3D
## The market's produce, laid out on every "stall_row" table the way Gordons
## sells it: watermelons in rows and stacked, banana hands, broccoli, heaps of
## capsicum and tomato on banana leaves, pyramids of kaukau (sweet potato),
## coconuts, aibika and buai bundles, with price cards, and labelled sacks
## (KAUKAU, RIGO BANANA...) under the tables. Each heap or big fruit is a
## "unit" with its own sphere on the PRODUCE physics layer (bullets only):
## shot, or caught in a blast, it bursts: it vanishes, a spray of coloured
## chunks flies out and it splats. Everything is drawn with MultiMesh per kind
## and area (a few draw calls), and laid out fresh with reset().

## Skin colour of each kind, for the distant lumps.
const SKINS := {"watermelon": Color(0.16, 0.36, 0.14), "banana": Color(0.95, 0.84, 0.25), "broccoli": Color(0.2, 0.44, 0.16),
		"capsicum": Color(0.85, 0.2, 0.12), "kaukau": Color(0.6, 0.26, 0.3), "tomato": Color(0.9, 0.16, 0.1),
		"coconut": Color(0.42, 0.5, 0.2), "aibika": Color(0.22, 0.5, 0.17), "buai": Color(0.4, 0.58, 0.18)}
## kind -> [collision radius of one unit, burst colour (the flesh)].
const KINDS := {
	"watermelon": [0.22, Color(0.86, 0.16, 0.2)],
	"banana": [0.17, Color(0.96, 0.92, 0.62)],
	"broccoli": [0.1, Color(0.25, 0.5, 0.18)],
	"capsicum": [0.14, Color(0.85, 0.2, 0.12)],
	"kaukau": [0.17, Color(0.95, 0.62, 0.25)],
	"tomato": [0.12, Color(0.9, 0.18, 0.12)],
	"coconut": [0.12, Color(0.95, 0.95, 0.9)],
	"aibika": [0.12, Color(0.3, 0.55, 0.2)],
	"buai": [0.1, Color(0.55, 0.65, 0.3)],
}
## What a table sells, with weights.
const DISPLAYS := [["watermelon", 3], ["banana", 4], ["broccoli", 2], ["capsicum", 3], ["kaukau", 3], ["tomato", 3],
		["coconut", 2], ["aibika", 2], ["buai", 2]]
const SACK_LABELS := ["KAUKAU", "RIGO BANANA", "KUMU", "BUAI", "KOKONAS", "KAPSIKUM", "AIBIKA", "TAMATO", "MAU BANANA",
		"KAUKAU - GOROKA", "PINAT", "KABIS"]
## Areas (cells this wide, m) that each get their own MultiMesh per kind, so
## what is off screen is culled.
const AREA := 20.0
const TABLE_TOP := 0.85
const CHUNKS := 320

## Produce is small: past this (m) it isn't drawn at all.
@export var draw_distance := 35.0
## Beyond this (m) each heap or fruit is one simple lump in its colours (the
## pieces cost 1.5-2.5 ms with a whole floor of stalls in view).
@export var detail_distance := 12.0
@export var label_distance := 14.0
@export var chunk_lifetime := 1.1

var _meshes := {}  # kind -> Mesh
var _material: StandardMaterial3D
var _units: Array[Dictionary] = []  # {kind, center, radius, items: [[multimesh, index, Transform3D]], shape, alive}
var _multimeshes: Array[MultiMesh] = []
var _chunks: MultiMesh
var _chunk_state: Array[Dictionary] = []  # {velocity, life, position, size}
var _next_chunk := 0
var _rng := RandomNumberGenerator.new()


## Lays produce on every "stall_row" body under `level`.
func build(level: Node) -> void:
	add_to_group("produce")
	_rng.seed = 1960
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.vertex_color_is_srgb = true
	_material.roughness = 0.6
	for kind: String in KINDS:
		_meshes[kind] = _mesh_for(kind)
	var pending := {}  # "kind:area" -> [kind, Array of [Transform3D, Color, unit]]
	var static_baker := MeshBaker.new()
	for node: Node in level.get_tree().get_nodes_in_group("stall_row"):
		var row := node as Node3D
		if row == null or not level.is_ancestor_of(row):
			continue
		var size: Vector3 = row.get_meta("size")
		var base := row.global_position - Vector3.UP * size.y * 0.5
		var body := ProduceBody.new()
		body.produce = self
		body.collision_layer = PhysicsLayers.PRODUCE
		body.collision_mask = 0
		body.set_meta("surface", "produce")
		add_child(body)
		for t in 3:
			var top := base + Vector3(-size.x * 0.5 + 1.2 + t * 2.4, TABLE_TOP, 0.0)
			_lay_table(top, size.z, body, pending, static_baker)
			if _rng.randf() < 0.45:
				var side := 1.0 if _rng.randf() < 0.5 else -1.0  # which aisle it faces
				_labelled_sack(base + Vector3(-size.x * 0.5 + 1.2 + t * 2.4 + _rng.randf_range(-0.6, 0.6), 0.0,
						(size.z * 0.5 - 0.25) * side), side, static_baker)
	# MultiMeshes, one per kind per area.
	for key: String in pending:
		var entry: Array = pending[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = _meshes[entry[0]]
		var instances: Array = entry[1]
		multimesh.instance_count = instances.size()
		for i in instances.size():
			var instance: Array = instances[i]
			multimesh.set_instance_transform(i, instance[0])
			multimesh.set_instance_color(i, instance[1])
			(instance[2] as Dictionary).items.append([multimesh, i, instance[0]])
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = multimesh
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drawn.visibility_range_end = detail_distance
		drawn.visibility_range_end_margin = 2.0
		drawn.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		drawn.material_override = _material
		drawn.name = "Produce_" + key.replace(":", "_")
		add_child(drawn)
		_multimeshes.append(multimesh)
	_build_far_lumps()
	var mats := MeshInstance3D.new()
	mats.mesh = static_baker.commit(_material)
	mats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mats.visibility_range_end = draw_distance
	mats.name = "ProduceMatsAndSacks"
	add_child(mats)
	_build_chunks()


## Everything back on the tables (a new stage).
func reset() -> void:
	for unit in _units:
		if unit.alive:
			continue
		unit.alive = true
		(unit.shape as CollisionShape3D).set_deferred("disabled", false)
		for item: Array in unit.items + [unit.far]:
			(item[0] as MultiMesh).set_instance_transform(item[1], item[2])


## A round hit shape `shape` on `body`: burst that unit.
func hit(body: StaticBody3D, shape: int, direction: Vector3) -> void:
	if shape < 0:
		return
	var owner_id := body.shape_find_owner(shape)
	var collision := body.shape_owner_get_owner(owner_id) as CollisionShape3D
	if collision != null and collision.has_meta("unit"):
		burst(int(collision.get_meta("unit")), direction)


## A blast at `center`: everything within `radius` bursts, flung outward.
func blast(center: Vector3, radius: float) -> void:
	for i in _units.size():
		var unit: Dictionary = _units[i]
		if unit.alive and (unit.center as Vector3).distance_to(center) < radius:
			burst(i, ((unit.center as Vector3) - center).normalized())


func burst(index: int, direction: Vector3) -> void:
	var unit: Dictionary = _units[index]
	if not unit.alive:
		return
	unit.alive = false
	(unit.shape as CollisionShape3D).set_deferred("disabled", true)
	var gone := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -100, 0))
	for item: Array in unit.items + [unit.far]:
		(item[0] as MultiMesh).set_instance_transform(item[1], gone)
	var flesh: Color = KINDS[unit.kind][1]
	var count := 8 + int(unit.radius * 60.0)
	for k in count:
		var spray := (direction * 0.6 + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.3, 1.4), _rng.randf_range(-1, 1))).normalized()
		_spawn_chunk(unit.center, spray * _rng.randf_range(1.5, 4.5), flesh.lerp(Color(1, 1, 1), _rng.randf() * 0.15),
				_rng.randf_range(0.02, 0.05) * (1.5 if unit.radius > 0.15 else 1.0))
	Soundscape.play_at("splat:%d" % (_rng.randi() % 3), unit.center, -4.0 + unit.radius * 10.0, 4.0)


## Units still on the tables (for probes).
func intact() -> int:
	var count := 0
	for unit in _units:
		count += 1 if unit.alive else 0
	return count


func unit_count() -> int:
	return _units.size()


func unit_center(index: int) -> Vector3:
	return _units[index].center


func _process(delta: float) -> void:
	if _chunks == null:
		return
	var gravity := Vector3.DOWN * 9.81
	for i in _chunk_state.size():
		var chunk: Dictionary = _chunk_state[i]
		if chunk.life <= 0.0:
			continue
		chunk.life -= delta
		chunk.velocity += gravity * delta
		chunk.position += chunk.velocity * delta
		var scale: float = chunk.size * clampf(chunk.life / (chunk_lifetime * 0.4), 0.0, 1.0)
		if chunk.life <= 0.0:
			scale = 0.0001
		_chunks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * maxf(scale, 0.0001)), chunk.position))


# --- Layout -------------------------------------------------------------------------

## One table: one kind of produce, laid out the way it's sold.
func _lay_table(top: Vector3, depth: float, body: StaticBody3D, pending: Dictionary, mats: MeshBaker) -> void:
	var kind := _pick_display()
	var B := MeshBaker
	match kind:
		"watermelon":
			for i in 5:
				var unit := _unit(kind, top + Vector3(-0.9 + i * 0.45, 0.15, 0.0), body)
				_put(pending, unit, kind, Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.3, 0.3)), unit.center), Color.WHITE)
			for i in 2:
				var unit := _unit(kind, top + Vector3(-0.45 + i * 0.6, 0.42, 0.0), body)
				_put(pending, unit, kind, Transform3D(Basis(Vector3.UP, PI * 0.5 + _rng.randf_range(-0.2, 0.2)), unit.center), Color.WHITE)
		"banana", "coconut", "broccoli", "aibika":
			var columns := {"banana": 4, "coconut": 5, "broccoli": 6, "aibika": 5}[kind] as int
			var rows := 1 if kind == "banana" else 2
			for r in rows:
				for c in columns:
					var at := top + Vector3(-1.0 + (c + 0.5) * 2.0 / columns, 0.0, (r - (rows - 1) * 0.5) * depth * 0.42)
					var unit := _unit(kind, at + Vector3.UP * 0.07, body)
					var tint := Color(1, 1, 1).lerp(Color(0.7, 0.85, 0.4), _rng.randf() * 0.4) if kind == "banana" else Color.WHITE
					_put(pending, unit, kind, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), at), tint)
		"capsicum", "tomato", "kaukau", "buai":
			# Heaps on banana-leaf mats: three or four little pyramids per table.
			var heaps := 3 if kind == "kaukau" else 4
			var colours := [Color(0.9, 0.15, 0.1), Color(0.95, 0.75, 0.1), Color(0.25, 0.55, 0.15)]
			for h in heaps:
				var center := top + Vector3(-1.0 + (h + 0.5) * 2.0 / heaps, 0.0, _rng.randf_range(-0.12, 0.12))
				mats.add(B.box(Vector3(0.42, 0.006, 0.5)), B.at(center + Vector3.UP * 0.003, Vector3(0, _rng.randf_range(-20, 20), 0)), Color(0.22, 0.45, 0.16))
				var unit := _unit(kind, center + Vector3.UP * 0.08, body)
				var tint: Color = colours[h % 3] if kind == "capsicum" else Color.WHITE
				var piece: float = {"capsicum": 0.1, "tomato": 0.085, "kaukau": 0.13, "buai": 0.07}[kind]
				for layer in 2:  # three round the bottom, one on top: reads as a heap
					var ring := 3 - layer * 2
					for k in ring:
						var angle := TAU * k / maxf(ring, 1) + layer * 0.5
						var spread := piece * 0.6 * (2 - layer) * 0.8
						var at := center + Vector3(cos(angle) * spread, 0.02 + layer * piece * 0.7, sin(angle) * spread)
						_put(pending, unit, kind, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).rotated(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3)), at), tint)
	# A price card on most tables.
	if _rng.randf() < 0.7:
		mats.add(B.box(Vector3(0.2, 0.12, 0.01)), B.at(top + Vector3(_rng.randf_range(-0.9, 0.9), 0.07, depth * 0.48), Vector3(-20, 0, 0)), Color(0.96, 0.96, 0.92))


## A sack standing under a table edge, its label facing the aisle.
func _labelled_sack(at: Vector3, facing: float, baker: MeshBaker) -> void:
	var B := MeshBaker
	baker.add(B.sphere(1.0, 6), B.at(at + Vector3(0, 0.3, 0), Vector3(0, _rng.randf_range(-10, 10), 0), Vector3(0.24, 0.3, 0.2)),
			Color(0.9, 0.89, 0.84) if _rng.randf() < 0.7 else Color(0.62, 0.48, 0.3))
	var label := Label3D.new()
	label.text = SACK_LABELS[_rng.randi() % SACK_LABELS.size()]
	label.font_size = 64
	label.pixel_size = 0.0018
	label.outline_size = 0
	label.modulate = Color(0.12, 0.3, 0.6) if _rng.randf() < 0.5 else Color(0.7, 0.1, 0.08)
	label.shaded = true
	label.double_sided = false
	label.visibility_range_end = label_distance
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	label.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0, -facing)), at + Vector3(0, 0.33, 0.2 * facing + 0.01 * facing))


func _pick_display() -> String:
	var total := 0
	for entry: Array in DISPLAYS:
		total += int(entry[1])
	var roll := _rng.randi() % total
	for entry: Array in DISPLAYS:
		roll -= int(entry[1])
		if roll < 0:
			return entry[0]
	return "banana"


func _unit(kind: String, center: Vector3, body: StaticBody3D) -> Dictionary:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = KINDS[kind][0]
	shape.shape = sphere
	shape.set_meta("unit", _units.size())
	body.add_child(shape)
	shape.global_position = center
	var unit := {"kind": kind, "center": center, "radius": float(KINDS[kind][0]), "items": [], "far": [], "shape": shape, "alive": true}
	_units.append(unit)
	return unit


func _put(pending: Dictionary, unit: Dictionary, kind: String, at: Transform3D, tint: Color) -> void:
	var key := "%s:%d_%d_%d" % [kind, floori(at.origin.x / AREA), floori(at.origin.z / AREA), 1 if at.origin.y > 3.0 else 0]
	if not pending.has(key):
		pending[key] = [kind, []]
	(pending[key][1] as Array).append([at, tint, unit])


# --- Meshes (vertex colours; instances tint them) ------------------------------------------

## Low-poly on purpose: there are well over a thousand of these.
func _mesh_for(kind: String) -> Mesh:
	var B := MeshBaker
	var mesh := MeshBaker.new()
	match kind:
		"watermelon":
			mesh.add(B.sphere(1.0, 7), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(0.17, 0.15, 0.24)), Color(0.14, 0.34, 0.13))
			for k in 2:  # pale stripes running end to end
				mesh.add(B.sphere(1.0, 6), Transform3D(Basis(Vector3.BACK, PI * 0.25 + k * PI * 0.5).scaled(Vector3(0.02, 0.153, 0.243)), Vector3.ZERO),
						Color(0.5, 0.66, 0.3))
		"banana":
			mesh.add(B.cylinder(0.02, 0.025, 0.12, 4), B.at(Vector3(0, 0.02, 0), Vector3(0, 0, 70)), Color(0.4, 0.45, 0.22))
			for f in 5:  # fingers curving up from the crown
				var angle := deg_to_rad(-50.0 + f * 25.0)
				var dir := Vector3(cos(angle), 0.45, sin(angle)).normalized()
				mesh.add(B.capsule(0.022, 0.19, 4), Transform3D(_along(dir), Vector3(cos(angle), 0.0, sin(angle)) * 0.04 + dir * 0.09),
						Color(1.0, 0.88, 0.25))
		"broccoli":
			mesh.add(B.cylinder(0.025, 0.032, 0.08, 4), B.at(Vector3(0, 0.0, 0)), Color(0.62, 0.78, 0.45))
			for k in 4:
				var angle := TAU * k / 4.0
				mesh.add(B.sphere(0.05, 4), B.at(Vector3(cos(angle) * 0.045, 0.07, sin(angle) * 0.045)), Color(0.18, 0.42, 0.15))
			mesh.add(B.sphere(0.058, 4), B.at(Vector3(0, 0.1, 0)), Color(0.2, 0.45, 0.16))
		"capsicum":
			mesh.add(B.sphere(0.05, 5), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.2, 1)), Color.WHITE)
			mesh.add(B.sphere(0.035, 4), B.at(Vector3(0.02, -0.02, 0.0)), Color.WHITE)  # a lobe
			mesh.add(B.cylinder(0.007, 0.009, 0.035, 4), B.at(Vector3(0, 0.065, 0)), Color(0.3, 0.5, 0.15))
		"kaukau":
			mesh.add(B.sphere(1.0, 5), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(0.06, 0.05, 0.13)), Color(0.62, 0.26, 0.32))
		"tomato":
			mesh.add(B.sphere(0.043, 5), B.at(Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.85, 1)), Color(0.95, 0.15, 0.1))
		"coconut":
			mesh.add(B.sphere(0.1, 6), B.at(Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 0.9, 1.1)), Color(0.42, 0.5, 0.2))
		"aibika":
			for k in 4:  # leaves fanned out, a tie round the stems
				mesh.add(B.box(Vector3(0.1, 0.006, 0.22)), B.at(Vector3(0, 0.01 + k * 0.006, 0.06), Vector3(0, -30 + k * 20, 0)), Color(0.22, 0.5, 0.17))
			mesh.add(B.cylinder(0.016, 0.016, 0.03, 4), B.at(Vector3(0, 0.015, -0.03), Vector3(90, 0, 0)), Color(0.6, 0.5, 0.28))
		"buai":
			mesh.add(B.cylinder(0.006, 0.008, 0.12, 3), B.at(Vector3(0, 0.03, 0), Vector3(0, 0, 60)), Color(0.45, 0.4, 0.22))
			for k in 5:
				mesh.add(B.sphere(0.026, 4), B.at(Vector3(_rng.randf_range(-0.04, 0.04), _rng.randf_range(0.0, 0.04), _rng.randf_range(-0.04, 0.04))),
						Color(0.4, 0.58, 0.18))
	return mesh.commit(null)


func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


## Distant level of detail: one squashed sphere per unit, in its skin colour
## (capsicum heaps keep their own colour), drawn from detail_distance out.
func _build_far_lumps() -> void:
	var lump := SphereMesh.new()
	lump.radial_segments = 6
	lump.rings = 3
	var areas := {}  # area key -> Array of unit indices
	for i in _units.size():
		var center: Vector3 = _units[i].center
		var key := "%d_%d_%d" % [floori(center.x / AREA), floori(center.z / AREA), 1 if center.y > 3.0 else 0]
		if not areas.has(key):
			areas[key] = []
		(areas[key] as Array).append(i)
	for key: String in areas:
		var members: Array = areas[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = lump
		multimesh.instance_count = members.size()
		for slot in members.size():
			var unit: Dictionary = _units[members[slot]]
			var r: float = unit.radius * 0.8
			var at := Transform3D(Basis.from_scale(Vector3(r * 2.0, r * 1.2, r * 2.0)), (unit.center as Vector3) - Vector3.UP * r * 0.3)
			multimesh.set_instance_transform(slot, at)
			var tint: Color = SKINS[unit.kind]
			if unit.kind == "capsicum" and not (unit.items as Array).is_empty():
				tint = ((unit.items[0][0] as MultiMesh).get_instance_color(unit.items[0][1]))
			multimesh.set_instance_color(slot, tint)
			unit.far = [multimesh, slot, at]
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = multimesh
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drawn.visibility_range_begin = detail_distance
		drawn.visibility_range_end = draw_distance
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.7
		drawn.material_override = material
		drawn.name = "ProduceFar_" + key
		add_child(drawn)


# --- Burst chunks ---------------------------------------------------------------------

func _build_chunks() -> void:
	_chunks = MultiMesh.new()
	_chunks.transform_format = MultiMesh.TRANSFORM_3D
	_chunks.use_colors = true
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	_chunks.mesh = cube
	_chunks.instance_count = CHUNKS
	for i in CHUNKS:
		_chunks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3(0, -100, 0)))
		_chunk_state.append({"velocity": Vector3.ZERO, "life": 0.0, "position": Vector3.ZERO, "size": 0.0})
	var drawn := MultiMeshInstance3D.new()
	drawn.multimesh = _chunks
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.4
	drawn.material_override = material
	drawn.name = "ProduceChunks"
	drawn.custom_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 60, 400))  # chunks fly anywhere
	add_child(drawn)


func _spawn_chunk(at: Vector3, velocity: Vector3, color: Color, size: float) -> void:
	var i := _next_chunk
	_next_chunk = (_next_chunk + 1) % CHUNKS
	_chunk_state[i] = {"velocity": velocity, "life": chunk_lifetime * _rng.randf_range(0.7, 1.2), "position": at, "size": size}
	_chunks.set_instance_color(i, color)


## The table's produce body: Ballistics calls apply_damage on it.
class ProduceBody extends StaticBody3D:
	var produce: MarketProduce

	func apply_damage(hit: Dictionary) -> void:
		produce.hit(self, int(hit.get("shape", -1)), hit.get("direction", Vector3.FORWARD))
