class_name CoverScoring
extends RefCounted
## Pure: how good a cover point is for one soldier right now. Higher is
## better; -INF means unusable (no protection from the threat). Weights come
## from AiSettings ("Cover scoring").


## protection: 0 none, half_cover_value for half, 1 full.
## flank_from: when set (not Vector3.INF), favour points that open a wide
## angle around the threat relative to this position (the soldier's current
## line to the target), and reject narrow ones.
static func score(settings: AiSettings, point: Vector3, protection: float, self_position: Vector3,
		threat: Vector3, profile: EnemyProfile, occupied: bool, flank_from: Vector3 = Vector3.INF) -> float:
	if protection <= 0.0:
		return -INF
	var value := protection * settings.protection_weight
	value -= flat_distance(point, self_position) * settings.travel_cost_per_metre
	var range_to_threat := flat_distance(point, threat)
	if range_to_threat < profile.preferred_range_min:
		value -= (profile.preferred_range_min - range_to_threat) * settings.too_close_cost_per_metre
	elif range_to_threat > profile.preferred_range_max:
		value -= (range_to_threat - profile.preferred_range_max) * settings.too_far_cost_per_metre
	if occupied:
		value -= settings.occupied_cost
	if flank_from != Vector3.INF:
		var angle := flank_angle(point, flank_from, threat)
		if angle < settings.flank_min_angle:
			return -INF
		value += angle / 90.0 * settings.flank_weight
	return value


## Angle (degrees, 0..180) at the threat between `from` and `point`, on the ground plane.
static func flank_angle(point: Vector3, from: Vector3, threat: Vector3) -> float:
	var a := Vector2(point.x - threat.x, point.z - threat.z)
	var b := Vector2(from.x - threat.x, from.z - threat.z)
	if a.is_zero_approx() or b.is_zero_approx():
		return 0.0
	return rad_to_deg(absf(a.angle_to(b)))


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
