class_name WeaponViewModel
extends Node3D
## Placeholder first-person gun assembled from primitive shapes, sized by the
## WeaponDefinition and styled by its view_style:
##   RIFLE   - split receiver, ribbed top rail, octagonal handguard, muzzle
##             device, curved magazine, angled grip, trigger guard, tube stock,
##             peep (aperture) rear sight and eared front post.
##   SHOTGUN - round-topped receiver, vent rib and bead, magazine tube,
##             grooved wooden pump, wooden wrist and stock, butt pad.
##   PISTOL  - slide with rear serrations, frame, angled grip with a magazine
##             base plate, notch-and-post sights.
## Poses: hip / aim / sprint, plus equip, reload, pump and inspect motion,
## mouse sway and a kick spring. Contact points (magazine seated, pump at the
## rear stop) use ViewModelTuning timings the WeaponHolder also uses for sound.
## Gloved hands and forearms (ViewArms) hold it: right hand on the grip with
## the finger on the trigger, left hand on the handguard, the pump (riding with
## it) or cupping the pistol grip, reaching for the magazine during reloads.

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

var _arms := ViewArms.new()
var _knife := Node3D.new()
## Hand holds in the gun's frame (the left one in the pump's when it rides it),
## and the support hand's hold on the magazine / at the loading port.
var _right_hold := Transform3D.IDENTITY
var _left_hold := Transform3D.IDENTITY
var _left_on_pump := false
var _grips: Array[ViewArms.Grip] = []
var _magazine_hold := Transform3D.IDENTITY
var _loading_hold := Transform3D.IDENTITY

var _metal: StandardMaterial3D
var _dark: StandardMaterial3D
var _furniture: StandardMaterial3D


func _ready() -> void:
	add_child(_gun)
	_arms.tuning = tuning
	add_child(_arms)
	_build_knife()


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
	_metal = _material(definition.body_color, 0.6, 0.45)
	_dark = _material(definition.body_color.darkened(0.45), 0.5, 0.5)
	PbrLibrary.apply_standard(_metal, "weapon_metal")  # authored maps, if present
	PbrLibrary.apply_standard(_dark, "weapon_metal")
	_furniture = _material(definition.furniture_color, 0.0, 0.8)
	_magazine = Node3D.new()
	_gun.add_child(_magazine)
	_pump = null
	_port = Node3D.new()
	_gun.add_child(_port)

	var muzzle: Vector3
	match definition.view_style:
		WeaponDefinition.ViewStyle.SHOTGUN:
			muzzle = _build_shotgun(definition)
		WeaponDefinition.ViewStyle.PISTOL:
			muzzle = _build_pistol(definition)
		_:
			muzzle = _build_rifle(definition)
	_magazine_rest = _magazine.position
	if _pump != null:
		_pump_rest = _pump.position
	_build_flash(muzzle)
	_arms.build(_grips[0], _grips[1])

	_pose_position = definition.hip_offset + Vector3.DOWN * tuning.equip_drop
	_pose_rotation = Vector3.ZERO
	_prewarm_flash_frames = 2


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
	var target_rotation := Vector3.ZERO
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


# --- Styles: each returns the muzzle point and fills _magazine, _pump, _port,
# and _ads_position (eye at the rear sight, looking along the sight line). ----

