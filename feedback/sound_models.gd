class_name SoundModels
extends RefCounted
## Pure maths behind the soundscape (no nodes), so it can be tested headless:
## how a gunshot's close and distant layers mix with distance, and what reverb
## a measured space gets.


## Level offsets (dB) for a gunshot heard `distance` m away: x = close layer
## (crack, body, mechanism), y = distant layer (boom, rolling echoes). The
## close layer fades out over the crossfade; the distant one fades in. Plain
## distance fall-off is left to each player's attenuation.
static func shot_mix(distance: float, settings: AudioSettings) -> Vector2:
	var t := clampf(inverse_lerp(settings.shot_distant_start, settings.shot_distant_full, distance), 0.0, 1.0)
	# Equal-power crossfade, so the shot does not dip in the middle.
	var close := cos(t * PI * 0.5)
	var distant := sin(t * PI * 0.5)
	return Vector2(linear_to_db(maxf(close, 0.0001)), linear_to_db(maxf(distant, 0.0001)) + settings.shot_distant_db)


## Reverb for the space around the listener, from horizontal ray distances
## (INF = no wall within range) and whether there is a roof overhead.
## Returns room_size, damping, wet, predelay_ms, echo_feedback and enclosure
## (0 = open ground, 1 = walls all round).
static func acoustics(distances: PackedFloat32Array, roofed: bool, settings: AudioSettings,
		speed_of_sound: float) -> Dictionary:
	var hits := 0
	var total := 0.0
	var closeness := 0.0
	for d in distances:
		if is_finite(d):
			hits += 1
			total += d
			closeness += 1.0 - clampf(d / settings.probe_range, 0.0, 1.0)
	# Near walls count fully, far ones barely: an alley between containers is
	# enclosed, a courtyard ringed by walls 25 m away much less so.
	var enclosure := closeness / maxf(distances.size(), 1.0)
	# Typical wall distance: the walls that are there, or open range if none.
	var mean := total / hits if hits > 0 else settings.probe_range
	var size := clampf(mean / settings.probe_range, 0.0, 1.0)
	var wet := lerpf(settings.open_wet, settings.enclosed_wet, enclosure)
	if roofed:
		wet += settings.roof_wet_bonus
	# The slap comes back after a round trip to the walls.
	var predelay := clampf(2.0 * mean / speed_of_sound * 1000.0, settings.min_predelay_ms, settings.max_predelay_ms)
	return {
		"enclosure": enclosure,
		"room_size": lerpf(settings.small_room, settings.large_room, size),
		"damping": lerpf(settings.open_damping, settings.enclosed_damping, enclosure),
		"wet": clampf(wet, 0.0, 1.0),
		"predelay_ms": predelay,
		"echo_feedback": lerpf(settings.open_echo_feedback, settings.enclosed_echo_feedback, enclosure),
	}
