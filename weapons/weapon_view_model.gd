class_name WeaponViewModel
extends Node3D
## The first-person gun: the weapon's 3D model (WeaponDefinition.model, a
## GunModel) with its moving parts (Magazine, Pump, Slide) on their own
## nodes, held by gloved hands (ViewArms) at the GunModel's points. Hold
## shapes come from the view_style: RIFLE (pistol grip, support hand under the
## handguard), SHOTGUN (hand round the stock's wrist, support hand riding the
## pump), PISTOL (support hand cupping the shooting hand).
## Poses: hip / aim / sprint, plus equip, reload, pump and inspect motion,
## mouse sway and a kick spring; the slide runs back with each shot. Contact
## points (magazine seated, pump at the rear stop) use ViewModelTuning timings
## the WeaponHolder also uses for sound.

## Support hand under a barrel-axis part (handguard, pump): palm on the
## lower left (hand +X), hand axis along the barrel (+Y = gun back), fingers
## curling under to the right side (hidden behind the barrel), thumb forward
## along the upper left where the shooter sees it (hand +Z).
const SUPPORT_BASIS := Basis(Vector3(-0.7071, -0.7071, 0), Vector3(0, 0, 1), Vector3(-0.7071, 0.7071, 0))

var tuning: ViewModelTuning
## 0..1 through a knife strike (the WeaponHolder sets it), below zero otherwise.
var knife_progress := -1.0

var _definition: WeaponDefinition
var _gun := Node3D.new()
var _magazine: Node3D
var _magazine_rest := Vector3.ZERO
var _pump: Node3D
var _pump_rest := Vector3.ZERO
var _slide: Node3D
var _slide_rest := Vector3.ZERO
var _port := Node3D.new()
var _flash_light: OmniLight3D
var _flash_strength := 1.0
var _flash_mesh: MeshInstance3D
var _ads_position := Vector3.ZERO
var _pose_position := Vector3.ZERO
var _pose_rotation := Vector3.ZERO
var _sway := Vector2.ZERO
var _kick_back := 0.0
var _kick_back_velocity := 0.0
var _kick_pitch := 0.0
var _kick_pitch_velocity := 0.0
var _flash_left := 0.0
## Frames left drawing the flash invisibly small after a build, so its shader
## compiles while equipping rather than on the first shot.
var _prewarm_flash_frames := 0

## ViewArms (shapes) or SkinnedViewArms (a rigged model): build(), place().
var _arms: Node3D
var _knife := Node3D.new()
## Hand holds in the gun's frame (the left one in the pump's when it rides it),
## and the support hand's hold on the magazine / at the loading port.
var _right_hold := Transform3D.IDENTITY
var _left_hold := Transform3D.IDENTITY
var _left_on_pump := false
var _grips: Array[ViewArms.Grip] = []
var _magazine_hold := Transform3D.IDENTITY
var _loading_hold := Transform3D.IDENTITY


func _ready() -> void:
	add_child(_gun)
	_arms = SkinnedViewArms.new() if tuning.arms_model != null else ViewArms.new()
	_arms.tuning = tuning
	add_child(_arms)
	_build_knife()
	# A soft fill light on the gun and arms only (their own render layer): at
	# dusk the guns read black against the ground.
	var fill := OmniLight3D.new()
	fill.light_color = tuning.view_fill_color
	fill.light_energy = tuning.view_fill_energy
	fill.omni_range = tuning.view_fill_range
	fill.position = tuning.view_fill_position
	fill.light_cull_mask = VIEW_LAYER
	fill.shadow_enabled = false
	add_child(fill)
	_to_view_layer(self)


## A gloved fist round a dark grip, a small guard and the blade forward (-Z).
func _build_knife() -> void:
	var glove := _material(tuning.glove_color, 0.0, 0.85)
	var grip := _material(Color(0.07, 0.07, 0.07), 0.1, 0.7)
	var steel := _material(Color(0.62, 0.63, 0.64), 0.85, 0.3)
	_sphere(_knife, 0.032, Vector3(0, -0.004, 0.035), glove).scale = Vector3(1.1, 1.0, 1.5)
	# Wrist and sleeved forearm running back out of view.
	var sleeve := _material(tuning.sleeve_camo_a, 0.0, 0.9)
	_cylinder(_knife, 0.026, 0.06, Vector3(0, -0.006, 0.08), glove, 10)
	_cylinder(_knife, 0.038, 0.34, Vector3(0, -0.01, 0.27), sleeve, 10)
	_cylinder(_knife, 0.014, 0.11, Vector3(0, 0, -0.02), grip, 8)
	_box(_knife, Vector3(0.05, 0.012, 0.008), Vector3(0, 0, -0.08), grip)
	_box(_knife, Vector3(0.004, 0.026, 0.16), Vector3(0, 0, -0.165), steel)
	_box(_knife, Vector3(0.004, 0.012, 0.03), Vector3(0, -0.006, -0.255), steel, Vector3(-25, 0, 0))
	_knife.visible = false
	add_child(_knife)


