class_name AimModel
extends RefCounted
## Pure: how far off an enemy's shot goes (cone half-angle, degrees). Grows
## with distance, is wild for the first burst after acquiring a target (so
## the player gets a moment), and worsens when the shooter is moving, the
## target is moving across the line of fire, or the shooter is suppressed.


static func error_degrees(profile: EnemyProfile, distance: float, suppression: float, self_moving: bool,
		target_lateral_speed: float, time_since_acquired: float) -> float:
	var error := profile.aim_error_degrees + profile.aim_error_per_10m * distance / 10.0
	if time_since_acquired < profile.first_burst_duration:
		error *= lerpf(profile.first_burst_error_multiplier, 1.0, time_since_acquired / profile.first_burst_duration)
	if self_moving:
		error *= profile.moving_error_multiplier
	error *= lerpf(1.0, profile.target_moving_error_multiplier, clampf(target_lateral_speed / 4.0, 0.0, 1.0))
	error *= lerpf(1.0, profile.suppressed_error_multiplier, clampf(suppression, 0.0, 1.0))
	return error
