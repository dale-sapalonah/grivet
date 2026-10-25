extends "res://tests/framework/suite.gd"

const AUDIO := preload("res://data/audio/audio_settings.tres")
const SPEED_OF_SOUND := 343.0


func test_shot_layers_cross_fade_with_distance() -> void:
	var near := SoundModels.shot_mix(5.0, AUDIO)
	var mid := SoundModels.shot_mix((AUDIO.shot_distant_start + AUDIO.shot_distant_full) * 0.5, AUDIO)
	var far := SoundModels.shot_mix(AUDIO.shot_distant_full + 50.0, AUDIO)
	assert_approx(near.x, 0.0, 0.01, "close layer full up close")
	assert_true(near.y < -40.0, "no distant layer up close: %.1f" % near.y)
	assert_true(far.x < -40.0, "no close layer far away: %.1f" % far.x)
	assert_approx(far.y, AUDIO.shot_distant_db, 0.01, "distant layer full far away")
	# Equal power in the middle: both about -3 dB, no hole in the crossfade.
	assert_approx(mid.x, -3.0, 0.2, "close layer halfway")
	assert_approx(mid.y - AUDIO.shot_distant_db, -3.0, 0.2, "distant layer halfway")
	var previous := SoundModels.shot_mix(0.0, AUDIO)
	for d in range(5, 200, 5):
		var mix := SoundModels.shot_mix(d, AUDIO)
		assert_true(mix.x <= previous.x + 1e-4 and mix.y >= previous.y - 1e-4, "monotonic at %d m" % d)
		previous = mix


func _rays(distance: float, hits: int, total: int = 8) -> PackedFloat32Array:
	var rays := PackedFloat32Array()
	for i in total:
		rays.append(distance if i < hits else INF)
	return rays


func test_alley_is_tight_bright_and_wetter_than_open_ground() -> void:
	var alley := SoundModels.acoustics(_rays(2.5, 6), false, AUDIO, SPEED_OF_SOUND)
	var open := SoundModels.acoustics(_rays(30.0, 1), false, AUDIO, SPEED_OF_SOUND)
	assert_true(alley.enclosure > open.enclosure, "alley more enclosed")
	assert_true(alley.wet > open.wet, "alley wetter: %.2f vs %.2f" % [alley.wet, open.wet])
	assert_true(alley.damping < open.damping, "steel walls keep the highs")
	assert_true(alley.room_size < open.room_size, "alley is a small room")
	assert_true(alley.predelay_ms < open.predelay_ms, "slap comes back sooner in the alley")
	assert_true(open.echo_feedback > alley.echo_feedback, "open ground echoes repeat")


func test_slap_delay_is_the_round_trip_to_the_walls() -> void:
	var yard := SoundModels.acoustics(_rays(20.0, 8), false, AUDIO, SPEED_OF_SOUND)
	assert_approx(yard.predelay_ms, 2.0 * 20.0 / SPEED_OF_SOUND * 1000.0, 0.5, "20 m walls -> ~117 ms")
	var nothing := SoundModels.acoustics(_rays(0.0, 0), false, AUDIO, SPEED_OF_SOUND)
	assert_approx(nothing.enclosure, 0.0, 1e-4, "no walls at all")
	assert_true(nothing.predelay_ms <= AUDIO.max_predelay_ms, "slap clamped")
	var hugging := SoundModels.acoustics(_rays(0.3, 8), false, AUDIO, SPEED_OF_SOUND)
	assert_approx(hugging.predelay_ms, AUDIO.min_predelay_ms, 0.01, "pressed against a wall: minimum slap")


func test_a_roof_adds_reverb() -> void:
	var outside := SoundModels.acoustics(_rays(6.0, 4), false, AUDIO, SPEED_OF_SOUND)
	var under := SoundModels.acoustics(_rays(6.0, 4), true, AUDIO, SPEED_OF_SOUND)
	assert_approx(under.wet - outside.wet, AUDIO.roof_wet_bonus, 1e-4, "roof bonus")