func build(definition: WeaponDefinition) -> void:
	_definition = definition
	for child in _gun.get_children():
		child.queue_free()
	_magazine = Node3D.new()
	_gun.add_child(_magazine)
	_pump = null
	_slide = null
	_port = Node3D.new()
	_gun.add_child(_port)
	var gun := definition.model
	var model := gun.scene.instantiate() as Node3D
	_gun.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null:
				mesh.set_surface_override_material(surface, _toned(material))
	# Moving parts ride their own nodes (placed at the part, so they move
	# from where they sit).
	_magazine.transform = _carry(model, "Magazine", _magazine)
	var pump_part := model.find_child("Pump", true, false) as Node3D
	if pump_part != null:
		_pump = Node3D.new()
		_gun.add_child(_pump)
		_pump.transform = _carry(model, "Pump", _pump)
	if model.find_child("Slide", true, false) != null:
		_slide = Node3D.new()
		_gun.add_child(_slide)
		_slide.transform = _carry(model, "Slide", _slide)
	_port.position = gun.port
	_hold(definition, gun)
	if _arms.has_method("set_holds"):
		var left_on_gun := (_pump.transform * _left_hold) if _left_on_pump and _pump != null else _left_hold
		_arms.call("set_holds", gun, definition.view_style, _right_hold, left_on_gun, _gun_surface)
	_ads_position = Vector3(-gun.sight.x, -gun.sight.y, -definition.ads_distance - gun.sight.z)
	_magazine_rest = _magazine.position
	if _pump != null:
		_pump_rest = _pump.position
	if _slide != null:
		_slide_rest = _slide.position
	_build_flash(gun.muzzle)
	_arms.build(_grips[0], _grips[1])
	_to_view_layer(_gun)

	_pose_position = definition.hip_offset + Vector3.DOWN * tuning.equip_drop
	_pose_rotation = Vector3.ZERO
	_prewarm_flash_frames = 2


## The render layer the gun and arms draw on, so the fill light lights them only.
const VIEW_LAYER := 1 << 1


## Puts every mesh under `root` on VIEW_LAYER as well as the world's layer.
func _to_view_layer(root: Node) -> void:
	for visual: VisualInstance3D in root.find_children("*", "VisualInstance3D", true, false):
		if visual is GeometryInstance3D:
			visual.layers = 1 | VIEW_LAYER


## Gun materials with the first-person metal scale, one per source material,
## kept for the session (made and freed on every weapon switch, they tripped
## an engine error).
static var _toned_cache := {}


func _toned(material: BaseMaterial3D) -> BaseMaterial3D:
	if not _toned_cache.has(material):
		var toned := material.duplicate() as BaseMaterial3D
		toned.metallic *= tuning.gun_metallic_scale
		_toned_cache[material] = toned
	return _toned_cache[material]


## The gun's triangles in its own frame (parts at rest), for the hands to
## close on.
func _gun_surface() -> TriangleMesh:
	var faces := PackedVector3Array()
	var to_gun := _gun.global_transform.affine_inverse()
	for mesh: MeshInstance3D in _gun.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null:
			faces.append_array((to_gun * mesh.global_transform) * mesh.mesh.get_faces())
	var surface := TriangleMesh.new()
	surface.create_from_faces(faces)
	return surface


## Moves the model's part `part_name` under `holder`, returning where the
## holder goes (at the part, in the gun's frame); identity if there is none.
func _carry(model: Node3D, part_name: String, holder: Node3D) -> Transform3D:
	var part := model.find_child(part_name, true, false) as Node3D
	if part == null:
		return Transform3D.IDENTITY
	var at := Transform3D(Basis.IDENTITY, (model.transform * part.transform).origin)
	part.owner = null
	part.get_parent().remove_child(part)
	holder.add_child(part)
	part.transform = at.affine_inverse() * model.transform * part.transform
	return at


