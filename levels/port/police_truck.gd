class_name PoliceTruck
extends Node3D
## The police 4x4 the player arrives and leaves in (built in Blender,
## assets/models/police_landcruiser.glb; this adds the light bar, lettering and
## collision), after the ten-seat
## troop carriers PNG's police drive (rugged roads): a long boxy navy body
## with a tall roof, a short bonnet, black fender flares and side steps, big
## off-road tyres, a heavy black bull bar with round spotlights, a snorkel up
## the right windscreen pillar, a white-and-blue checker band down the sides,
## "POLICE" on the doors and bonnet, a plain round door emblem and a red/blue
## light bar that flashes (emissive, plus one light shown only while
## flashing). No maker's badge or real crest. Faces -Z, origin on the ground
## under its middle; about 5.3 x 2.0 x 2.3 m. Carries its own collision box
## (WORLD, "vehicle" surface).

const MODEL := preload("res://assets/models/police_landcruiser.glb")
const LENGTH := 5.2
const WIDTH := 1.9
const CHECK_WHITE := Color(0.95, 0.96, 0.97)
## Where the bonnet ends and the tall body begins (z), and their tops (y).
const COWL_Z := -1.05
const BONNET_TOP := 1.28
const ROOF_TOP := 2.08
## Light bar flashes per second (red and blue alternate).
const FLASH_HZ := 2.5

var flashing := true

var _red: StandardMaterial3D
var _blue: StandardMaterial3D
var _light := OmniLight3D.new()
var _time := 0.0


func _ready() -> void:
	# The bodywork and glass are Blender-made (tools/blender/build_landcruiser.py):
	# rounded panels, cut wheel arches, tube bull bar. Vertex colours are the paint.
	var model := MODEL.instantiate()
	add_child(model)
	var paint := _material(Color.WHITE, 0.45, 0.15, true)
	var glass := _material(Color(0.04, 0.05, 0.07), 0.08, 0.6, false)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = glass if mesh.name.begins_with("Glass") else paint
	var half := LENGTH * 0.5
	# The light bar: a red and a blue lens that light in turn.
	_red = _emissive(Color(0.9, 0.05, 0.04))
	_blue = _emissive(Color(0.06, 0.2, 1.0))
	for pair in [[0.33, _red], [-0.33, _blue]]:
		var lens := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.14, 0.26)
		lens.mesh = box
		lens.material_override = pair[1]
		lens.position = Vector3(pair[0], ROOF_TOP + 0.13, COWL_Z + 0.35)
		add_child(lens)
	_light.omni_range = 8.0
	_light.light_energy = 2.5
	_light.position = Vector3(0, ROOF_TOP + 0.5, COWL_Z + 0.35)
	_light.visible = false
	add_child(_light)
	for side in [-1.0, 1.0]:
		_text("POLICE", Vector3(side * (WIDTH * 0.5 + 0.012), 0.98, COWL_Z + 1.2), Vector3(side, 0, 0), 0.17, CHECK_WHITE)
	_text("POLICE", Vector3(0, BONNET_TOP + 0.065, -half + 0.45), Vector3.UP, 0.15, CHECK_WHITE)
	# Solid to bullets and walkers.
	var collider := StaticBody3D.new()
	collider.collision_layer = PhysicsLayers.WORLD
	collider.set_meta("surface", "vehicle")
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(WIDTH + 0.1, ROOF_TOP - 0.2, LENGTH + 0.3)
	shape.shape = bounds
	shape.position = Vector3(0, (ROOF_TOP + 0.2) * 0.5, -0.1)
	collider.add_child(shape)
	add_child(collider)


func _process(delta: float) -> void:
	_time += delta
	var phase := fmod(_time * FLASH_HZ, 1.0)
	var red_on := flashing and phase < 0.5
	var blue_on := flashing and phase >= 0.5
	_red.emission_energy_multiplier = 4.0 if red_on else 0.15
	_blue.emission_energy_multiplier = 4.0 if blue_on else 0.15
	# Shown only while flashing: a hidden light costs nothing.
	_light.visible = flashing
	_light.light_color = Color(1.0, 0.15, 0.1) if red_on else Color(0.2, 0.35, 1.0)


func _emissive(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	return material


func _text(text: String, at: Vector3, normal: Vector3, height: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = GrivetStyle.heavy()
	label.font_size = 64
	label.outline_size = 0
	label.pixel_size = height / 64.0
	label.modulate = color
	label.shaded = true
	label.double_sided = false
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = at
	label.basis = Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.9 else Vector3.UP)
	add_child(label)


func _material(color: Color, roughness: float, metallic: float, vertex_colors: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = vertex_colors
	material.vertex_color_is_srgb = true  # painted in Blender as sRGB
	material.roughness = roughness
	material.metallic = metallic
	return material