func _build_rifle(definition: WeaponDefinition) -> Vector3:
	var receiver := definition.receiver_size
	var front := -receiver.z * 0.5
	var back := receiver.z * 0.5
	var upper_height := receiver.y * 0.45
	var upper_y := receiver.y * 0.5 - upper_height * 0.5
	var upper_top := receiver.y * 0.5
	var lower_height := receiver.y * 0.55
	var lower_y := -receiver.y * 0.5 + lower_height * 0.5
	var lower_bottom := -receiver.y * 0.5
	var bore_y := upper_y

	_box(_gun, Vector3(receiver.x, upper_height, receiver.z), Vector3(0, upper_y, 0), _metal)
	_box(_gun, Vector3(receiver.x * 0.92, lower_height, receiver.z * 0.62),
			Vector3(0, lower_y, receiver.z * 0.08), _metal)

	# Top rail: base plus a rib every centimetre.
	var rail_length := receiver.z * 0.95
	_box(_gun, Vector3(receiver.x * 0.5, 0.006, rail_length), Vector3(0, upper_top + 0.003, 0), _dark)
	var rib_count := int(rail_length / 0.01)
	_ribs(_gun, rib_count, Vector3(receiver.x * 0.6, 0.004, 0.005),
			Vector3(0, upper_top + 0.008, -rail_length * 0.5 + 0.005), Vector3(0, 0, 0.01), _dark)
	var rail_top := upper_top + 0.01

	# Handguard around the barrel, barrel, gas block, muzzle device.
	var handguard_length := definition.barrel_length * 0.8
	_cylinder(_gun, receiver.x * 0.62, handguard_length,
			Vector3(0, bore_y, front - handguard_length * 0.5), _furniture, 8)
	_cylinder(_gun, definition.barrel_radius, definition.barrel_length,
			Vector3(0, bore_y, front - definition.barrel_length * 0.5), _dark)
	var gas_z := front - handguard_length - 0.015
	_box(_gun, Vector3(0.02, 0.03, 0.02), Vector3(0, bore_y + 0.02, gas_z), _dark)
	var device_length := 0.045
	var muzzle_z := front - definition.barrel_length - device_length
	_cylinder(_gun, definition.barrel_radius * 1.6, device_length,
			Vector3(0, bore_y, front - definition.barrel_length - device_length * 0.5), _dark)

	# Curved magazine: three segments leaning further forward as they go down.
	var magazine := definition.magazine_mesh_size
	_box(_gun, Vector3(magazine.x * 1.25, 0.02, magazine.z * 1.15),
			Vector3(0, lower_bottom - 0.005, -receiver.z * 0.05), _metal)
	_magazine.position = Vector3(0, lower_bottom, -receiver.z * 0.05)
	var segment := magazine.y / 3.0
	var cursor := Vector3.ZERO
	for i in 3:
		var tilt := deg_to_rad(8.0 * (i + 0.5))
		var down := Vector3(0, -cos(tilt), -sin(tilt))
		_box(_magazine, Vector3(magazine.x, segment, magazine.z), cursor + down * segment * 0.5,
				_dark, Vector3(rad_to_deg(tilt), 0, 0))
		cursor += down * segment

	# Grip, trigger guard and trigger.
	_box(_gun, Vector3(receiver.x * 0.7, 0.1, 0.035),
			Vector3(0, lower_bottom - 0.045, back - receiver.z * 0.3), _furniture, Vector3(-18, 0, 0))
	_trigger_group(Vector3(0, lower_bottom - 0.012, receiver.z * 0.04))
	_right_hold = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-18.0), 0, 0)),
			Vector3(0, lower_bottom - 0.04, back - receiver.z * 0.3))
	_left_hold = Transform3D(SUPPORT_BASIS, Vector3(0, bore_y - 0.004, front - handguard_length * 0.45))
	_left_on_pump = false
	_magazine_hold = Transform3D(Basis(Vector3.UP, PI), Vector3(0, -magazine.y * 0.55, -0.01))
	_grips = [ViewArms.Grip.new(0.018, Vector3(0.03, -0.075, 0.03), false, true),
			ViewArms.Grip.support(receiver.x * 0.62, Vector3(receiver.x * 0.62 + 0.03, 0.05, 0.0))]

	# Stock: buffer tube, cheek riser, butt.
	_cylinder(_gun, 0.014, 0.16, Vector3(0, bore_y - 0.01, back + 0.08), _dark)
	_box(_gun, Vector3(receiver.x * 0.7, 0.02, 0.1), Vector3(0, bore_y + 0.015, back + 0.11), _furniture)
	_box(_gun, Vector3(receiver.x * 0.85, receiver.y * 1.25, 0.05),
			Vector3(0, bore_y - 0.03, back + 0.16), _furniture)
	_box(_gun, Vector3(0.03, 0.008, 0.02), Vector3(0, upper_top - 0.004, back - 0.01), _dark)  # charging handle

	# Ejection port on the right, where casings leave.
	_box(_gun, Vector3(0.002, 0.014, 0.05), Vector3(receiver.x * 0.5 + 0.001, upper_y, -receiver.z * 0.05), _dark)
	_port.position = Vector3(receiver.x * 0.5 + 0.01, upper_y, -receiver.z * 0.05)

	# Peep rear sight on the rail; eared front post on the gas block, its tip
	# exactly on the line through the aperture centre.
	var rear_z := back - 0.03
	_box(_gun, Vector3(0.022, 0.012, 0.02), Vector3(0, rail_top + 0.006, rear_z), _dark)
	var ring_outer := 0.0075
	var sight_line := rail_top + 0.012 + ring_outer
	_torus(_gun, 0.0045, ring_outer, Vector3(0, sight_line, rear_z), _dark, Vector3(90, 0, 0))
	var post_base := bore_y + 0.035
	_box(_gun, Vector3(0.003, sight_line - post_base, 0.003),
			Vector3(0, (post_base + sight_line) * 0.5, gas_z), _dark)
	for side in [-1.0, 1.0]:
		_box(_gun, Vector3(0.002, 0.02, 0.006), Vector3(side * 0.007, post_base + 0.01, gas_z), _dark)
	_ads_position = Vector3(0, -sight_line, -definition.ads_distance - rear_z)
	return Vector3(0, bore_y, muzzle_z)