## The hands' holds for the view style, at the GunModel's points.
func _hold(definition: WeaponDefinition, gun: GunModel) -> void:
	var grip_basis := Basis.from_euler(Vector3(deg_to_rad(gun.grip_tilt_degrees), 0, 0))
	_right_hold = Transform3D(grip_basis, gun.grip)
	_magazine_hold = Transform3D(Basis(Vector3.UP, PI), gun.magazine_hold)
	_loading_hold = Transform3D(SUPPORT_BASIS, gun.loading_port)
	match definition.view_style:
		WeaponDefinition.ViewStyle.SHOTGUN:
			# Right hand round the stock's wrist (axis along it, thumb over the
			# top); left hand on the pump, riding it when racking.
			_left_hold = Transform3D(SUPPORT_BASIS, gun.support)
			_left_on_pump = _pump != null
			_grips = [ViewArms.Grip.new(0.024, Vector3(0.03, -0.078, -0.022), false, true),
					ViewArms.Grip.support(gun.support_radius, Vector3(gun.support_radius + 0.03, 0.05, 0.0))]
		WeaponDefinition.ViewStyle.PISTOL:
			# Two hands: the support hand cups the shooting hand from the left.
			_left_hold = Transform3D(grip_basis, gun.support)
			_left_on_pump = false
			_grips = [ViewArms.Grip.new(0.02, Vector3(0.028, -0.075, 0.03), false, true),
					ViewArms.Grip.new(0.034, Vector3(-0.058, -0.07, 0.012), true)]
		_:
			_left_hold = Transform3D(SUPPORT_BASIS, gun.support)
			_left_on_pump = false
			_grips = [ViewArms.Grip.new(0.018, Vector3(0.03, -0.075, 0.03), false, true),
					ViewArms.Grip.support(gun.support_radius, Vector3(gun.support_radius + 0.03, 0.05, 0.0))]


## World transform of the ejection port; casings fly out along its basis.
func ejection_port() -> Transform3D:
	return Transform3D(_gun.global_basis, _port.global_position)


func kick() -> void:
	_kick_back_velocity += _definition.view_kick_back * tuning.kick_impulse
	_kick_pitch_velocity += deg_to_rad(_definition.visual_kick_degrees) * tuning.kick_impulse


func flash() -> void:
	_flash_left = tuning.flash_time
	var strength := randf_range(0.8, 1.2)
	_flash_light.light_energy = tuning.flash_energy * strength
	_flash_mesh.rotation.z = randf() * TAU
	_flash_strength = strength


func update_pose(delta: float, weapon: WeaponModel, aim_blend: float, sprinting: bool,
		look_delta: Vector2) -> void:
	if weapon == null or _definition == null:
		return
	var progress := weapon.state_progress()
	var bump := sin(PI * progress)  # 0 -> 1 -> 0 over a timed state
	var target_position := _definition.hip_offset.lerp(_ads_position, aim_blend)
	var target_rotation := _definition.hip_rotation_degrees * (PI / 180.0) * (1.0 - aim_blend)
	if sprinting:
		target_position = _definition.sprint_offset
		target_rotation = _definition.sprint_rotation_degrees * (PI / 180.0)
	match weapon.state:
		WeaponModel.State.RELOADING:
			target_rotation.z += deg_to_rad(tuning.reload_tilt_degrees) * bump
		WeaponModel.State.INSPECTING:
			target_rotation.y += deg_to_rad(tuning.inspect_yaw_degrees) * bump
			target_rotation.z += deg_to_rad(tuning.inspect_roll_degrees) * bump

	var blend := 1.0 - exp(-tuning.pose_blend_speed * delta)
	_pose_position = _pose_position.lerp(target_position, blend)
	_pose_rotation = _pose_rotation.lerp(target_rotation, blend)
	var sway_target := (-look_delta * _definition.sway_amount).limit_length(_definition.sway_limit)
	_sway = _sway.lerp(sway_target, blend)

	var recoil_back := Spring.step(Vector2(_kick_back, _kick_back_velocity), tuning.kick_spring, tuning.kick_damping, delta)
	_kick_back = recoil_back.x
	_kick_back_velocity = recoil_back.y
	var recoil_pitch := Spring.step(Vector2(_kick_pitch, _kick_pitch_velocity), tuning.kick_spring, tuning.kick_damping, delta)
	_kick_pitch = recoil_pitch.x
	_kick_pitch_velocity = recoil_pitch.y

	var equip_offset := 0.0
	if weapon.state == WeaponModel.State.EQUIPPING:
		equip_offset = -tuning.equip_drop * (1.0 - progress)
	_knife.visible = knife_progress >= 0.0
	if _knife.visible:
		# Out to the thrust over the reach share, then back; the gun ducks away.
		var share := tuning.knife_reach_share
		var out := smoothstep(0.0, share, knife_progress) * (1.0 - smoothstep(share, 1.0, knife_progress))
		_knife.position = tuning.knife_rest.lerp(tuning.knife_thrust, out)
		# Blade forward and a little in toward the middle, edge turned to the shooter.
		_knife.rotation = Vector3(deg_to_rad(lerpf(25.0, 4.0, out)), deg_to_rad(lerpf(30.0, 14.0, out)), deg_to_rad(lerpf(-60.0, -80.0, out)))
		equip_offset -= tuning.knife_gun_drop * smoothstep(0.0, 0.12, knife_progress) * (1.0 - smoothstep(0.8, 1.0, knife_progress))
	_gun.position = _pose_position + Vector3(_sway.x, -_sway.y + equip_offset, _kick_back)
	_gun.rotation = _pose_rotation + Vector3(_kick_pitch, _sway.x * 2.0, 0.0)

	_magazine.position = _magazine_rest
	if weapon.state == WeaponModel.State.RELOADING \
			and _definition.reload_mode == WeaponDefinition.ReloadMode.MAGAZINE:
		var out := smoothstep(tuning.magazine_out_start, tuning.magazine_out_end, progress) \
				- smoothstep(tuning.magazine_in_start, tuning.magazine_in_end, progress)
		# Along the magazine's own axis, so angled pistol grips drop it straight out.
		_magazine.position -= _magazine.basis.y * tuning.reload_magazine_drop * out
	if _pump != null:
		_pump.position = _pump_rest
		if weapon.state == WeaponModel.State.PUMPING:
			var back := smoothstep(0.0, tuning.pump_back_end, progress) \
					- smoothstep(tuning.pump_forward_start, tuning.pump_forward_end, progress)
			_pump.position.z += tuning.pump_travel * back
	if _slide != null:
		# The slide runs back with the recoil and returns with it.
		_slide.position = _slide_rest + Vector3.BACK * tuning.slide_travel * clampf(_kick_back / maxf(_definition.view_kick_back, 0.001), 0.0, 1.0)

	_flash_left -= delta
	var flashing := _flash_left > 0.0
	_flash_mesh.visible = flashing or _prewarm_flash_frames > 0
	_flash_mesh.scale = Vector3.ONE * (_flash_strength if flashing else 0.001)
	_prewarm_flash_frames = maxi(_prewarm_flash_frames - 1, 0)
	# Hidden, not just dimmed: a zero-energy light still costs every nearby pixel.
	_flash_light.visible = flashing
	_place_arms(weapon, progress)


