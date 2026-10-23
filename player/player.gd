class_name Player
extends CharacterBody3D
## First-person player body. Reads input into a MovementModel, then applies
## the result with physics: acceleration, slide, mantle and stance height.
## Camera feel (bob, lean, FOV, landing dip) lives in CameraRig.
## The body origin is at the feet. A downward SeparationRayShape3D (StepRay)
## carries the body over steps up to step_height; the capsule starts above it.

@export var tuning: MovementTuning
@export var camera_tuning: CameraTuning

var model: MovementModel
var noclip := false
var speed_multiplier := 1.0

var _intent := MovementModel.Intent.new()
var _world := MovementModel.World.new()
var _shape: CapsuleShape3D
var _body_height := -1.0
var _probe := CapsuleShape3D.new()
var _pitch := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _mantle_time := 0.0
var _mantle_duration := 0.0

@onready var _collision: CollisionShape3D = $Collision
@onready var _step_ray: CollisionShape3D = $StepRay
@onready var _head: Node3D = $Head
@onready var _rig: CameraRig = $Head/CameraRig
@onready var _legs: Node3D = $LegsPlaceholder


func _ready() -> void:
	model = MovementModel.new(tuning)
	_shape = _collision.shape.duplicate()
	_collision.shape = _shape
	_shape.radius = tuning.radius
	var step_shape := _step_ray.shape.duplicate() as SeparationRayShape3D
	step_shape.length = tuning.step_height
	_step_ray.shape = step_shape
	_step_ray.position.y = tuning.step_height
	_probe.radius = tuning.radius - tuning.probe_margin
	_set_body_height(tuning.stand_height)
	_head.position.y = tuning.stand_eye_height
	floor_snap_length = tuning.floor_snap
	floor_max_angle = deg_to_rad(tuning.max_slope_degrees)
	_rig.setup(camera_tuning, self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_register_debug_commands()


func _exit_tree() -> void:
	for command in ["noclip", "speed", "tp", "pos", "movement.show"]:
		Debug.unregister(command)


func _unhandled_input(event: InputEvent) -> void:
	if Debug.console_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := camera_tuning.mouse_sensitivity
		if model.aiming:
			sensitivity *= camera_tuning.ads_sensitivity_multiplier
		var motion := (event as InputEventMouseMotion).relative
		rotate_y(-motion.x * sensitivity)
		var limit := deg_to_rad(camera_tuning.pitch_limit_degrees)
		_pitch = clampf(_pitch - motion.y * sensitivity, -limit, limit)
		_head.rotation.x = _pitch
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_read_intent()
	if noclip:
		_move_noclip(delta)
	elif model.gait == MovementModel.Gait.MANTLE:
		_update_mantle(delta)
	else:
		_move_normally(delta)
	_update_head(delta)
	_publish_watches()


func _move_normally(delta: float) -> void:
	_world.grounded = is_on_floor()
	_world.horizontal_speed = Vector2(velocity.x, velocity.z).length()
	_world.can_stand = _fits(global_position, tuning.stand_height)
	_world.can_crouch = _fits(global_position, tuning.crouch_height)
	model.update(_intent, _world, delta)
	if model.slide_started:
		var direction := Vector3(velocity.x, 0.0, velocity.z).normalized()
		velocity += direction * tuning.slide_boost

	var jump_pressed := _can_act() and Input.is_action_just_pressed("jump")
	var climbing := _can_act() and Input.is_action_pressed("jump") and not _world.grounded \
			and _intent.move.y >= tuning.sprint_forward_threshold
	if (jump_pressed or climbing) and _try_start_mantle():
		return
	if jump_pressed and model.try_jump(_world):
		velocity.y = tuning.jump_velocity

	_set_body_height(model.target_height())
	_apply_horizontal(delta)
	if not is_on_floor():
		velocity.y -= tuning.gravity * delta
	var fall_speed := -velocity.y
	var was_grounded := is_on_floor()
	var start_height := global_position.y
	move_and_slide()
	var rise := global_position.y - start_height
	if was_grounded and is_on_floor() and rise > 0.0:
		_head.position.y -= rise  # ease the head up a step instead of snapping
	if is_on_floor() and not was_grounded:
		model.land(fall_speed)
		_rig.add_landing(fall_speed)


func _read_intent() -> void:
	_intent.sprint_pressed = false
	_intent.crouch_pressed = false
	_intent.prone_pressed = false
	if not _can_act():
		_intent.move = Vector2.ZERO
		_intent.aiming = false
		_intent.lean = 0.0
		return
	_intent.move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	_intent.sprint_pressed = Input.is_action_just_pressed("sprint")
	_intent.crouch_pressed = Input.is_action_just_pressed("crouch")
	_intent.prone_pressed = Input.is_action_just_pressed("prone")
	_intent.aiming = Input.is_action_pressed("aim")
	_intent.lean = Input.get_axis("lean_left", "lean_right")


func _can_act() -> bool:
	return not Debug.console_open


func _apply_horizontal(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if model.gait == MovementModel.Gait.SLIDE:
		horizontal = horizontal.move_toward(Vector3.ZERO, tuning.slide_friction * delta)
	else:
		var wish := global_basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)
		var target := wish * model.target_speed() * speed_multiplier
		var rate := tuning.air_acceleration
		if is_on_floor():
			rate = tuning.ground_acceleration if wish != Vector3.ZERO else tuning.ground_deceleration
		elif wish == Vector3.ZERO:
			rate = 0.0  # keep momentum in the air
		horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Looks for a flat ledge between mantle_min_height and mantle_max_height
## just ahead, with room for a crouched body on top.
func _try_start_mantle() -> bool:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var feet := global_position
	var reach := forward * tuning.mantle_reach
	var query := PhysicsRayQueryParameters3D.create(
			feet + reach + Vector3.UP * tuning.mantle_max_height,
			feet + reach + Vector3.UP * tuning.mantle_min_height,
			collision_mask, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < tuning.mantle_min_ledge_flatness:
		return false
	var ledge: Vector3 = hit.position
	var target := ledge + forward * tuning.radius + Vector3.UP * tuning.probe_margin
	if not _fits(target, tuning.crouch_height):
		return false
	# Room to rise straight up from here to the ledge.
	if not _fits(feet, ledge.y - feet.y + tuning.crouch_height):
		return false
	model.begin_mantle()
	_mantle_from = feet
	_mantle_to = target
	_mantle_time = 0.0
	_mantle_duration = tuning.mantle_duration * clampf(
			(ledge.y - feet.y) / tuning.mantle_max_height, tuning.mantle_rise_fraction, 1.0)
	velocity = Vector3.ZERO
	_set_body_height(tuning.crouch_height)
	return true


func _update_mantle(delta: float) -> void:
	_mantle_time += delta
	var t := clampf(_mantle_time / _mantle_duration, 0.0, 1.0)
	var rise := ease(clampf(t / tuning.mantle_rise_fraction, 0.0, 1.0), 0.5)
	var forward := clampf((t - tuning.mantle_rise_fraction * 0.5)
			/ (1.0 - tuning.mantle_rise_fraction * 0.5), 0.0, 1.0)
	var position_now := _mantle_from.lerp(_mantle_to, forward)
	position_now.y = lerpf(_mantle_from.y, _mantle_to.y, rise)
	global_position = position_now
	if t >= 1.0:
		model.end_mantle(_fits(global_position, tuning.stand_height))
		_set_body_height(model.target_height())


func _move_noclip(delta: float) -> void:
	var direction := _head.global_basis * Vector3(_intent.move.x, 0.0, -_intent.move.y)
	if _can_act():
		direction += Vector3.UP * Input.get_axis("crouch", "jump")
	global_position += direction * tuning.noclip_speed * speed_multiplier * delta
	velocity = Vector3.ZERO


func _update_head(delta: float) -> void:
	var blend := 1.0 - exp(-tuning.stance_blend_speed * delta)
	_head.position.y = lerpf(_head.position.y, model.eye_height(), blend)
	_rig.update_rig(delta, model, _intent, Vector2(velocity.x, velocity.z).length(), is_on_floor())


func _set_body_height(height: float) -> void:
	if is_equal_approx(_body_height, height):
		return
	_body_height = height
	# The capsule sits on top of the step ray; prone is too short for that,
	# so its capsule reaches the floor.
	_shape.height = maxf(height - tuning.step_height, tuning.radius * 2.0)
	_collision.position.y = height - _shape.height * 0.5
	_legs.scale.y = height / tuning.stand_height


## Would a capsule of `height` fit with its feet at `feet`?
func _fits(feet: Vector3, height: float) -> bool:
	_probe.height = maxf(height - tuning.probe_margin, _probe.radius * 2.0)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _probe
	params.transform = Transform3D(Basis.IDENTITY,
			feet + Vector3.UP * (tuning.probe_margin + _probe.height * 0.5))
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


func _publish_watches() -> void:
	if not Debug.show_watches:
		return
	Debug.watch("stance", MovementModel.Stance.keys()[model.stance])
	Debug.watch("gait", MovementModel.Gait.keys()[model.gait])
	Debug.watch("speed", "%.2f m/s" % Vector2(velocity.x, velocity.z).length())
	Debug.watch("vertical", "%.2f m/s" % velocity.y)
	Debug.watch("grounded", is_on_floor())
	Debug.watch("lean", "%.2f" % model.lean)
	Debug.watch("position", "%.1f, %.1f, %.1f" % [global_position.x, global_position.y, global_position.z])


func _register_debug_commands() -> void:
	Debug.register("noclip", _cmd_noclip, "Toggle fly mode without collision.")
	Debug.register("speed", _cmd_speed, "speed <multiplier>: scale movement speed.")
	Debug.register("tp", _cmd_tp, "tp <x> <y> <z>: teleport the player.")
	Debug.register("pos", _cmd_pos, "Print the player's position.")
	Debug.register("movement.show", _cmd_movement_show, "Toggle movement state readout.")


func _cmd_noclip(_args: PackedStringArray) -> String:
	noclip = not noclip
	_collision.disabled = noclip
	_step_ray.disabled = noclip
	return "noclip %s" % ("ON" if noclip else "OFF")


func _cmd_speed(args: PackedStringArray) -> String:
	if args.size() != 1 or not args[0].is_valid_float():
		return "usage: speed <multiplier>"
	speed_multiplier = args[0].to_float()
	return "speed x%.2f" % speed_multiplier


func _cmd_tp(args: PackedStringArray) -> String:
	if args.size() != 3 or not (args[0].is_valid_float() and args[1].is_valid_float() and args[2].is_valid_float()):
		return "usage: tp <x> <y> <z>"
	global_position = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	velocity = Vector3.ZERO
	return _cmd_pos(args)


func _cmd_pos(_args: PackedStringArray) -> String:
	return "%.2f %.2f %.2f" % [global_position.x, global_position.y, global_position.z]


func _cmd_movement_show(_args: PackedStringArray) -> String:
	Debug.show_watches = not Debug.show_watches
	if not Debug.show_watches:
		Debug.watches.clear()
	return "movement readout %s" % ("ON" if Debug.show_watches else "OFF")
