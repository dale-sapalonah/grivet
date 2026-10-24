class_name MuzzleFlash
extends Node3D
## A world-space muzzle flash for third-person shooters (enemies): a short,
## bright light that lights up walls and corners around the shooter, and a
## camera-facing glow. Each shot varies the brightness, size and spin a little.
## Place it at the muzzle and call flash().

var energy := 10.0
var light_range := 10.0
var duration := 0.05
var size := 0.35

var _light: OmniLight3D
var _glow: MeshInstance3D
var _left := 0.0


func setup(flash_energy: float, flash_range: float, flash_time: float, flash_size: float) -> void:
	energy = flash_energy
	light_range = flash_range
	duration = flash_time
	size = flash_size
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.72, 0.38)
	_light.omni_range = light_range
	_light.omni_attenuation = 1.4
	_light.visible = false  # hidden, not dimmed: a dark light still costs every nearby pixel
	add_child(_light)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_glow = MeshInstance3D.new()
	_glow.mesh = quad
	_glow.material_override = glow_material()
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	add_child(_glow)
	set_process(false)


func flash() -> void:
	var strength := randf_range(0.8, 1.2)
	_light.light_energy = energy * strength
	_light.visible = true
	_glow.scale = Vector3.ONE * size * strength
	_glow.rotation.z = randf() * TAU
	_glow.visible = true
	_left = duration
	set_process(true)


func _process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_light.visible = false
		_glow.visible = false
		set_process(false)


## Additive radial glow: hot white core fading through orange to nothing.
static func glow_material() -> StandardMaterial3D:
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	glow.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.6, 0.2, 0.6), Color(1.0, 0.4, 0.1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = glow
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	return material