func _build_shotgun(definition: WeaponDefinition) -> Vector3:
	var receiver := definition.receiver_size
	var length := receiver.z * 0.5
	var front := -length * 0.5
	var back := length * 0.5
	var box_height := receiver.y * 0.75
	var box_y := -receiver.y * 0.125
	var box_top := box_y + box_height * 0.5
	var box_bottom := box_y - box_height * 0.5
	var radius := definition.barrel_radius
	var bore_y := box_top + radius * 0.5

	_box(_gun, Vector3(receiver.x, box_height, length), Vector3(0, box_y, 0), _metal)
	_cylinder(_gun, receiver.x * 0.5, length, Vector3(0, box_top, 0), _metal, 16)  # rounded top
	_box(_gun, Vector3(0.002, 0.02, 0.05), Vector3(receiver.x * 0.5 + 0.001, box_y + 0.012, -0.02), _dark)
	_port.position = Vector3(receiver.x * 0.5 + 0.012, box_y + 0.012, -0.02)
	_box(_gun, Vector3(0.018, 0.002, 0.06), Vector3(0, box_bottom - 0.001, front + 0.04), _dark)  # loading port

	# Barrel with vent rib and bead; magazine tube under it.
	_cylinder(_gun, radius, definition.barrel_length,
			Vector3(0, bore_y, front - definition.barrel_length * 0.5), _dark)
	var rib_y := bore_y + radius + 0.002
	_box(_gun, Vector3(0.008, 0.004, definition.barrel_length), Vector3(0, rib_y, front - definition.barrel_length * 0.5), _metal)
	var muzzle_z := front - definition.barrel_length
	var bead_radius := 0.003
	var sight_line := rib_y + 0.002 + bead_radius
	_sphere(_gun, bead_radius, Vector3(0, sight_line, muzzle_z + 0.01), _material(Color(0.9, 0.85, 0.7), 0.8, 0.3))
	var tube_y := bore_y - radius - 0.014
	var tube_length := definition.barrel_length * 0.85
	_cylinder(_gun, 0.014, tube_length, Vector3(0, tube_y, front - tube_length * 0.5), _dark)
	_cylinder(_gun, 0.015, 0.02, Vector3(0, tube_y, front - tube_length), _metal)

	# Wooden pump with grooves; it is what slides when racking.
	_pump = Node3D.new()
	_pump.position = Vector3(0, tube_y, front - 0.11)
	_gun.add_child(_pump)
	var pump_length := 0.16
	_cylinder(_pump, 0.024, pump_length, Vector3.ZERO, _furniture, 10)
	for i in 5:
		_cylinder(_pump, 0.0245, 0.005, Vector3(0, 0, -pump_length * 0.4 + i * pump_length * 0.2), _dark, 10)

	_trigger_group(Vector3(0, box_bottom - 0.012, 0.03))
	# Right hand round the stock's wrist (axis along it, thumb over the top);
	# left hand on the pump, riding it when racking.
	_right_hold = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-76.0), 0, 0)), Vector3(0, box_y - 0.016, back + 0.05))
	_left_hold = Transform3D(SUPPORT_BASIS, Vector3.ZERO)
	_left_on_pump = true
	_loading_hold = Transform3D(SUPPORT_BASIS, Vector3(0, box_bottom - 0.03, front + 0.04))
	_grips = [ViewArms.Grip.new(0.024, Vector3(0.03, -0.078, -0.022)),
			ViewArms.Grip.support(0.026, Vector3(0.056, 0.05, 0.0))]

	# Wooden wrist and stock dropping toward the butt, with a dark pad.
	_box(_gun, Vector3(receiver.x * 0.8, 0.05, 0.1), Vector3(0, box_y - 0.012, back + 0.045), _furniture, Vector3(14, 0, 0))
	_box(_gun, Vector3(receiver.x * 0.85, 0.07, 0.22), Vector3(0, box_y - 0.04, back + 0.19), _furniture, Vector3(8, 0, 0))
	_box(_gun, Vector3(receiver.x * 0.9, 0.085, 0.02), Vector3(0, box_y - 0.055, back + 0.305), _dark, Vector3(8, 0, 0))

	var rear_z := back - 0.02
	_ads_position = Vector3(0, -sight_line, -definition.ads_distance - rear_z)
	return Vector3(0, bore_y, muzzle_z)


