class_name KamfotTaxi
extends Node3D
## Port Moresby taxi in the town's blue livery: a boxy sedan with a yellow
## roof sign, yellow door decals (a bird of paradise and "KAMFOT TAXI") and
## yellow "T" plates. An original lookalike of the city's taxi fleets (no
## real company name or marks). Visual only: the level gives it a collision
## box with the "vehicle" surface. Faces -Z, origin on the ground under its
## middle; about 4.4 x 1.7 x 1.5 m.

const LENGTH := 4.4
const WIDTH := 1.7
const BLUE := Color(0.1, 0.27, 0.72)
const YELLOW := Color(0.95, 0.78, 0.1)


func build(plate: String) -> void:
	var B := MeshBaker
	var half := LENGTH * 0.5
	var trim := Color(0.1, 0.1, 0.11)
	var chrome := Color(0.55, 0.56, 0.58)
	var body := MeshBaker.new()
	body.add(B.box(Vector3(WIDTH, 0.5, LENGTH)), B.at(Vector3(0, 0.6, 0)), BLUE)  # lower body
	body.add(B.box(Vector3(WIDTH - 0.04, 0.1, 1.2)), B.at(Vector3(0, 0.88, -half + 0.6)), BLUE)  # bonnet
	body.add(B.box(Vector3(WIDTH - 0.04, 0.1, 0.85)), B.at(Vector3(0, 0.88, half - 0.42)), BLUE)  # boot lid
	body.add(B.box(Vector3(1.56, 0.05, 1.15)), B.at(Vector3(0, 1.43, 0.375)), BLUE)  # roof
	# Pillars along the window edges: windscreen (A), doors (B), rear window (C).
	for edge in [[Vector2(-0.75, 0.86), Vector2(-0.2, 1.42)], [Vector2(0.32, 0.86), Vector2(0.32, 1.42)],
			[Vector2(1.25, 0.86), Vector2(0.95, 1.42)]]:
		for side in [-1.0, 1.0]:
			var from := Vector3(side * 0.77, edge[0].y, edge[0].x)
			var to := Vector3(side * 0.77, edge[1].y, edge[1].x)
			body.add(B.box(Vector3(0.05, from.distance_to(to), 0.07)), Transform3D(_along(to - from), (from + to) * 0.5), BLUE)
	body.add(B.box(Vector3(WIDTH + 0.02, 0.16, 0.12)), B.at(Vector3(0, 0.42, -half - 0.03)), BLUE)  # front bumper
	body.add(B.box(Vector3(WIDTH + 0.02, 0.16, 0.12)), B.at(Vector3(0, 0.42, half + 0.03)), BLUE)  # rear bumper
	body.add(B.box(Vector3(0.9, 0.2, 0.03)), B.at(Vector3(0, 0.66, -half - 0.01)), chrome)  # grille
	for side in [-1.0, 1.0]:
		body.add(B.box(Vector3(0.3, 0.16, 0.03)), B.at(Vector3(side * 0.62, 0.68, -half - 0.01)), Color(0.85, 0.85, 0.8))  # headlamps
		body.add(B.box(Vector3(0.3, 0.16, 0.03)), B.at(Vector3(side * 0.6, 0.7, half + 0.01)), Color(0.65, 0.08, 0.05))  # tail lamps
		body.add(B.box(Vector3(0.1, 0.08, 0.14)), B.at(Vector3(side * 0.92, 1.0, -0.62)), BLUE)  # mirrors
		for z in [-half + 0.8, half - 0.8]:
			body.add(B.cylinder(0.31, 0.31, 0.2, 14), B.at(Vector3(side * (WIDTH * 0.5 - 0.08), 0.31, z), Vector3(0, 0, 90)), Color(0.06, 0.06, 0.06))
			body.add(B.cylinder(0.17, 0.17, 0.21, 10), B.at(Vector3(side * (WIDTH * 0.5 - 0.08), 0.31, z), Vector3(0, 0, 90)), chrome)
		body.add(B.box(Vector3(0.012, 0.42, 0.4)), B.at(Vector3(side * (WIDTH * 0.5 + 0.004), 0.62, -0.3)), YELLOW)  # door decal
	body.add(B.box(Vector3(0.46, 0.15, 0.22)), B.at(Vector3(0, 1.53, 0.2)), YELLOW)  # roof sign
	for z in [-half - 0.07, half + 0.07]:
		body.add(B.box(Vector3(0.36, 0.12, 0.01)), B.at(Vector3(0, 0.42, z)), YELLOW)  # plates
	_mesh(body, _material(Color.WHITE, 0.35, 0.25, true))

	# Cabin glass: windscreen raked forward, rear window back.
	var glass := MeshBaker.new()
	glass.add(B.prism(PackedVector2Array([Vector2(-1.25, 0.86), Vector2(0.75, 0.86), Vector2(0.2, 1.42), Vector2(-0.95, 1.42)]), 1.52),
			Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO), Color.WHITE)
	_mesh(glass, _material(Color(0.05, 0.07, 0.09), 0.06, 0.6, false))

	# Lettering and the decal's bird.
	var sign_blue := Color(0.08, 0.2, 0.6)
	_text("TAXI", Vector3(0, 1.53, 0.2 - 0.111), Vector3(0, 0, -1), 0.1, sign_blue)
	_text("TAXI", Vector3(0, 1.53, 0.2 + 0.111), Vector3(0, 0, 1), 0.1, sign_blue)
	_text(plate, Vector3(0, 0.42, -half - 0.076), Vector3(0, 0, -1), 0.075, Color(0.05, 0.05, 0.05))
	_text(plate, Vector3(0, 0.42, half + 0.076), Vector3(0, 0, 1), 0.075, Color(0.05, 0.05, 0.05))
	for side in [-1.0, 1.0]:
		var normal := Vector3(float(side), 0, 0)
		var face: float = side * (WIDTH * 0.5 + 0.012)
		_text("KAMFOT", Vector3(face, 0.66, -0.3), normal, 0.07, Color(0.7, 0.08, 0.06))
		_text("TAXI", Vector3(face, 0.56, -0.3), normal, 0.1, Color(0.7, 0.08, 0.06))
		_text("KOLIM MI 180 7777", Vector3(face, 0.46, -0.3), normal, 0.03, Color(0.05, 0.05, 0.05))
		_bird(Vector3(face, 0.74, -0.3), side)


