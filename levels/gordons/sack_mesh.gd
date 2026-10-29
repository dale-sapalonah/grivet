class_name SackMesh
extends RefCounted
## Filled sacks as soft rounded boxes (superquadrics): flat-ish faces that
## bulge and round off at the seams, like a stuffed woven bag, where a box
## reads as a brick and a sphere as a ball. Built once and instanced
## (MultiMesh), so a few thousand cost little.


## A sack lying on its side, 1 m long (Z), 0.62 wide (X), 0.32 tall (Y),
## origin at its middle. `roundness` 0..1: 0 squarer, 1 rounder.
static func lying(roundness: float = 0.45) -> ArrayMesh:
	return _superquadric(Vector3(0.31, 0.16, 0.5), lerpf(0.25, 0.9, roundness), lerpf(0.35, 0.9, roundness), 8, 5, true)


## A sack standing up, tied at the neck: 0.44 wide, 0.62 tall, origin at its foot.
static func standing() -> ArrayMesh:
	var body := _superquadric(Vector3(0.22, 0.26, 0.19), 0.55, 0.6, 8, 5, false)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.26, 0)))
	# The gathered neck and the knot above it.
	var neck := CylinderMesh.new()
	neck.top_radius = 0.035
	neck.bottom_radius = 0.09
	neck.height = 0.1
	neck.radial_segments = 6
	neck.rings = 1
	tool.append_from(neck, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.56, 0)))
	var knot := SphereMesh.new()
	knot.radius = 0.045
	knot.height = 0.07
	knot.radial_segments = 6
	knot.rings = 3
	tool.append_from(knot, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0.62, 0)))
	tool.generate_normals()
	return tool.commit()


## Superquadric surface: x = a·c(v)^e1·c(u)^e2, y = b·s(v)^e1, z = c·c(v)^e1·s(u)^e2,
## with c/s the signed powers of cos/sin. Exponents below 1 square it off.
## `sag` dips the top a little, as a filled sack settles.
static func _superquadric(half: Vector3, e_vertical: float, e_around: float, around: int, rings: int, sag: bool) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := []
	for r in rings + 1:
		var v := lerpf(-PI * 0.5, PI * 0.5, float(r) / rings)
		var row := []
		for a in around + 1:
			var u := lerpf(-PI, PI, float(a) / around)
			var cv := _spow(cos(v), e_vertical)
			var p := Vector3(half.x * cv * _spow(cos(u), e_around), half.y * _spow(sin(v), e_vertical), half.z * cv * _spow(sin(u), e_around))
			if sag and p.y > 0.0:
				p.y *= 1.0 - 0.25 * (1.0 - absf(p.x) / half.x) * (1.0 - absf(p.z) / half.z)
			row.append(p)
		points.append(row)
	for r in rings:
		for a in around:
			var p00: Vector3 = points[r][a]
			var p10: Vector3 = points[r + 1][a]
			var p01: Vector3 = points[r][a + 1]
			var p11: Vector3 = points[r + 1][a + 1]
			for p in [p00, p10, p11, p00, p11, p01]:
				tool.add_vertex(p)
	tool.generate_normals()
	return tool.commit()


static func _spow(value: float, exponent: float) -> float:
	return signf(value) * pow(absf(value), exponent)
