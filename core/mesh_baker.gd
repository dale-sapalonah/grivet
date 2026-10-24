class_name MeshBaker
extends RefCounted
## Merges many primitive meshes, each with its own transform and colour, into
## one ArrayMesh surface with vertex colours: a whole body part or prop is a
## single draw call (cheap on integrated GPUs). Shaders read COLOR.rgb as the
## piece's sRGB colour and COLOR.a as a per-piece flag (e.g. 1 = camo cloth).
## Avoid negative scales in `at`: they flip triangle winding.

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func add(mesh: Mesh, at: Transform3D, color: Color) -> void:
	var arrays := (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := _vertices.size()
	var normal_basis := at.basis.inverse().transposed()
	for i in vertices.size():
		_vertices.append(at * vertices[i])
		_normals.append((normal_basis * normals[i]).normalized())
		_colors.append(color)
	for index in indices:
		_indices.append(base + index)


func is_empty() -> bool:
	return _vertices.is_empty()


func commit(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


# --- Primitive shortcuts (sizes in metres) ---------------------------------------

static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


## Cylinder along Y, tapering from `top` radius to `bottom` radius.
static func cylinder(top: float, bottom: float, height: float, segments: int = 12) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	return mesh


static func sphere(radius: float, segments: int = 12, hemisphere: bool = false) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius if hemisphere else radius * 2.0
	mesh.is_hemisphere = hemisphere
	mesh.radial_segments = segments
	mesh.rings = maxi(4, segments / 2)
	return mesh


static func capsule(radius: float, height: float, segments: int = 10) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 4
	return mesh


static func torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 6
	return mesh


## A prism: `profile` (a convex or simple polygon in X/Y, counter-clockwise)
## extruded `length` along Z, centred. Flat-shaded sides, capped ends.
static func prism(profile: PackedVector2Array, length: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half := length * 0.5
	var count := profile.size()
	for i in count:
		var a := profile[i]
		var b := profile[(i + 1) % count]
		var edge := b - a
		var normal := Vector3(edge.y, -edge.x, 0.0).normalized()
		var base := vertices.size()
		for corner in [Vector3(a.x, a.y, half), Vector3(b.x, b.y, half), Vector3(b.x, b.y, -half), Vector3(a.x, a.y, -half)]:
			vertices.append(corner)
			normals.append(normal)
		indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var triangles := Geometry2D.triangulate_polygon(profile)
	for z in [half, -half]:
		var base := vertices.size()
		for point in profile:
			vertices.append(Vector3(point.x, point.y, z))
			normals.append(Vector3(0, 0, signf(z)))
		for t in range(0, triangles.size(), 3):
			if z > 0.0:
				indices.append_array([base + triangles[t], base + triangles[t + 2], base + triangles[t + 1]])
			else:
				indices.append_array([base + triangles[t], base + triangles[t + 1], base + triangles[t + 2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Transform helper: position, optional rotation (degrees), optional scale.
static func at(position: Vector3, rotation_degrees := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	var basis := Basis.from_euler(rotation_degrees * (PI / 180.0)).scaled(scale)
	return Transform3D(basis, position)
