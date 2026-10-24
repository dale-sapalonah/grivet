class_name PerceptionModel
extends RefCounted
## Pure sight rules. Visibility (0..1) of a target that has line of sight,
## and how awareness builds from it. Combat starts at awareness 1; the
## suspicious band below that sends a soldier to investigate.


## distance in m, angle_degrees off the soldier's forward, stance and motion
## of the target. Returns 0 when outside range or outside the view cone
## (beyond the profile's peripheral range).
static func visibility(profile: EnemyProfile, settings: AiSettings, distance: float, angle_degrees: float,
		target_stance: MovementModel.Stance, target_moving: bool) -> float:
	if distance > profile.sight_range:
		return 0.0
	var peripheral := angle_degrees > profile.fov_degrees * 0.5
	if peripheral and distance > profile.peripheral_range:
		return 0.0
	var value := 1.0 / (1.0 + distance / settings.visibility_half_distance)
	match target_stance:
		MovementModel.Stance.CROUCH:
			value *= settings.stance_visibility_crouch
		MovementModel.Stance.PRONE:
			value *= settings.stance_visibility_prone
		_:
			value *= settings.stance_visibility_stand
	value *= settings.moving_visibility if target_moving else settings.still_visibility
	if peripheral:
		value *= 0.5
	return clampf(value, 0.0, 1.0)


## Awareness rises with visibility and decays without it. Capped a little
## above 1 so a brief loss of sight doesn't drop a soldier out of combat.
static func update_awareness(awareness: float, seen_visibility: float, profile: EnemyProfile, delta: float) -> float:
	if seen_visibility > 0.0:
		awareness += seen_visibility * profile.awareness_gain * delta
	else:
		awareness -= profile.awareness_decay * delta
	return clampf(awareness, 0.0, 1.5)
