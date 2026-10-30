extends "res://tests/framework/suite.gd"

const FORWARD := Vector3(0, 0, -1)  # the victim looks along -Z


func test_takedown_from_behind_only_when_aware() -> void:
	var victim := Vector3.ZERO
	var behind := Vector3(0, 0, 1.2)
	var front := Vector3(0, 0, -1.2)
	var side := Vector3(1.2, 0, 0)
	assert_true(MeleeMath.can_take_down(behind, victim, FORWARD, 1.6, 70.0, true, false), "behind an aware soldier")
	assert_true(not MeleeMath.can_take_down(front, victim, FORWARD, 1.6, 70.0, true, false), "not face to face")
	assert_true(not MeleeMath.can_take_down(side, victim, FORWARD, 1.6, 70.0, true, false), "not square from the side")
	assert_true(MeleeMath.can_take_down(front, victim, FORWARD, 1.6, 70.0, false, false), "an unaware one from anywhere")
	assert_true(MeleeMath.can_take_down(front, victim, FORWARD, 1.6, 70.0, true, true), "a blinded one from anywhere")
	assert_true(not MeleeMath.can_take_down(Vector3(0, 0, 2.5), victim, FORWARD, 1.6, 70.0, false, false), "out of reach")


func test_knife_picks_the_closest_in_front() -> void:
	var at := Vector3.ZERO
	var facing := Vector3(0, 0, -1)
	var candidates: Array[Vector3] = [Vector3(0, 0, -1.5), Vector3(0.2, 0, -1.0), Vector3(0, 0, 1.0), Vector3(0, 0, -3.0)]
	assert_eq(MeleeMath.pick_target(at, facing, candidates, 1.8, 45.0), 1, "closest in front")
	var behind_only: Array[Vector3] = [Vector3(0, 0, 1.0)]
	assert_eq(MeleeMath.pick_target(at, facing, behind_only, 1.8, 45.0), -1, "nobody behind the player")