func _place_arms(weapon: WeaponModel, progress: float) -> void:
	var right := _gun.transform * _right_hold
	var left := _gun.transform * ((_pump.transform * _left_hold) if _left_on_pump and _pump != null else _left_hold)
	if weapon.state == WeaponModel.State.RELOADING:
		var reach := 0.0
		var target := left
		if _definition.reload_mode == WeaponDefinition.ReloadMode.MAGAZINE:
			reach = smoothstep(tuning.magazine_out_start - tuning.reload_hand_lead, tuning.magazine_out_start, progress) \
					* (1.0 - smoothstep(tuning.magazine_in_end, tuning.magazine_in_end + tuning.reload_hand_lead, progress))
			target = _gun.transform * _magazine.transform * _magazine_hold
		else:
			reach = sin(PI * progress)  # a shell into the loading port
			target = _gun.transform * _loading_hold
		left = left.interpolate_with(target, reach)
	_arms.place(0, right, right * _arms_wrist(0) + _definition.right_elbow_offset)
	_arms.place(1, left, left * _arms_wrist(1) + _definition.left_elbow_offset)


func _arms_wrist(i: int) -> Vector3:
	return _grips[i].wrist


func _build_flash(muzzle: Vector3) -> void:
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.omni_range = tuning.flash_range
	_flash_light.light_energy = tuning.flash_energy
	_flash_light.omni_attenuation = 1.4
	_flash_light.visible = false
	_flash_light.position = muzzle
	_gun.add_child(_flash_light)
	var flash_quad := QuadMesh.new()
	flash_quad.size = Vector2.ONE * tuning.flash_size
	# Soft radial glow: hot white core fading through orange to nothing.
	var glow := Gradient.new()
	glow.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	glow.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.6, 0.2, 0.6), Color(1.0, 0.4, 0.1, 0.0)])
	var glow_texture := GradientTexture2D.new()
	glow_texture.gradient = glow
	glow_texture.fill = GradientTexture2D.FILL_RADIAL
	glow_texture.fill_from = Vector2(0.5, 0.5)
	glow_texture.fill_to = Vector2(0.5, 0.0)
	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_material.albedo_texture = glow_texture
	_flash_mesh = _mesh(_gun, flash_quad, muzzle + Vector3(0, 0, -tuning.flash_size * 0.4), flash_material)
	_flash_mesh.visible = false


# --- Shape helpers -------------------------------------------------------------

func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material,
		rotation_deg := Vector3.ZERO) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := _mesh(parent, box, at, material)
	instance.rotation_degrees = rotation_deg
	return instance


## Cylinder lying along the Z (barrel) axis.
func _cylinder(parent: Node3D, radius: float, length: float, at: Vector3, material: Material,
		segments: int = 12) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = segments
	cylinder.rings = 1
	var instance := _mesh(parent, cylinder, at, material)
	instance.rotation_degrees.x = 90.0
	return instance


func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	return _mesh(parent, sphere, at, material)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
