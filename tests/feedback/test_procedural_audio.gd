extends "res://tests/framework/suite.gd"

const SETTINGS := preload("res://data/ballistics/ballistics_settings.tres")
const KESTREL := preload("res://data/weapons/kestrel.tres")
const HAMMERHEAD := preload("res://data/weapons/hammerhead.tres")
const VANTA := preload("res://data/weapons/vanta.tres")


## Sign changes per second in a window: a rough pitch measure (low = dull).
func crossing_rate(stream: AudioStreamWAV, from: float, to: float) -> float:
	var first := int(from * stream.mix_rate)
	var last := mini(int(to * stream.mix_rate), stream.data.size() / 2)
	var crossings := 0
	var previous := stream.data.decode_s16(first * 2)
	for i in range(first + 1, last):
		var sample := stream.data.decode_s16(i * 2)
		if (sample >= 0) != (previous >= 0):
			crossings += 1
		previous = sample
	return crossings / (to - from)


func test_every_weapon_has_shot_and_mechanism_sounds() -> void:
	for weapon: WeaponDefinition in [KESTREL, HAMMERHEAD, VANTA]:
		var shot := ProceduralAudio.gunshot(weapon)
		assert_approx(ProceduralAudio.duration(shot), weapon.shot_sound_length, 0.01, "%s shot length" % weapon.id)
		assert_true(ProceduralAudio.rms(shot, 0.0, 0.05) > 0.05, "%s shot is audible" % weapon.id)
	for stream in [ProceduralAudio.magazine_out(KESTREL), ProceduralAudio.magazine_in(KESTREL),
			ProceduralAudio.bolt_release(KESTREL), ProceduralAudio.shell_insert(HAMMERHEAD)]:
		assert_true(ProceduralAudio.rms(stream, 0.0, 0.1) > 0.02, "mechanism sound audible")


func impact(surface_id: String, outcome: String, mass: float, energy: float) -> AudioStreamWAV:
	return ProceduralAudio.impact(SETTINGS.surface(surface_id), outcome, mass, energy, 0)


func test_direct_steel_hit_is_a_short_clang_not_a_bell() -> void:
	var hit := impact("steel", "stopped", 0.25, 0.75)
	assert_true(ProceduralAudio.rms(hit, 0.02, 0.15) > 0.05, "audible clang")
	assert_true(ProceduralAudio.rms(hit, 0.6, 1.0) < 0.01, "gone by 0.6 s: %.4f" % ProceduralAudio.rms(hit, 0.6, 1.0))


func test_glancing_steel_hit_resonates_longer() -> void:
	var direct := impact("steel", "stopped", 0.25, 0.5)
	var glance := impact("steel", "ricochet", 0.25, 0.5)
	var direct_tail := ProceduralAudio.rms(direct, 0.3, 0.6)
	var glance_tail := ProceduralAudio.rms(glance, 0.3, 0.6)
	assert_true(glance_tail > direct_tail * 3.0, "ricochet %.4f vs direct %.4f" % [glance_tail, direct_tail])


func test_thin_steel_rings_more_than_thick() -> void:
	var thin := impact("steel", "stopped", 0.25, 0.75)
	var thick := impact("steel", "stopped", 1.0, 0.75)
	var thin_ring := ProceduralAudio.rms(thin, 0.08, 0.3)
	var thick_ring := ProceduralAudio.rms(thick, 0.08, 0.3)
	assert_true(thin_ring > thick_ring * 2.0, "thin %.4f vs thick %.4f" % [thin_ring, thick_ring])


func test_thin_wood_crackles_and_dense_wood_thuds() -> void:
	var board := impact("wood", "penetrated", 0.2, 0.75)
	var trunk := impact("wood", "stopped", 1.0, 0.75)
	var board_rate := crossing_rate(board, 0.0, 0.08)
	var trunk_rate := crossing_rate(trunk, 0.0, 0.08)
	assert_true(board_rate > trunk_rate * 2.0, "board %.0f vs trunk %.0f crossings/s" % [board_rate, trunk_rate])


func test_heavy_rounds_crumble_concrete_longer() -> void:
	var light := impact("concrete", "stopped", 1.0, 0.25)
	var heavy := impact("concrete", "stopped", 1.0, 1.0)
	var light_debris := ProceduralAudio.rms(light, 0.25, 0.5)
	var heavy_debris := ProceduralAudio.rms(heavy, 0.25, 0.5)
	assert_true(heavy_debris > light_debris * 2.0, "heavy %.4f vs light %.4f" % [heavy_debris, light_debris])
	assert_true(ProceduralAudio.duration(heavy) > ProceduralAudio.duration(light), "longer")


