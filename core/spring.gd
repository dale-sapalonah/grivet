class_name Spring
## Damped springs stepped in fixed small sub-steps. One step per frame goes
## unstable once delta * damping nears 2 (a stiff kick spring blew up below
## ~16 fps and flung the first-person gun off screen), so long frames are cut
## into steps of at most MAX_STEP and a hitch is capped at MAX_DELTA.

const MAX_STEP := 1.0 / 120.0
const MAX_DELTA := 0.25


## Advances (position, velocity) packed as Vector2(x, v); returns the new pair.
## A non-finite result (bad input) comes back as rest, never NaN.
static func step(state: Vector2, stiffness: float, damping: float, delta: float) -> Vector2:
	var remaining := clampf(delta, 0.0, MAX_DELTA)
	var x := state.x
	var v := state.y
	while remaining > 0.0:
		var h := minf(remaining, MAX_STEP)
		v += (-stiffness * x - damping * v) * h
		x += v * h
		remaining -= h
	if not is_finite(x) or not is_finite(v):
		return Vector2.ZERO
	return Vector2(x, v)
