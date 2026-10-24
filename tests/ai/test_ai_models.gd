extends "res://tests/framework/suite.gd"

const SETTINGS := preload("res://data/ai/ai_settings.tres")
const RIFLEMAN := preload("res://data/ai/rifleman.tres")
const FRAG := preload("res://data/grenades/frag.tres")
const Stance := MovementModel.Stance


func test_visibility_falls_with_distance_and_stance() -> void:
	var near := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 10.0, 0.0, Stance.STAND, false)
	var far := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 50.0, 0.0, Stance.STAND, false)
	var crouched := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 10.0, 0.0, Stance.CROUCH, false)
	var prone := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 10.0, 0.0, Stance.PRONE, false)
	var moving := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 10.0, 0.0, Stance.STAND, true)
	assert_true(near > far, "distance")
	assert_true(near > crouched and crouched > prone, "stance")
	assert_true(moving > near, "movement draws the eye")


func test_outside_view_cone_is_unseen_unless_close() -> void:
	var behind := RIFLEMAN.fov_degrees * 0.5 + 20.0
	assert_eq(PerceptionModel.visibility(RIFLEMAN, SETTINGS, 20.0, behind, Stance.STAND, false), 0.0, "far, behind")
	assert_true(PerceptionModel.visibility(RIFLEMAN, SETTINGS, RIFLEMAN.peripheral_range * 0.5, behind,
			Stance.STAND, true) > 0.0, "close, behind")
	assert_eq(PerceptionModel.visibility(RIFLEMAN, SETTINGS, RIFLEMAN.sight_range + 1.0, 0.0, Stance.STAND, true),
			0.0, "beyond sight range")


func test_awareness_builds_over_time_not_instantly() -> void:
	var visibility := PerceptionModel.visibility(RIFLEMAN, SETTINGS, 30.0, 0.0, Stance.STAND, false)
	var awareness := 0.0
	var seconds := 0.0
	while awareness < 1.0 and seconds < 10.0:
		awareness = PerceptionModel.update_awareness(awareness, visibility, RIFLEMAN, 0.1)
		seconds += 0.1
	assert_true(seconds > 1.0 and seconds < 5.0, "spotted at 30 m after %.1f s" % seconds)


func test_aim_error_grows_with_range_suppression_and_motion() -> void:
	var settled := 5.0  # well past the first burst
	var base := AimModel.error_degrees(RIFLEMAN, 10.0, 0.0, false, 0.0, settled)
	assert_true(AimModel.error_degrees(RIFLEMAN, 40.0, 0.0, false, 0.0, settled) > base, "range")
	assert_true(AimModel.error_degrees(RIFLEMAN, 10.0, 1.0, false, 0.0, settled) > base, "suppression")
	assert_true(AimModel.error_degrees(RIFLEMAN, 10.0, 0.0, true, 0.0, settled) > base, "shooter moving")
	assert_true(AimModel.error_degrees(RIFLEMAN, 10.0, 0.0, false, 4.0, settled) > base, "target crossing")


func test_first_burst_is_wild() -> void:
	var first := AimModel.error_degrees(RIFLEMAN, 20.0, 0.0, false, 0.0, 0.0)
	var settled := AimModel.error_degrees(RIFLEMAN, 20.0, 0.0, false, 0.0, RIFLEMAN.first_burst_duration + 1.0)
	assert_approx(first / settled, RIFLEMAN.first_burst_error_multiplier, 1e-4)


func test_cover_scoring_prefers_protection_and_short_trips() -> void:
	var me := Vector3(0, 0, 0)
	var threat := Vector3(0, 0, -25)
	var near_full := CoverScoring.score(SETTINGS, Vector3(2, 0, 0), 1.0, me, threat, RIFLEMAN, false)
	var near_half := CoverScoring.score(SETTINGS, Vector3(2, 0, 0), SETTINGS.half_cover_value, me, threat, RIFLEMAN, false)
	var far_full := CoverScoring.score(SETTINGS, Vector3(15, 0, 0), 1.0, me, threat, RIFLEMAN, false)
	assert_true(near_full > near_half, "full beats half")
	assert_true(near_full > far_full, "short trip beats long")
	assert_eq(CoverScoring.score(SETTINGS, Vector3(2, 0, 0), 0.0, me, threat, RIFLEMAN, false), -INF, "no protection")
	assert_true(CoverScoring.score(SETTINGS, Vector3(2, 0, 0), 1.0, me, threat, RIFLEMAN, true) < near_full, "taken")


func test_flank_scoring_needs_a_wide_angle() -> void:
	var me := Vector3(0, 0, 0)
	var threat := Vector3(0, 0, -20)
	var straight := CoverScoring.score(SETTINGS, Vector3(1, 0, -2), 1.0, me, threat, RIFLEMAN, false, me)
	var wide := CoverScoring.score(SETTINGS, Vector3(-18, 0, -18), 1.0, me, threat, RIFLEMAN, false, me)
	assert_eq(straight, -INF, "same line of attack is no flank")
	assert_true(wide > -INF, "around the side is")
	assert_approx(CoverScoring.flank_angle(Vector3(-20, 0, -20), me, threat), 90.0, 0.5, "right angle")


func test_grenade_arc_lands_on_target() -> void:
	var from := Vector3(0, 1.5, 0)
	for target in [Vector3(0, 0, -12), Vector3(8, 0, -20), Vector3(-5, 1.2, -8)]:
		var velocity := ThrowMath.launch_velocity(from, target, 9.81, FRAG.max_throw_speed,
				FRAG.arc_angle_min, FRAG.arc_angle_max)
		assert_true(velocity.length() <= FRAG.max_throw_speed + 0.01, "within arm strength")
		# Fly it until it comes back down to the target's height.
		var position := from
		var v := velocity
		var dt := 1.0 / 240.0
		var landed := Vector3.INF
		for i in 2400:
			v.y -= 9.81 * dt
			position += v * dt
			if v.y < 0.0 and position.y <= target.y:
				landed = position
				break
		assert_true(landed != Vector3.INF and CoverScoring.flat_distance(landed, target) < 0.3,
				"lands on %s (landed %s)" % [target, landed])


func test_out_of_reach_throw_falls_short_at_max_strength() -> void:
	var velocity := ThrowMath.launch_velocity(Vector3.ZERO, Vector3(0, 0, -200), 9.81, FRAG.max_throw_speed,
			FRAG.arc_angle_min, FRAG.arc_angle_max)
	assert_approx(velocity.length(), FRAG.max_throw_speed, 1e-3)


func test_blast_damage_falls_off_to_zero() -> void:
	assert_eq(ThrowMath.blast_damage(FRAG, 0.0), FRAG.max_damage, "centre")
	assert_true(ThrowMath.blast_damage(FRAG, 2.0) > ThrowMath.blast_damage(FRAG, 5.0), "falls off")
	assert_eq(ThrowMath.blast_damage(FRAG, FRAG.blast_radius), 0.0, "edge")
	assert_true(ThrowMath.blast_damage(FRAG, 2.0) >= 100.0, "lethal-ish up close")
