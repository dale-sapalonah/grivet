class_name PmvBus
extends Node3D
## Port Moresby PMV (public motor vehicle): the white Coaster-style minibus
## with a coloured skirt band (teal, lavender, green), dark window band,
## rounded roof, bull bar, route number and orange plate. Visual only: the
## level gives it a collision box with the "vehicle" surface (thin skins:
## rifle rounds go through). Unbadged, no maker's marks (original IP only).
## Faces -Z, origin on the ground under its middle; about 7 x 2.05 x 2.6 m.

const LENGTH := 7.0
const WIDTH := 2.05


## livery: skirt band colour; route: number painted front and side;
## headlights: parked with lights on.
func build(livery: Color, route: String, plate: String, headlights: bool) -> void:
	var B := MeshBaker
	var white := Color(0.86, 0.86, 0.82)
	var trim := Color(0.12, 0.12, 0.12)
	var chrome := Color(0.5, 0.5, 0.5)
	var half := LENGTH * 0.5
	var body := MeshBaker.new()
	body.add(B.box(Vector3(WIDTH, 1.05, LENGTH)), B.at(Vector3(0, 0.88, 0)), white)  # lower body
	body.add(B.box(Vector3(WIDTH + 0.01, 0.42, LENGTH + 0.01)), B.at(Vector3(0, 0.6, 0)), livery)  # skirt band
	body.add(B.box(Vector3(WIDTH - 0.04, 0.3, LENGTH - 0.1)), B.at(Vector3(0, 2.27, 0)), white)  # roof rail
	body.add(B.cylinder(1.0, 1.0, LENGTH - 0.1, 16), B.at(Vector3(0, 2.4, 0), Vector3(90, 0, 0), Vector3(WIDTH * 0.5 - 0.02, 0.16, 1)), white)  # roof crown
	# Window pillars between the side windows.
	for i in 8:
		var z := -half + 0.95 + i * 0.78
		body.add(B.box(Vector3(WIDTH + 0.005, 0.8, 0.09)), B.at(Vector3(0, 1.8, z)), white)
	body.add(B.box(Vector3(WIDTH, 0.8, 0.25)), B.at(Vector3(0, 1.8, half - 0.13)), white)  # rear pillar
	# Front: nose, grille, headlamps, bumper, bull bar.
	body.add(B.box(Vector3(WIDTH, 0.95, 0.3)), B.at(Vector3(0, 0.85, -half - 0.1)), white)
	body.add(B.box(Vector3(WIDTH + 0.01, 0.42, 0.31)), B.at(Vector3(0, 0.6, -half - 0.1)), livery)
	body.add(B.box(Vector3(0.8, 0.2, 0.02)), B.at(Vector3(0, 0.95, -half - 0.26)), trim)  # grille
	body.add(B.box(Vector3(WIDTH + 0.06, 0.16, 0.18)), B.at(Vector3(0, 0.38, -half - 0.24)), trim)  # bumper
	for side in [-1.0, 1.0]:
		body.add(B.cylinder(0.035, 0.035, 0.8, 6), B.at(Vector3(side * 0.62, 0.65, -half - 0.42)), chrome)  # bull bar uprights
		body.add(B.box(Vector3(0.05, 0.05, 0.3)), B.at(Vector3(side * 0.62, 0.95, -half - 0.3)), chrome)
		body.add(B.box(Vector3(0.06, 0.25, 0.06)), B.at(Vector3(side * (WIDTH * 0.5 + 0.12), 1.9, -half + 0.05)), trim)  # mirror
		body.add(B.box(Vector3(0.24, 0.04, 0.04)), B.at(Vector3(side * (WIDTH * 0.5 + 0.06), 2.05, -half + 0.05)), trim)
	body.add(B.cylinder(0.035, 0.035, 1.5, 6), B.at(Vector3(0, 1.0, -half - 0.42), Vector3(0, 0, 90)), chrome)  # bull bar rails
	body.add(B.cylinder(0.035, 0.035, 1.5, 6), B.at(Vector3(0, 0.62, -half - 0.42), Vector3(0, 0, 90)), chrome)
	body.add(B.box(Vector3(0.36, 0.12, 0.02)), B.at(Vector3(0, 0.38, -half - 0.34)), Color(0.95, 0.5, 0.1))  # plate
	# Wheels and dark arches; side vents; rear bumper.
	for z in [-half + 1.15, half - 1.5]:
		for side in [-1.0, 1.0]:
			body.add(B.cylinder(0.38, 0.38, 0.26, 14), B.at(Vector3(side * (WIDTH * 0.5 - 0.1), 0.38, z), Vector3(0, 0, 90)), Color(0.06, 0.06, 0.06))
			body.add(B.cylinder(0.2, 0.2, 0.27, 8), B.at(Vector3(side * (WIDTH * 0.5 - 0.1), 0.38, z), Vector3(0, 0, 90)), chrome)
			body.add(B.box(Vector3(0.02, 0.5, 1.0)), B.at(Vector3(side * (WIDTH * 0.5 + 0.006), 0.62, z)), trim)
	for side in [-1.0, 1.0]:
		body.add(B.box(Vector3(0.02, 0.18, 0.5)), B.at(Vector3(side * (WIDTH * 0.5 + 0.006), 1.1, half - 2.6)), trim)  # engine vent
	body.add(B.box(Vector3(WIDTH + 0.04, 0.16, 0.12)), B.at(Vector3(0, 0.38, half + 0.04)), trim)
	_mesh(body, _material(Color.WHITE, 0.45, 0.15))

	# Glass: windscreen, side windows, door (kerb side, the bus's left: PNG drives on the left), rear.
	var glass := MeshBaker.new()
	glass.add(B.box(Vector3(WIDTH - 0.12, 0.85, 0.04)), B.at(Vector3(0, 1.78, -half - 0.02), Vector3(-6, 0, 0)), Color.WHITE)
	glass.add(B.box(Vector3(WIDTH + 0.002, 0.72, LENGTH - 0.5)), B.at(Vector3(0, 1.82, 0.1)), Color.WHITE)
	glass.add(B.box(Vector3(0.02, 1.7, 0.75)), B.at(Vector3(-WIDTH * 0.5 - 0.004, 1.25, -half + 1.9)), Color.WHITE)
	glass.add(B.box(Vector3(WIDTH - 0.3, 0.7, 0.02)), B.at(Vector3(0, 1.8, half + 0.002)), Color.WHITE)
	_mesh(glass, _material(Color(0.04, 0.05, 0.06), 0.08, 0.6))

	var lamps := MeshBaker.new()
	for side in [-1.0, 1.0]:
		lamps.add(B.sphere(0.09, 8), B.at(Vector3(side * 0.72, 0.95, -half - 0.24)), Color.WHITE)
		lamps.add(B.box(Vector3(0.14, 0.22, 0.02)), B.at(Vector3(side * 0.85, 0.95, half + 0.002)), Color(0.7, 0.05, 0.03))
	var lamp_material := _material(Color(1, 1, 0.9), 0.3, 0.0)
	lamp_material.vertex_color_use_as_albedo = true
	if headlights:
		lamp_material.emission_enabled = true
		lamp_material.emission = Color(1.0, 0.92, 0.75)
		lamp_material.emission_energy_multiplier = 3.0
	_mesh(lamps, lamp_material)

	var number := Color(0.75, 0.1, 0.08)
	_text(route, Vector3(0.62, 2.28, -half - 0.03), Vector3(0, 0, -1), 0.24, number)  # above the windscreen
	_text(route, Vector3(WIDTH * 0.5 + 0.01, 1.2, -half + 0.6), Vector3(1, 0, 0), 0.22, number)
	_text(route, Vector3(-WIDTH * 0.5 - 0.01, 1.2, -half + 0.6), Vector3(-1, 0, 0), 0.22, number)
	_text(plate, Vector3(0, 0.38, -half - 0.36), Vector3(0, 0, -1), 0.08, Color(0.05, 0.05, 0.05))
	_text("PMV", Vector3(-0.55, 2.28, -half - 0.03), Vector3(0, 0, -1), 0.2, Color(0.1, 0.1, 0.1))
	_text("26 PASINJA TASOL", Vector3(WIDTH * 0.5 + 0.01, 1.2, -half + 2.6), Vector3(1, 0, 0), 0.07, Color(0.1, 0.1, 0.08))


## Painted lettering facing `normal`, lit like the paint around it.
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
	label.position = at
	label.basis = Basis.looking_at(-normal)
	add_child(label)


func _mesh(baker: MeshBaker, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = baker.commit(material)
	add_child(instance)


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = color == Color.WHITE
	material.vertex_color_is_srgb = true
	material.roughness = roughness
	material.metallic = metallic
	return material