## Share of a window's level below `cutoff_hz` (one-pole low-pass): how much
## of the sound is low body rather than ring or crackle.
func low_share(stream: AudioStreamWAV, from: float, to: float, cutoff_hz: float) -> float:
	var a := 1.0 - exp(-TAU * cutoff_hz / stream.mix_rate)
	var low := 0.0
	var low_total := 0.0
	var total := 0.0
	for i in range(int(from * stream.mix_rate), mini(int(to * stream.mix_rate), stream.data.size() / 2)):
		var sample := stream.data.decode_s16(i * 2) / 32767.0
		low += a * (sample - low)
		low_total += low * low
		total += sample * sample
	return sqrt(low_total / total) if total > 0.0 else 0.0


func test_concrete_carries_more_low_body_than_thin_steel() -> void:
	var steel := impact("steel", "stopped", 0.25, 0.5)
	var concrete := impact("concrete", "stopped", 1.0, 0.5)
	var steel_low := low_share(steel, 0.0, 0.1, 300.0)
	var concrete_low := low_share(concrete, 0.0, 0.1, 300.0)
	assert_true(concrete_low > steel_low, "concrete %.3f vs steel %.3f below 300 Hz" % [concrete_low, steel_low])


func test_mass_factor_follows_areal_density() -> void:
	var steel := SETTINGS.surface("steel")
	assert_approx(steel.mass_factor(0.005, false), 7850.0 * 0.005 / steel.areal_density_thick, 1e-4, "5 mm")
	assert_eq(steel.mass_factor(0.02, false), 1.0, "20 mm is thick")
	assert_eq(steel.mass_factor(0.001, true), 1.0, "solid")
	var wood := SETTINGS.surface("wood")
	assert_true(wood.mass_factor(0.05, false) < 0.3, "5 cm board is thin")
	assert_eq(wood.mass_factor(0.5, false), 1.0, "trunk is dense")


func test_light_rounds_are_quieter_and_lower() -> void:
	assert_true(SETTINGS.light_round_volume_db < 0.0, "light rounds quieter")
	assert_true(SETTINGS.light_round_pitch < SETTINGS.heavy_round_pitch, "light rounds lower")
	assert_true(VANTA.impact_energy < KESTREL.impact_energy, "pistol lighter than rifle")


func test_casings_clink_on_hard_floors_only() -> void:
	assert_true(ProceduralAudio.casing_clink(KESTREL, SETTINGS.surface("flesh")) == null, "silent on flesh")
	var on_steel := ProceduralAudio.casing_clink(KESTREL, SETTINGS.surface("steel"))
	var on_wood := ProceduralAudio.casing_clink(KESTREL, SETTINGS.surface("wood"))
	var on_concrete := ProceduralAudio.casing_clink(KESTREL, SETTINGS.surface("concrete"))
	assert_true(on_steel != null and on_concrete != null and on_wood != null, "hard floors clink")
	if on_steel != null and on_wood != null:
		assert_true(ProceduralAudio.rms(on_steel, 0.02, 0.06) > ProceduralAudio.rms(on_wood, 0.02, 0.06),
				"steel rings longer than wood")


func test_shell_hull_is_lower_than_brass() -> void:
	var concrete := SETTINGS.surface("concrete")
	var brass := ProceduralAudio.casing_clink(KESTREL, concrete)
	var hull := ProceduralAudio.casing_clink(HAMMERHEAD, concrete)
	assert_true(crossing_rate(hull, 0.0, 0.03) < crossing_rate(brass, 0.0, 0.03), "hull duller than brass")


func test_pump_forward_lands_its_clack_after_the_slide() -> void:
	var forward := ProceduralAudio.rack_forward(HAMMERHEAD)
	var slide := ProceduralAudio.rms(forward, 0.0, 0.06)
	var clack := ProceduralAudio.rms(forward, 0.07, 0.11)
	assert_true(clack > slide * 1.5, "clack %.3f louder than slide %.3f" % [clack, slide])


func test_cache_returns_the_same_stream() -> void:
	var first := ProceduralAudio.cached("test:steel",
			func() -> AudioStreamWAV: return impact("steel", "stopped", 0.5, 0.5))
	var second := ProceduralAudio.cached("test:steel",
			func() -> AudioStreamWAV: return null)
	assert_true(first == second and first != null)