## A small bird-of-paradise silhouette for the door decal: body, head and the
## long trailing plumes.
func _bird(at: Vector3, side: float) -> void:
	var bird := MeshBaker.new()
	var black := Color(0.05, 0.05, 0.05)
	var flat := Vector3(0.6, 1, 1)  # thin against the door
	bird.add(MeshBaker.sphere(0.025, 8), MeshBaker.at(at + Vector3(0, 0, 0.04), Vector3.ZERO, flat), black)
	bird.add(MeshBaker.sphere(0.012, 6), MeshBaker.at(at + Vector3(0, 0.022, 0.07), Vector3.ZERO, flat), black)
	for i in 3:
		bird.add(MeshBaker.box(Vector3(0.004, 0.006, 0.09)), MeshBaker.at(at + Vector3(0, -0.012 - i * 0.012, -0.02), Vector3(-20.0 - i * 15.0, 0, 0)), black)
	_mesh(bird, _material(Color.WHITE, 0.6, 0.0, true))


## A basis whose +Y runs along `axis`.
static func _along(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()


func _text(text: String, at: Vector3, normal: Vector3, height: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.outline_size = 0
	label.pixel_size = height / 64.0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visibility_range_end = 30.0  # each label is a draw call
	label.position = at
	label.basis = Basis.looking_at(-normal)
	add_child(label)


func _mesh(baker: MeshBaker, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = baker.commit(material)
	add_child(instance)


func _material(color: Color, roughness: float, metallic: float, vertex_colors: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_colors
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.metallic = metallic
	return material
