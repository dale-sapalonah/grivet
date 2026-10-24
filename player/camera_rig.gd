class_name CameraRig
extends Node3D
## Procedural first-person camera layered on the Head (which carries pitch
## and eye height): footstep bob, lean (clamped so it never peeks through
## walls), strafe roll, landing dip and sprint/slide/ADS field of view.

var tuning: CameraTuning
## The held weapon's aim zoom; below zero falls back to CameraTuning's.
var ads_fov_multiplier := -1.0

var _body: CollisionObject3D
var _bob_phase := 0.0
var _bob_weight := 0.0
var _dip := 0.0
var _dip_velocity := 0.0
var _roll := 0.0
var _kick := 0.0
var _kick_velocity := 0.0
var _shake := 0.0

@onready var camera: Camera3D = $Camera3D


func setup(camera_tuning: CameraTuning, body: CollisionObject3D) -> void:
	tuning = camera_tuning
	_body = body
	camera.fov = tuning.base_fov


func add_landing(impact_speed: float) -> void:
	if impact_speed < tuning.landing_min_speed:
		return
	_dip_velocity -= minf(impact_speed, tuning.landing_max_speed) * tuning.landing_kick


## Blast shake (degrees of jitter) that dies away; camera only.
func add_shake(degrees: float) -> void:
	_shake = maxf(_shake, degrees)


## Camera-only upward kick (degrees) that springs back; does not move the aim.
func add_kick(degrees: float) -> void:
	_kick_velocity += deg_to_rad(degrees) * tuning.kick_impulse


func update_rig(delta: float, model: MovementModel, intent: MovementModel.Intent,
		horizontal_speed: float, grounded: bool) -> void:
	var bob := _update_bob(delta, model, horizontal_speed, grounded)

	var spring := -tuning.landing_spring * _dip - tuning.landing_damping * _dip_velocity
	_dip_velocity += spring * delta
	_dip += _dip_velocity * delta

	var lean_x := _clamp_lean(model.lean * tuning.lean_offset)
	position = Vector3(bob.x + lean_x, bob.y + _dip, 0.0)

	var target_roll := -model.lean * deg_to_rad(tuning.lean_angle_degrees) \
			- intent.move.x * deg_to_rad(tuning.strafe_roll_degrees)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-tuning.roll_blend_speed * delta))
	rotation.z = _roll

	_kick_velocity += (-tuning.kick_spring * _kick - tuning.kick_damping * _kick_velocity) * delta
	_kick += _kick_velocity * delta
	_shake = move_toward(_shake, 0.0, tuning.shake_decay * delta)
	var jitter := deg_to_rad(_shake)
	rotation.x = _kick + randf_range(-jitter, jitter)
	rotation.z += randf_range(-jitter, jitter)

	camera.fov = lerpf(camera.fov, _target_fov(model),
			1.0 - exp(-tuning.fov_blend_speed * delta))


func _update_bob(delta: float, model: MovementModel, horizontal_speed: float,
		grounded: bool) -> Vector2:
	var moving := grounded and horizontal_speed > tuning.bob_min_speed \
			and model.gait != MovementModel.Gait.SLIDE
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, tuning.bob_blend_speed * delta)
	_bob_phase = fmod(_bob_phase + horizontal_speed * delta / tuning.step_length * PI, TAU)

	var amplitude := tuning.bob_walk
	match model.gait:
		MovementModel.Gait.SPRINT:
			amplitude = tuning.bob_sprint
		MovementModel.Gait.TAC_SPRINT:
			amplitude = tuning.bob_tac_sprint
	match model.stance:
		MovementModel.Stance.CROUCH:
			amplitude *= tuning.bob_crouch_multiplier
		MovementModel.Stance.PRONE:
			amplitude *= tuning.bob_prone_multiplier
	if model.aiming:
		amplitude *= tuning.bob_ads_multiplier
	amplitude *= _bob_weight
	# One vertical dip per step, one side-to-side sway per two steps.
	return Vector2(sin(_bob_phase) * amplitude * 0.5, -absf(sin(_bob_phase)) * amplitude)


func _clamp_lean(offset: float) -> float:
	if is_zero_approx(offset):
		return 0.0
	var head := get_parent() as Node3D
	var from := head.global_position
	var side := head.global_basis.x * signf(offset)
	var reach := absf(offset) + tuning.lean_wall_margin
	var query := PhysicsRayQueryParameters3D.create(from, from + side * reach,
			_body.collision_mask, [_body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return offset
	var room := maxf(from.distance_to(hit.position) - tuning.lean_wall_margin, 0.0)
	return signf(offset) * minf(absf(offset), room)


func _target_fov(model: MovementModel) -> float:
	var fov := tuning.base_fov
	match model.gait:
		MovementModel.Gait.SPRINT:
			fov += tuning.sprint_fov_add
		MovementModel.Gait.TAC_SPRINT:
			fov += tuning.tac_sprint_fov_add
		MovementModel.Gait.SLIDE:
			fov += tuning.slide_fov_add
	if model.aiming:
		fov *= ads_fov_multiplier if ads_fov_multiplier > 0.0 else tuning.ads_fov_multiplier
	return fov