func _build_pistol(definition: WeaponDefinition) -> Vector3:
	var receiver := definition.receiver_size
	var front := -receiver.z * 0.5
	var back := receiver.z * 0.5
	var slide_height := receiver.y * 0.5
	var slide_y := slide_height * 0.5
	var slide_top := slide_height
	var bore_y := slide_y + 0.003

	_box(_gun, Vector3(receiver.x, slide_height, receiver.z), Vector3(0, slide_y, 0), _metal)
	# Rear serrations on both sides of the slide.
	for side in [-1.0, 1.0]:
		_ribs(_gun, 8, Vector3(0.001, slide_height * 0.7, 0.002),
				Vector3(side * (receiver.x * 0.5 + 0.0005), slide_y, back - 0.01), Vector3(0, 0, -0.005), _dark)
	_box(_gun, Vector3(0.012, 0.002, 0.03), Vector3(receiver.x * 0.18, slide_top + 0.0005, -0.01), _dark)  # port
	_port.position = Vector3(receiver.x * 0.5 + 0.01, slide_top - 0.006, -0.01)

	var frame_height := 0.022
	_box(_gun, Vector3(receiver.x * 0.9, frame_height, receiver.z * 0.82),
			Vector3(0, -frame_height * 0.5, receiver.z * 0.08), _furniture)
	_box(_gun, Vector3(receiver.x * 0.8, 0.01, 0.05), Vector3(0, -frame_height - 0.004, front + 0.04), _furniture)
	_cylinder(_gun, definition.barrel_radius, definition.barrel_length,
			Vector3(0, bore_y, front - definition.barrel_length * 0.5 + 0.01), _dark)
	var muzzle_z := front - definition.barrel_length + 0.01
	_cylinder(_gun, definition.barrel_radius * 0.5, 0.002, Vector3(0, bore_y, muzzle_z - 0.001),
			_material(Color.BLACK, 0.0, 1.0))

	# Angled grip; the magazine rides inside it with only the base plate showing.
	var grip_tilt := Vector3(-16, 0, 0)
	var grip_center := Vector3(0, -frame_height - 0.05, back - receiver.z * 0.18)
	_box(_gun, Vector3(receiver.x * 0.85, 0.105, 0.042), grip_center, _furniture, grip_tilt)
	_magazine.position = grip_center
	_magazine.rotation_degrees = grip_tilt
	var magazine := definition.magazine_mesh_size
	_box(_magazine, magazine, Vector3.ZERO, _dark)
	_box(_magazine, Vector3(receiver.x * 0.9, 0.008, 0.046), Vector3(0, -0.0525 - 0.004, 0), _dark)

	_trigger_group(Vector3(0, -frame_height - 0.01, front + receiver.z * 0.42))
	# Two hands: the support hand cups the shooting hand from the left.
	var grip_basis := Basis.from_euler(grip_tilt * (PI / 180.0))
	_right_hold = Transform3D(grip_basis, grip_center + Vector3(0, 0.008, 0))
	_left_hold = Transform3D(grip_basis, grip_center + Vector3(-0.004, -0.006, -0.008))
	_left_on_pump = false
	_magazine_hold = Transform3D(Basis(Vector3.UP, PI), Vector3(0, -0.075, 0))
	_grips = [ViewArms.Grip.new(0.02, Vector3(0.028, -0.075, 0.03), false, true),
			ViewArms.Grip.new(0.034, Vector3(-0.058, -0.07, 0.012), true)]

	# Notch rear sight and front post; the post tip sits on the sight line.
	var rear_z := back - 0.012
	_box(_gun, Vector3(0.02, 0.006, 0.008), Vector3(0, slide_top + 0.003, rear_z), _dark)
	var notch_top := slide_top + 0.012
	for side in [-1.0, 1.0]:
		_box(_gun, Vector3(0.006, 0.006, 0.008), Vector3(side * 0.006, notch_top - 0.003, rear_z), _dark)
	var sight_line := notch_top - tuning.sight_post_height * (1.0 - tuning.sight_line_fraction)
	_box(_gun, Vector3(0.003, sight_line - slide_top, 0.004),
			Vector3(0, (slide_top + sight_line) * 0.5, front + 0.006), _dark)
	_ads_position = Vector3(0, -sight_line, -definition.ads_distance - rear_z)
	return Vector3(0, bore_y, muzzle_z)


func _trigger_group(at: Vector3) -> void:
	var guard := _torus(_gun, 0.014, 0.017, at, _dark, Vector3(0, 0, 90))
	guard.scale = Vector3(1.0, 1.0, 1.5)
	_box(_gun, Vector3(0.006, 0.016, 0.005), at + Vector3(0, 0.004, -0.004), _dark, Vector3(-10, 0, 0))


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


func _torus(parent: Node3D, inner: float, outer: float, at: Vector3, material: Material,
		rotation_deg: Vector3) -> MeshInstance3D:
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 16
	torus.ring_segments = 8
	var instance := _mesh(parent, torus, at, material)
	instance.rotation_degrees = rotation_deg
	return instance


func _sphere(parent: Node3D, radius: float, at: Vector3, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	return _mesh(parent, sphere, at, material)


## A row of identical small boxes in one draw call (rail ribs, serrations).
func _ribs(parent: Node3D, count: int, size: Vector3, first: Vector3, step: Vector3,
		material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = count
	for i in count:
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, first + step * i))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
