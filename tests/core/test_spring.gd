extends "res://tests/framework/suite.gd"

const SpringMath := preload("res://core/spring.gd")
const STIFFNESS := 260.0  # the view-model kick spring
const DAMPING := 24.0


## Fires a kick and steps the spring at a fixed frame time; returns the largest
## displacement seen after the first frame.
func _peak_after_kick(frame_time: float, frames: int) -> float:
	var state := Vector2(0.0, 1.0)
	var peak := 0.0
	for i in frames:
		state = SpringMath.step(state, STIFFNESS, DAMPING, frame_time)
		if i > 0:
			peak = maxf(peak, absf(state.x))
	return peak


func test_kick_settles_at_low_frame_rates() -> void:
	# One explicit step per frame diverged below ~16 fps (the HIGH preset).
	for fps in [144.0, 60.0, 30.0, 16.0, 10.0, 5.0]:
		var state := Vector2(0.0, 1.0)
		for i in int(fps * 3.0):
			state = SpringMath.step(state, STIFFNESS, DAMPING, 1.0 / fps)
		assert_true(absf(state.x) < 1e-3 and absf(state.y) < 1e-2,
				"kick did not settle at %d fps: %s" % [fps, state])


func test_frame_rate_does_not_change_the_motion() -> void:
	var fast := _peak_after_kick(1.0 / 144.0, 144)
	var slow := _peak_after_kick(1.0 / 15.0, 15)
	assert_true(slow <= fast * 1.05, "15 fps peak %f above 144 fps peak %f" % [slow, fast])


func test_hitch_and_bad_input_stay_finite() -> void:
	var state := SpringMath.step(Vector2(0.1, 30.0), STIFFNESS, DAMPING, 5.0)
	assert_true(state.is_finite(), "hitch gave %s" % state)
	assert_eq(SpringMath.step(Vector2(NAN, 1.0), STIFFNESS, DAMPING, 0.016), Vector2.ZERO)
	assert_eq(SpringMath.step(Vector2(0.0, INF), STIFFNESS, DAMPING, 0.016), Vector2.ZERO)
